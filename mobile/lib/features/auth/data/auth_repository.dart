import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'auth_models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(dio: ref.watch(dioClientProvider));
});

class AuthRepository {
  AuthRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Requests a new OTP for [phoneNumber].
  /// Returns the mock OTP in dev mode (when server echoes it).
  Future<String?> requestOtp(String phoneNumber) async {
    final response = await _dio.post(
      ApiEndpoints.otpRequest,
      data: {'phone_number': phoneNumber},
    );
    final data = unwrap(response);
    // Backend returns `otp` field only in mock/dev mode.
    return data['otp'] as String?;
  }

  /// Verifies [otp] for [phoneNumber] and returns tokens + user.
  Future<OtpVerifyResponse> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    final response = await _dio.post(
      ApiEndpoints.otpVerify,
      data: {'phone_number': phoneNumber, 'otp': otp},
    );
    return OtpVerifyResponse.fromJson(unwrap(response));
  }

  /// Refreshes the access token using [refreshToken].
  Future<AuthTokens> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      ApiEndpoints.tokenRefresh,
      data: {'refresh_token': refreshToken},
    );
    return AuthTokens.fromJson(unwrap(response));
  }

  /// Revokes [refreshToken] on the server (logout).
  Future<void> logout(String refreshToken) async {
    await _dio.post(
      ApiEndpoints.logout,
      data: {'refresh_token': refreshToken},
    );
  }
}
