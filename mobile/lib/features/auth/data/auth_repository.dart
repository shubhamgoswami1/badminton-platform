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
  /// Returns the mock OTP string in dev mode (server echoes it back).
  /// Returns null in production mode (OTP is sent via SMS only).
  Future<String?> requestOtp(String phoneNumber) async {
    final response = await _dio.post(
      ApiEndpoints.otpRequest,
      data: {'phone_number': phoneNumber},
    );
    final data = unwrap(response);
    return data['otp'] as String?;
  }

  /// Verifies [otp] for [phoneNumber].
  /// Returns [AuthTokens] on success.
  /// Backend contract: {access_token, refresh_token, token_type} — no user object.
  Future<AuthTokens> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    final response = await _dio.post(
      ApiEndpoints.otpVerify,
      data: {'phone_number': phoneNumber, 'otp': otp},
    );
    return AuthTokens.fromJson(unwrap(response));
  }

  /// Rotates the refresh token. Returns a new [AuthTokens] pair.
  Future<AuthTokens> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      ApiEndpoints.tokenRefresh,
      data: {'refresh_token': refreshToken},
    );
    return AuthTokens.fromJson(unwrap(response));
  }

  /// Revokes [refreshToken] on the server (best-effort logout).
  Future<void> logout(String refreshToken) async {
    await _dio.post(
      ApiEndpoints.logout,
      data: {'refresh_token': refreshToken},
    );
  }
}
