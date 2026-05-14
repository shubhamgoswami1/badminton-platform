import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/training_models.dart';
import '../data/training_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TrainingLogsState {
  const TrainingLogsState({
    this.logs = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.submitError,
  });

  final List<TrainingLog> logs;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final String? submitError;

  TrainingLogsState copyWith({
    List<TrainingLog>? logs,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    String? submitError,
    bool clearError = false,
    bool clearSubmitError = false,
  }) =>
      TrainingLogsState(
        logs: logs ?? this.logs,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        submitError: clearSubmitError
            ? null
            : (submitError ?? this.submitError),
      );

  // ── Derived stats for the weekly summary card ──────────────────────────

  List<TrainingLog> get weekLogs {
    final cutoff =
        DateTime.now().subtract(const Duration(days: 7));
    return logs
        .where((l) => l.loggedAt.isAfter(cutoff))
        .toList();
  }

  int get weekSessionCount => weekLogs.length;

  String get weekHours {
    final mins =
        weekLogs.fold(0, (sum, l) => sum + l.durationMinutes);
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  int get streakDays {
    if (logs.isEmpty) return 0;
    final today = DateTime.now();
    final todayDate =
        DateTime(today.year, today.month, today.day);

    final logDates = logs.map((l) {
      final d = l.loggedAt.toLocal();
      return DateTime(d.year, d.month, d.day);
    }).toSet();

    // Start from today; if no log today check yesterday.
    var check = todayDate;
    if (!logDates.contains(check)) {
      check = check.subtract(const Duration(days: 1));
      if (!logDates.contains(check)) return 0;
    }

    var streak = 0;
    while (logDates.contains(check)) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TrainingLogsNotifier extends StateNotifier<TrainingLogsState> {
  TrainingLogsNotifier(this._repo) : super(const TrainingLogsState());

  final TrainingRepository _repo;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final logs = await _repo.getMyLogs();
      state = state.copyWith(isLoading: false, logs: logs);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load training logs.',
      );
    }
  }

  Future<void> refresh() async {
    state = const TrainingLogsState();
    await load();
  }

  /// Returns true on success, false on error (error stored in submitError).
  Future<bool> addLog(TrainingLogCreate request) async {
    state =
        state.copyWith(isSubmitting: true, clearSubmitError: true);
    try {
      final created = await _repo.createLog(request);
      // Prepend to the list without a full reload.
      state = state.copyWith(
        isSubmitting: false,
        logs: [created, ...state.logs],
      );
      return true;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Could not save log. Please try again.',
      );
      return false;
    }
  }

  void clearSubmitError() =>
      state = state.copyWith(clearSubmitError: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final trainingLogsProvider =
    StateNotifierProvider<TrainingLogsNotifier, TrainingLogsState>(
  (ref) => TrainingLogsNotifier(ref.watch(trainingRepositoryProvider)),
);
