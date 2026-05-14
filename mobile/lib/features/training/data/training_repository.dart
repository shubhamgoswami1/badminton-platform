import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'training_models.dart';

class TrainingRepository {
  TrainingRepository(this._dio);

  final Dio _dio;

  /// Fetch the current user's training logs, newest first.
  Future<List<TrainingLog>> getMyLogs({int limit = 30}) async {
    final response = await _dio.get(
      ApiEndpoints.trainingLogs,
      queryParameters: {'limit': limit},
    );
    return unwrapList(response)
        .map((e) => TrainingLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a new training log entry.
  Future<TrainingLog> createLog(TrainingLogCreate request) async {
    final response = await _dio.post(
      ApiEndpoints.trainingLogs,
      data: request.toJson(),
    );
    return TrainingLog.fromJson(unwrap(response));
  }
}

final trainingRepositoryProvider = Provider<TrainingRepository>((ref) {
  return TrainingRepository(ref.watch(dioClientProvider));
});
