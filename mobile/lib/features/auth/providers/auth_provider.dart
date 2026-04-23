import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';

// ── State ──────────────────────────────────────────────────────────────────

class AuthState {
  const AuthState({
    this.accessToken,
    this.userId,
    this.isLoading = false,
    this.error,
    this.isFirstLogin = false,
  });

  final String? accessToken;
  final String? userId;
  final bool isLoading;
  final String? error;

  /// True immediately after OTP verify when this is a brand-new account.
  /// Set to false once the user has completed profile onboarding (P2).
  /// Currently always false — will be populated in P2 via GET /users/me.
  final bool isFirstLogin;

  bool get isLoggedIn => accessToken != null;

  AuthState copyWith({
    String? accessToken,
    String? userId,
    bool? isLoading,
    String? error,
    bool? isFirstLogin,
    bool clearError = false,
    bool clearSession = false,
  }) {
    return AuthState(
      accessToken: clearSession ? null : (accessToken ?? this.accessToken),
      userId: clearSession ? null : (userId ?? this.userId),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isFirstLogin: clearSession ? false : (isFirstLogin ?? this.isFirstLogin),
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

  /// Called on app start — restores session from secure storage into state.
  /// Returns true if a stored token was found.
  Future<bool> restoreSession() async {
    final token = await _storage.getAccessToken();
    if (token != null) {
      state = state.copyWith(accessToken: token);
      return true;
    }
    return false;
  }

  /// Requests an OTP for [phoneNumber].
  /// On success, navigating to the OTP screen is the caller's responsibility.
  Future<void> requestOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.requestOtp(phoneNumber);
      state = state.copyWith(isLoading: false);
    } on DioException catch (e) {
      final msg = _messageFromDio(e);
      state = state.copyWith(isLoading: false, error: msg);
      rethrow;
    } on Exception catch (_) {
      const msg = 'Something went wrong. Please try again.';
      state = state.copyWith(isLoading: false, error: msg);
      rethrow;
    }
  }

  /// Verifies [otp] for [phoneNumber], saves tokens to secure storage,
  /// and updates auth state on success.
  Future<void> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tokens = await _repository.verifyOtp(
        phoneNumber: phoneNumber,
        otp: otp,
      );
      await _storage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      // isFirstLogin will be determined in P2 via GET /users/me profile check.
      state = state.copyWith(
        isLoading: false,
        accessToken: tokens.accessToken,
      );
    } on DioException catch (e) {
      final msg = _messageFromDio(e);
      state = state.copyWith(isLoading: false, error: msg);
      rethrow;
    } on Exception catch (_) {
      const msg = 'Something went wrong. Please try again.';
      state = state.copyWith(isLoading: false, error: msg);
      rethrow;
    }
  }

  /// Clears tokens from storage and resets auth state.
  /// Best-effort revoke on server — always clears locally.
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _repository.logout(refreshToken);
      } catch (_) {
        // Intentional: clear locally even if server revoke fails.
      }
    }
    await _storage.clearTokens();
    state = const AuthState();
  }

  /// Clears the current error from state (e.g. when user edits the phone field).
  void clearError() => state = state.copyWith(clearError: true);

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _messageFromDio(DioException e) {
    final status = e.response?.statusCode;
    if (status == 400) return 'Invalid request. Check your input.';
    if (status == 401) return 'Invalid OTP. Please try again.';
    if (status == 429) return 'Too many attempts. Please wait before retrying.';
    if (status == 404) return 'Phone number not recognised.';
    if (status != null && status >= 500) return 'Server error. Please try again later.';

    // Network-level errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Connection timed out. Check your internet.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No internet connection.';
    }

    return 'Something went wrong. Please try again.';
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    repository: ref.watch(authRepositoryProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});

/// Notifies go_router whenever auth state changes so redirect is re-evaluated.
/// Used as `GoRouter(refreshListenable: ref.watch(authListenableProvider))`.
final authListenableProvider = Provider<Listenable>((ref) {
  final notifier = _AuthChangeNotifier();
  ref.listen<AuthState>(authProvider, (_, __) => notifier.notify());
  ref.onDispose(notifier.dispose);
  return notifier;
});

class _AuthChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
