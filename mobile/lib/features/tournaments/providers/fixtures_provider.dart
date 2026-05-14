import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../matches/data/match_models.dart';
import '../../matches/data/match_repository.dart';
import '../data/tournament_models.dart';
import '../data/tournament_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tournament fixtures + standings — family keyed by tournamentId
// ─────────────────────────────────────────────────────────────────────────────

class TournamentFixturesState {
  const TournamentFixturesState({
    this.matches = const [],
    this.standings = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Match> matches;
  final List<StandingEntry> standings;
  final bool isLoading;
  final String? error;

  TournamentFixturesState copyWith({
    List<Match>? matches,
    List<StandingEntry>? standings,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      TournamentFixturesState(
        matches: matches ?? this.matches,
        standings: standings ?? this.standings,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );

  /// Matches grouped by round number; each round's matches sorted by matchNumber.
  Map<int, List<Match>> get byRound {
    final map = <int, List<Match>>{};
    for (final m in matches) {
      map.putIfAbsent(m.round, () => []).add(m);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    }
    return map;
  }

  int get maxRound =>
      matches.isEmpty
          ? 0
          : matches.map((m) => m.round).reduce((a, b) => a > b ? a : b);
}

class TournamentFixturesNotifier
    extends StateNotifier<TournamentFixturesState> {
  TournamentFixturesNotifier(
    this._matchRepo,
    this._tournamentRepo,
    this._tournamentId,
  ) : super(const TournamentFixturesState());

  final MatchRepository _matchRepo;
  final TournamentRepository _tournamentRepo;
  final String _tournamentId;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Load matches and standings in parallel; standings 409 for KO is normal.
      final results = await Future.wait([
        _matchRepo.getTournamentMatches(_tournamentId),
        _loadStandingsSafe(),
      ]);

      final matches = results[0] as List<Match>;
      final standings = results[1] as List<StandingEntry>;

      matches.sort((a, b) {
        final r = a.round.compareTo(b.round);
        return r != 0 ? r : a.matchNumber.compareTo(b.matchNumber);
      });

      state = state.copyWith(
        isLoading: false,
        matches: matches,
        standings: standings,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load fixtures.',
      );
    }
  }

  /// Loads standings and swallows 409 (knockout tournament) and network errors
  /// so they don't fail the whole fixtures load.
  Future<List<StandingEntry>> _loadStandingsSafe() async {
    try {
      return await _tournamentRepo.getStandings(_tournamentId);
    } on DioException catch (e) {
      // 409 = not a round-robin tournament — expected, not an error.
      if (e.response?.statusCode == 409) return [];
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> reload() async {
    state = const TournamentFixturesState();
    await load();
  }
}

final tournamentFixturesProvider = StateNotifierProvider.family<
    TournamentFixturesNotifier, TournamentFixturesState, String>(
  (ref, tournamentId) => TournamentFixturesNotifier(
    ref.watch(matchRepositoryProvider),
    ref.watch(tournamentRepositoryProvider),
    tournamentId,
  ),
);
