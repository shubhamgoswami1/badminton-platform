import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

// ── State ──────────────────────────────────────────────────────────────────

class AuthState {
  const AuthState({
    this.accessToken,
    this.userId,
    this.isLoading = false,
    this.error,
  });

  final String? accessToken;
  final String? userId;
  final bool isLoading;
  final String? error;

  bool get isLoggedIn => accessToken != null;

  AuthState copyWith({
    String? accessToken,
    String? userId,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearTokens = false,
  }) {
    return AuthState(
      accessToken: clearTokens ? null : (accessToken ?? this.accessToken),
      userId: clearTokens ? null : (userId ?? this.userId),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required AuthRepository repository,
    required TokenStorage storage,
  })  : _repository = repository,
        _storage = storage,
        super(const AuthState());

  final AuthRepository _repository;
  final TokenStorage _storage;

  // Called on app start — restore session from secure storage.
  Future<bool> restoreSession() async {
    final token = await _storage.getAccessToken();
    if (token != null) {
      state = state.copyWith(accessToken: token);
      return true;
    }
    return false;
  }

  Future<void> requestOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.requestOtp(phoneNumber);
      state = state.copyWith(isLoading: false);
    } on Exception catch (e) {
      state = state.copyWith(isLoading: false, error: _message(e));
      rethrow;
    }
  }

  Future<OtpVerifyResponse> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repository.verifyOtp(
        phoneNumber: phoneNumber,
        otp: otp,
      );
      await _storage.saveTokens(
        accessToken: result.tokens.accessToken,
        refreshToken: result.tokens.refreshToken,
      );
      state = state.copyWith(
        isLoading: false,
        accessToken: result.tokens.accessToken,
        userId: result.user.id,
      );
      return result;
    } on Exception catch (e) {
      state = state.copyWith(isLoading: false, error: _message(e));
      rethrow;
    }
  }

  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _repository.logout(refreshToken);
      } catch (_) {
        // Best-effort — clear locally regardless.
      }
    }
    await _storage.clearTokens();
    state = const AuthState();
  }

  void clearError() => state = state.copyWith(clearError: true);

  String _message(Exception e) {
    final msg = e.toString();
    if (msg.contains('400')) return 'Invalid OTP. Please try again.';
    if (msg.contains('429')) return 'Too many attempts. Please wait.';
    if (msg.contains('404')) return 'Phone number not found.';
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return 'No internet connection.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    repository: ref.watch(authRepositoryProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});

/// Convenience provider for just the access token string.
final accessTokenProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).accessToken;
});
