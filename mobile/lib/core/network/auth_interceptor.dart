import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import 'api_endpoints.dart';

/// Attaches Bearer token to every request and handles 401 → token refresh → retry.
/// Wire this up after TokenStorage is available.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.ref});

  final Ref ref;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final storage = ref.read(tokenStorageProvider);
    final accessToken = await storage.getAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // Attempt one silent refresh.
      final storage = ref.read(tokenStorageProvider);
      final refreshToken = await storage.getRefreshToken();

      if (refreshToken == null) {
        await storage.clearTokens();
        return handler.next(err);
      }

      try {
        final refreshDio = Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
        final response = await refreshDio.post(
          ApiEndpoints.tokenRefresh,
          data: {'refresh_token': refreshToken},
        );

        final data = response.data['data'] as Map<String, dynamic>;
        final newAccess = data['access_token'] as String;
        final newRefresh = data['refresh_token'] as String;
        await storage.saveTokens(accessToken: newAccess, refreshToken: newRefresh);

        // Retry original request with new token.
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retried = await Dio().fetch(err.requestOptions);
        return handler.resolve(retried);
      } catch (_) {
        await storage.clearTokens();
        return handler.next(err);
      }
    }
    handler.next(err);
  }
}
