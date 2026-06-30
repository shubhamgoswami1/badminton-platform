import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/training_models.dart';
import '../data/training_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class GoalsState {
  const GoalsState({
    this.goals = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.submitError,
  });

  final List<TrainingGoal> goals;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final String? submitError;

  GoalsState copyWith({
    List<TrainingGoal>? goals,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    String? submitError,
    bool clearError = false,
    bool clearSubmitError = false,
  }) =>
      GoalsState(
        goals: goals ?? this.goals,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        submitError:
            clearSubmitError ? null : (submitError ?? this.submitError),
      );

  // ── Derived counts ──────────────────────────────────────────────────────

  List<TrainingGoal> get activeGoals =>
      goals.where((g) => g.isActive).toList();

  List<TrainingGoal> get achievedGoals =>
      goals.where((g) => g.isAchieved).toList();

  int get totalGoals => goals.length;
  int get achievedCount => achievedGoals.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class GoalsNotifier extends StateNotifier<GoalsState> {
  GoalsNotifier(this._repo) : super(const GoalsState());

  final TrainingRepository _repo;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final goals = await _repo.getMyGoals();
      state = state.copyWith(isLoading: false, goals: goals);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load goals.',
      );
    }
  }

  Future<void> refresh() async {
    state = const GoalsState();
    await load();
  }

  Future<bool> addGoal(TrainingGoalCreate request) async {
    state = state.copyWith(isSubmitting: true, clearSubmitError: true);
    try {
      final created = await _repo.createGoal(request);
      state = state.copyWith(
        isSubmitting: false,
        goals: [created, ...state.goals],
      );
      return true;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Could not save goal. Please try again.',
      );
      return false;
    }
  }

  Future<bool> updateGoal(String id, TrainingGoalUpdate request) async {
    state = state.copyWith(isSubmitting: true, clearSubmitError: true);
    try {
      final updated = await _repo.updateGoal(id, request);
      final newList = state.goals
          .map((g) => g.id == id ? updated : g)
          .toList();
      state = state.copyWith(isSubmitting: false, goals: newList);
      return true;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Could not update goal. Please try again.',
      );
      return false;
    }
  }

  Future<void> deleteGoal(String id) async {
    try {
      await _repo.deleteGoal(id);
      state = state.copyWith(
        goals: state.goals.where((g) => g.id != id).toList(),
      );
    } catch (_) {
      // Silently ignore — user stays on the screen, list unchanged.
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final goalsProvider =
    StateNotifierProvider<GoalsNotifier, GoalsState>(
  (ref) => GoalsNotifier(ref.watch(trainingRepositoryProvider)),
);
