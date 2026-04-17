import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_endpoints.dart';
import 'auth_interceptor.dart';

final dioClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.addAll([
    AuthInterceptor(ref: ref),
    LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => _log(obj.toString()),
    ),
  ]);

  return dio;
});

void _log(String message) {
  // ignore: avoid_print
  assert(() {
    // ignore: avoid_print
    print('[DioClient] $message');
    return true;
  }());
}

/// Extracts `response.data['data']` from the standard envelope.
/// Throws if the envelope has a non-null `error` field.
Map<String, dynamic> unwrap(Response response) {
  final body = response.data as Map<String, dynamic>;
  final err = body['error'];
  if (err != null) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: (err as Map<String, dynamic>)['message']?.toString(),
    );
  }
  return body['data'] as Map<String, dynamic>;
}

List<dynamic> unwrapList(Response response) {
  final body = response.data as Map<String, dynamic>;
  return body['data'] as List<dynamic>;
}
