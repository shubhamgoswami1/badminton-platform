// Auth data models — aligned with actual backend response contracts.
// Backend /auth/otp/verify returns: {access_token, refresh_token, token_type}
// There is no `user` object in the verify response (backend P1 contract).
// First-login detection is deferred to P2 via GET /users/me profile check.

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'bearer',
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
      );

  final String accessToken;
  final String refreshToken;
  final String tokenType;
}
