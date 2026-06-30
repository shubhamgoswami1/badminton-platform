import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'match_models.dart';

class MatchRepository {
  MatchRepository(this._dio);

  final Dio _dio;

  Future<List<Match>> getTournamentMatches(String tournamentId) async {
    final response = await _dio.get(ApiEndpoints.matches(tournamentId));
    return unwrapList(response)
        .map((e) => Match.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch all matches for the current user across all tournaments.
  /// Optional [statuses] filters by comma-joined statuses,
  /// e.g. ['PENDING', 'IN_PROGRESS'].
  Future<List<MatchWithContext>> getMyMatches({
    List<String>? statuses,
  }) async {
    final response = await _dio.get(
      ApiEndpoints.myMatches,
      queryParameters: statuses != null && statuses.isNotEmpty
          ? {'status': statuses.join(',')}
          : null,
    );
    return unwrapList(response)
        .map((e) =>
            MatchWithContext.fromMyMatchJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch full match detail (status, sets, version, elo_applied) from
  /// GET /matches/{id}. Use this instead of getMatchScore where possible.
  Future<MatchDetail> getMatchDetail(String matchId) async {
    final response = await _dio.get(ApiEndpoints.matchDetail(matchId));
    return MatchDetail.fromJson(unwrap(response));
  }

  Future<MatchScore> getMatchScore(String matchId) async {
    final response = await _dio.get(ApiEndpoints.matchScore(matchId));
    return MatchScore.fromJson(unwrap(response));
  }

  /// Save intermediate set scores without completing the match.
  /// PENDING → IN_PROGRESS (noop if already IN_PROGRESS).
  Future<MatchDetail> updateScore(
    String matchId,
    UpdateScoreRequest request,
  ) async {
    final response = await _dio.post(
      ApiEndpoints.matchUpdateScore(matchId),
      data: request.toJson(),
    );
    return MatchDetail.fromJson(unwrap(response));
  }

  /// Complete the match and apply Elo.
  /// Optionally replaces stored scores if sets are provided.
  Future<MatchDetail> completeMatch(
    String matchId,
    CompleteMatchRequest request,
  ) async {
    final response = await _dio.post(
      ApiEndpoints.matchComplete(matchId),
      data: request.toJson(),
    );
    return MatchDetail.fromJson(unwrap(response));
  }

  /// One-shot submit: sets + winner → COMPLETED.
  ///
  /// An [Idempotency-Key] header is automatically generated and sent with every
  /// POST so that network retries don't double-submit the score.
  Future<MatchDetail> submitScore(
    String matchId,
    SubmitScoreRequest request,
  ) async {
    final idempotencyKey = _generateKey();
    final response = await _dio.post(
      ApiEndpoints.matchScore(matchId),
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    // /score returns a MatchScoreResponse shape (match_id, status, sets).
    // Fallback: re-fetch via detail endpoint for full MatchDetail.
    try {
      return MatchDetail.fromJson(unwrap(response));
    } catch (_) {
      return getMatchDetail(matchId);
    }
  }
}

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return MatchRepository(ref.watch(dioClientProvider));
});

/// Simple random hex key — unique enough for idempotency within a session.
String _generateKey() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
