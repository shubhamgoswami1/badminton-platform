import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'training_models.dart';

class TrainingRepository {
  TrainingRepository(this._dio);

  final Dio _dio;

  // ── Logs ──────────────────────────────────────────────────────────────────

  Future<List<TrainingLog>> getMyLogs({int limit = 30}) async {
    final response = await _dio.get(
      ApiEndpoints.trainingLogs,
      queryParameters: {'limit': limit},
    );
    return unwrapList(response)
        .map((e) => TrainingLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TrainingLog> createLog(TrainingLogCreate request) async {
    final response = await _dio.post(
      ApiEndpoints.trainingLogs,
      data: request.toJson(),
    );
    return TrainingLog.fromJson(unwrap(response));
  }

  // ── Goals ─────────────────────────────────────────────────────────────────

  Future<List<TrainingGoal>> getMyGoals({int limit = 50}) async {
    final response = await _dio.get(
      ApiEndpoints.trainingGoals,
      queryParameters: {'limit': limit},
    );
    return unwrapList(response)
        .map((e) => TrainingGoal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TrainingGoal> createGoal(TrainingGoalCreate request) async {
    final response = await _dio.post(
      ApiEndpoints.trainingGoals,
      data: request.toJson(),
    );
    return TrainingGoal.fromJson(unwrap(response));
  }

  Future<TrainingGoal> updateGoal(String id, TrainingGoalUpdate request) async {
    final response = await _dio.put(
      ApiEndpoints.trainingGoal(id),
      data: request.toJson(),
    );
    return TrainingGoal.fromJson(unwrap(response));
  }

  Future<void> deleteGoal(String id) async {
    await _dio.delete(ApiEndpoints.trainingGoal(id));
  }
}

final trainingRepositoryProvider = Provider<TrainingRepository>((ref) {
  return TrainingRepository(ref.watch(dioClientProvider));
});
