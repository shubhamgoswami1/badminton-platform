import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kQueueKey = 'score_sync_queue';

/// Thin SharedPreferences persistence for the offline score sync queue.
class ScoreQueueStore {
  Future<List<Map<String, dynamic>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueueKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> saveAll(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQueueKey, jsonEncode(entries));
  }
}
