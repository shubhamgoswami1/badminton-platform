import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';

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

  /// True immediately after OTP verify when the backend has no player profile
  /// yet for this user.  The router uses this to send them to /onboarding.
  /// Cleared once the user completes or skips onboarding.
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
      isFirstLogin:
          clearSession ? false : (isFirstLogin ?? this.isFirstLogin),
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required AuthRepository repository,
    required TokenStorage storage,
    required ProfileRepository profileRepository,
  })  : _repository = repository,
        _storage = storage,
        _profileRepository = profileRepository,
        super(const AuthState());

  final AuthRepository _repository;
  final TokenStorage _storage;
  final ProfileRepository _profileRepository;

  /// Called on app start — restores session from secure storage into state.
  /// Also checks whether a player profile exists so the router can decide
  /// whether to show onboarding.  Returns true if a token was found.
  Future<bool> restoreSession() async {
    final token = await _storage.getAccessToken();
    if (token == null) return false;

    state = state.copyWith(accessToken: token);

    // Silently fetch /users/me to determine first-login status.
    // Any failure is swallowed — the user is still logged in.
    try {
      final data = await _profileRepository.getMe();
      state = state.copyWith(
        userId: data.user.id,
        isFirstLogin: !data.hasProfile,
      );
    } catch (_) {
      // Network unavailable on startup — treat as returning user.
    }

    return true;
  }

  /// Requests an OTP for [phoneNumber].
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

  /// Verifies [otp] for [phoneNumber], saves tokens, then calls GET /users/me
  /// to determine whether to route to onboarding.
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

      // Optimistically mark logged in, then check for existing profile.
      state = state.copyWith(
        isLoading: false,
        accessToken: tokens.accessToken,
        isFirstLogin: false, // will be updated below
      );

      try {
        final data = await _profileRepository.getMe();
        state = state.copyWith(
          userId: data.user.id,
          isFirstLogin: !data.hasProfile,
        );
      } catch (_) {
        // If profile check fails, default to not onboarding.
      }
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

  /// Called once the user has completed or explicitly skipped onboarding.
  /// Clears the isFirstLogin flag so the router stops redirecting.
  void markOnboardingComplete() {
    state = state.copyWith(isFirstLogin: false);
  }

  /// Clears tokens from storage and resets auth state.
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _repository.logout(refreshToken);
      } catch (_) {
        // Always clear locally.
      }
    }
    await _storage.clearTokens();
    state = const AuthState();
  }

  /// Clears the current error (e.g. when the user edits the phone field).
  void clearError() => state = state.copyWith(clearError: true);

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _messageFromDio(DioException e) {
    final status = e.response?.statusCode;
    if (status == 400) return 'Invalid request. Check your input.';
    if (status == 401) return 'Invalid OTP. Please try again.';
    if (status == 429) {
      return 'Too many attempts. Please wait before retrying.';
    }
    if (status == 404) return 'Phone number not recognised.';
    if (status != null && status >= 500) {
      return 'Server error. Please try again later.';
    }
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
    profileRepository: ref.watch(profileRepositoryProvider),
  );
});

/// Drives GoRouter.refreshListenable — notifies the router when auth changes.
final authListenableProvider = Provider<Listenable>((ref) {
  final notifier = _AuthChangeNotifier();
  ref.listen<AuthState>(authProvider, (_, __) => notifier.notify());
  ref.onDispose(notifier.dispose);
  return notifier;
});

class _AuthChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
