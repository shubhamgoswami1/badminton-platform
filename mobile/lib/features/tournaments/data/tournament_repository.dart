import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'tournament_models.dart';

class TournamentRepository {
  TournamentRepository(this._dio);

  final Dio _dio;

  // ── Create ────────────────────────────────────────────────────────────

  Future<Tournament> createTournament(CreateTournamentRequest data) async {
    final response = await _dio.post(
      ApiEndpoints.tournaments,
      data: data.toJson(),
    );
    return Tournament.fromJson(unwrap(response));
  }

  // ── Read ──────────────────────────────────────────────────────────────

  Future<Tournament> getTournament(String id) async {
    final response = await _dio.get(ApiEndpoints.tournament(id));
    return Tournament.fromJson(unwrap(response));
  }

  Future<PaginatedTournaments> getNearbyTournaments({
    required double lat,
    required double lng,
    double radiusKm = 50,
  }) async {
    final response = await _dio.get(
      ApiEndpoints.tournamentsNearby,
      queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius_km': radiusKm,
      },
    );
    return PaginatedTournaments.fromJson(unwrap(response));
  }

  Future<List<Tournament>> getMyHosted() async {
    final response = await _dio.get(ApiEndpoints.tournamentsMyHosted);
    return unwrapList(response)
        .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Tournament>> getMyJoined() async {
    final response = await _dio.get(ApiEndpoints.tournamentsMyJoined);
    return unwrapList(response)
        .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Join ──────────────────────────────────────────────────────────────

  Future<void> joinTournament(
    String tournamentId, {
    String? partnerUserId,
  }) async {
    final body = <String, dynamic>{};
    if (partnerUserId != null) body['partner_user_id'] = partnerUserId;
    await _dio.post(
      ApiEndpoints.participants(tournamentId),
      data: body,
    );
  }
}

final tournamentRepositoryProvider = Provider<TournamentRepository>((ref) {
  return TournamentRepository(ref.watch(dioClientProvider));
});
