import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_models.dart';
import '../data/profile_repository.dart';

// ── State ──────────────────────────────────────────────────────────────────

/// Holds the full user+profile snapshot plus loading/error state.
class ProfileState {
  const ProfileState({
    this.userWithProfile,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  final UserWithProfile? userWithProfile;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  PlayerProfile? get profile => userWithProfile?.profile;

  ProfileState copyWith({
    UserWithProfile? userWithProfile,
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) =>
      ProfileState(
        userWithProfile: userWithProfile ?? this.userWithProfile,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier(this._repository) : super(const ProfileState());

  final ProfileRepository _repository;

  /// Loads the current user + profile from the backend.
  /// Safe to call multiple times (guards against concurrent fetches).
  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _repository.getMe();
      state = state.copyWith(isLoading: false, userWithProfile: data);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load profile. Pull to refresh.',
      );
    }
  }

  /// Saves/upserts profile fields to the backend.
  /// On success the local snapshot is updated in-place.
  Future<bool> save(ProfileUpdateRequest req) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _repository.updateProfile(req);
      // Patch the cached UserWithProfile with the new profile.
      final prev = state.userWithProfile;
      if (prev != null) {
        state = state.copyWith(
          isSaving: false,
          userWithProfile: UserWithProfile(
            user: prev.user,
            profile: updated,
          ),
        );
      } else {
        state = state.copyWith(isSaving: false);
      }
      return true;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        error: 'Could not save profile. Please try again.',
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ── Provider ───────────────────────────────────────────────────────────────

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier(ref.watch(profileRepositoryProvider));
});
