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
    this.participantNames = const {},
    this.isLoading = false,
    this.error,
  });

  final List<Match> matches;
  final List<StandingEntry> standings;
  /// Maps participantId → display label (e.g. "Alice" or "Alice & Bob" for doubles).
  final Map<String, String> participantNames;
  final bool isLoading;
  final String? error;

  TournamentFixturesState copyWith({
    List<Match>? matches,
    List<StandingEntry>? standings,
    Map<String, String>? participantNames,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      TournamentFixturesState(
        matches: matches ?? this.matches,
        standings: standings ?? this.standings,
        participantNames: participantNames ?? this.participantNames,
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
      // Load matches, standings, and participants in parallel.
      // Standings 409 for KO is normal; participants failure is non-fatal.
      final results = await Future.wait([
        _matchRepo.getTournamentMatches(_tournamentId),
        _loadStandingsSafe(),
        _loadParticipantsSafe(),
      ]);

      final matches = results[0] as List<Match>;
      final standings = results[1] as List<StandingEntry>;
      final participants = results[2] as List<TournamentParticipant>;

      matches.sort((a, b) {
        final r = a.round.compareTo(b.round);
        return r != 0 ? r : a.matchNumber.compareTo(b.matchNumber);
      });

      // Build participantId → display label map.
      final nameMap = <String, String>{
        for (final p in participants) p.id: p.matchLabel,
      };

      state = state.copyWith(
        isLoading: false,
        matches: matches,
        standings: standings,
        participantNames: nameMap,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load fixtures.',
      );
    }
  }

  /// Loads participants and swallows errors so they don't fail the whole load.
  Future<List<TournamentParticipant>> _loadParticipantsSafe() async {
    try {
      return await _tournamentRepo.getParticipants(_tournamentId);
    } catch (_) {
      return [];
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
