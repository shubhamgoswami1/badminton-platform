// Simple data models for the auth feature.
// No code-gen needed — plain Dart classes with factory constructors.

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );

  final String accessToken;
  final String refreshToken;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.phoneNumber,
    required this.isNewUser,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        phoneNumber: json['phone_number'] as String,
        isNewUser: json['is_new_user'] as bool? ?? false,
      );

  final String id;
  final String phoneNumber;
  final bool isNewUser;
}

class OtpVerifyResponse {
  const OtpVerifyResponse({
    required this.tokens,
    required this.user,
  });

  factory OtpVerifyResponse.fromJson(Map<String, dynamic> json) =>
      OtpVerifyResponse(
        tokens: AuthTokens.fromJson(json),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final AuthTokens tokens;
  final AuthUser user;
}
