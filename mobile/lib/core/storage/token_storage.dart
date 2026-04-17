import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyAccessToken = 'access_token';
const _keyRefreshToken = 'refresh_token';
const _keyIsLoggedIn = 'is_logged_in';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

/// Wraps flutter_secure_storage for tokens and SharedPreferences for
/// non-sensitive flags like `is_logged_in`.
class TokenStorage {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _secure.write(key: _keyAccessToken, value: accessToken),
      _secure.write(key: _keyRefreshToken, value: refreshToken),
      _setLoggedIn(true),
    ]);
  }

  Future<String?> getAccessToken() => _secure.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _secure.read(key: _keyRefreshToken);

  Future<void> saveAccessToken(String token) =>
      _secure.write(key: _keyAccessToken, value: token);

  Future<void> clearTokens() async {
    await Future.wait([
      _secure.delete(key: _keyAccessToken),
      _secure.delete(key: _keyRefreshToken),
      _setLoggedIn(false),
    ]);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  Future<void> _setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, value);
  }
}
