import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'discovery_models.dart';

class DiscoveryRepository {
  DiscoveryRepository(this._dio);

  final Dio _dio;

  Future<({List<PlayerSearchResult> items, int total})> searchPlayers({
    String? query,
    double? eloMin,
    double? eloMax,
    double? lat,
    double? lng,
    double? radiusKm,
    int limit = 30,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    if (query != null && query.isNotEmpty) params['q'] = query;
    if (eloMin != null) params['elo_min'] = eloMin;
    if (eloMax != null) params['elo_max'] = eloMax;
    if (lat != null && lng != null && radiusKm != null) {
      params['lat'] = lat;
      params['lng'] = lng;
      params['radius_km'] = radiusKm;
    }

    final response = await _dio.get(
      ApiEndpoints.discoverPlayers,
      queryParameters: params,
    );
    final body = response.data as Map<String, dynamic>;
    final dataList = body['data'] as List<dynamic>;
    final total = (body['meta'] as Map<String, dynamic>)['total'] as int;
    return (
      items: dataList
          .map((e) => PlayerSearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: total,
    );
  }

  Future<List<Venue>> getVenues({String? city, int limit = 50}) async {
    final params = <String, dynamic>{'limit': limit};
    if (city != null && city.isNotEmpty) params['city'] = city;

    final response = await _dio.get(
      ApiEndpoints.venues,
      queryParameters: params,
    );
    final body = response.data as Map<String, dynamic>;
    final dataList = body['data'] as List<dynamic>;
    return dataList
        .map((e) => Venue.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<({List<DiscoveryTournament> items, int total})> discoverTournaments({
    String? city,
    String? status,
    String? format,
    int limit = 30,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (city != null && city.isNotEmpty) params['city'] = city;
    if (status != null) params['status'] = status;
    if (format != null) params['format'] = format;

    final response = await _dio.get(
      ApiEndpoints.discoverTournaments,
      queryParameters: params,
    );
    final body = response.data as Map<String, dynamic>;
    final dataList = body['data'] as List<dynamic>;
    final total = (body['meta'] as Map<String, dynamic>)['total'] as int;
    return (
      items: dataList
          .map((e) => DiscoveryTournament.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: total,
    );
  }

  Future<Venue> submitVenue(VenueCreate data) async {
    final response = await _dio.post(
      ApiEndpoints.venues,
      data: data.toJson(),
    );
    final body = response.data as Map<String, dynamic>;
    return Venue.fromJson(body['data'] as Map<String, dynamic>);
  }
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository(ref.watch(dioClientProvider));
});
