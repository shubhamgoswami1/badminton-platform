import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/match_models.dart';
import '../data/match_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// All matches — backed by GET /matches/my
// ─────────────────────────────────────────────────────────────────────────────

class AllMatchesState {
  const AllMatchesState({
    this.upcoming = const [],
    this.ongoing = const [],
    this.completed = const [],
    this.isLoading = false,
    this.error,
  });

  final List<MatchWithContext> upcoming;
  final List<MatchWithContext> ongoing;
  final List<MatchWithContext> completed;
  final bool isLoading;
  final String? error;

  AllMatchesState copyWith({
    List<MatchWithContext>? upcoming,
    List<MatchWithContext>? ongoing,
    List<MatchWithContext>? completed,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      AllMatchesState(
        upcoming: upcoming ?? this.upcoming,
        ongoing: ongoing ?? this.ongoing,
        completed: completed ?? this.completed,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AllMatchesNotifier extends StateNotifier<AllMatchesState> {
  AllMatchesNotifier(this._repo) : super(const AllMatchesState());

  final MatchRepository _repo;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final all = await _repo.getMyMatches();

      final upcoming = <MatchWithContext>[];
      final ongoing = <MatchWithContext>[];
      final completed = <MatchWithContext>[];

      for (final ctx in all) {
        if (ctx.match.isPending) {
          upcoming.add(ctx);
        } else if (ctx.match.isInProgress) {
          ongoing.add(ctx);
        } else if (ctx.match.isDone) {
          completed.add(ctx);
        }
      }

      state = state.copyWith(
        isLoading: false,
        upcoming: upcoming,
        ongoing: ongoing,
        completed: completed,
      );
    } on DioException {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load matches.',
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load matches.',
      );
    }
  }

  Future<void> reload() async {
    state = const AllMatchesState();
    await load();
  }
}

final allMatchesProvider =
    StateNotifierProvider<AllMatchesNotifier, AllMatchesState>(
  (ref) => AllMatchesNotifier(ref.watch(matchRepositoryProvider)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Match detail — loads full detail, handles update-score and complete
// (family by matchId)
// ─────────────────────────────────────────────────────────────────────────────

class MatchDetailState {
  const MatchDetailState({
    this.matchDetail,
    this.isLoading = false,
    this.isUpdating = false,
    this.isCompleting = false,
    this.error,
    this.updateError,
    this.completeError,
  });

  final MatchDetail? matchDetail;
  final bool isLoading;
  final bool isUpdating;
  final bool isCompleting;
  final String? error;
  final String? updateError;
  final String? completeError;

  /// True whenever any mutating operation is in flight.
  bool get isBusy => isLoading || isUpdating || isCompleting;

  /// Backward-compat: callers that check isSubmitting still work.
  bool get isSubmitting => isUpdating || isCompleting;

  /// Backward-compat: score submitted iff the match is now done.
  bool get submitted =>
      matchDetail != null && matchDetail!.isDone;

  /// Backward-compat: expose as MatchScore for callers that used matchScore.
  MatchScore? get matchScore => matchDetail == null
      ? null
      : MatchScore(
          matchId: matchDetail!.id,
          status: matchDetail!.status,
          winnerParticipantId: matchDetail!.winnerParticipantId,
          sets: matchDetail!.sortedSets,
        );

  MatchDetailState copyWith({
    MatchDetail? matchDetail,
    bool? isLoading,
    bool? isUpdating,
    bool? isCompleting,
    String? error,
    String? updateError,
    String? completeError,
    bool clearError = false,
    bool clearUpdateError = false,
    bool clearCompleteError = false,
  }) =>
      MatchDetailState(
        matchDetail: matchDetail ?? this.matchDetail,
        isLoading: isLoading ?? this.isLoading,
        isUpdating: isUpdating ?? this.isUpdating,
        isCompleting: isCompleting ?? this.isCompleting,
        error: clearError ? null : (error ?? this.error),
        updateError:
            clearUpdateError ? null : (updateError ?? this.updateError),
        completeError:
            clearCompleteError ? null : (completeError ?? this.completeError),
      );
}

class MatchDetailNotifier extends StateNotifier<MatchDetailState> {
  MatchDetailNotifier(this._repo, this._matchId)
      : super(const MatchDetailState());

  final MatchRepository _repo;
  final String _matchId;

  /// Fetch full match detail from GET /matches/{id}.
  Future<void> loadDetail() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final detail = await _repo.getMatchDetail(_matchId);
      state = state.copyWith(isLoading: false, matchDetail: detail);
    } catch (e) {
      // Graceful degradation: 404 is unexpected here but handle it.
      if (e is DioException && e.response?.statusCode == 404) {
        state = state.copyWith(isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not load match details.',
        );
      }
    }
  }

  /// Backward-compat alias used by initState callers.
  Future<void> loadScore() => loadDetail();

  /// Save intermediate scores without completing (PENDING → IN_PROGRESS).
  /// Returns true on success.
  Future<bool> updateScore(UpdateScoreRequest request) async {
    state = state.copyWith(isUpdating: true, clearUpdateError: true);
    try {
      final detail = await _repo.updateScore(_matchId, request);
      state = state.copyWith(isUpdating: false, matchDetail: detail);
      return true;
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateError: _errorMessage(e, {
          403: 'You are not authorised to update this match.',
          409: 'Match is already finished.',
        }),
      );
      return false;
    }
  }

  /// Complete the match with a winner (IN_PROGRESS / PENDING → COMPLETED).
  /// Optionally replaces stored scores.
  /// Returns true on success.
  Future<bool> completeMatch(CompleteMatchRequest request) async {
    state = state.copyWith(isCompleting: true, clearCompleteError: true);
    try {
      final detail = await _repo.completeMatch(_matchId, request);
      state = state.copyWith(isCompleting: false, matchDetail: detail);
      return true;
    } catch (e) {
      state = state.copyWith(
        isCompleting: false,
        completeError: _errorMessage(e, {
          403: 'You are not authorised to complete this match.',
          409: 'Match already has a result.',
          422: 'Invalid input. Check scores and winner.',
        }),
      );
      return false;
    }
  }

  /// One-shot submit (PENDING → COMPLETED) kept for backward compatibility.
  Future<bool> submit(SubmitScoreRequest request) async {
    state = state.copyWith(isUpdating: true, clearUpdateError: true);
    try {
      final detail = await _repo.submitScore(_matchId, request);
      state = state.copyWith(isUpdating: false, matchDetail: detail);
      return true;
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateError: _errorMessage(e, {
          403: 'You are not authorised to submit this score.',
          409: 'Score already submitted for this match.',
          422: 'Invalid scores. Please check your input.',
        }),
      );
      return false;
    }
  }

  void clearUpdateError() => state = state.copyWith(clearUpdateError: true);
  void clearCompleteError() => state = state.copyWith(clearCompleteError: true);

  /// Backward-compat alias.
  void clearSubmitError() => clearUpdateError();
}

String _errorMessage(Object e, Map<int, String> codeMessages) {
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code != null && codeMessages.containsKey(code)) {
      return codeMessages[code]!;
    }
  }
  return 'Something went wrong. Please try again.';
}

final matchDetailProvider = StateNotifierProvider.family<MatchDetailNotifier,
    MatchDetailState, String>(
  (ref, matchId) =>
      MatchDetailNotifier(ref.watch(matchRepositoryProvider), matchId),
);
