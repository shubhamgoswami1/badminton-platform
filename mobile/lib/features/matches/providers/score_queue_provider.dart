import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/match_models.dart';
import '../data/match_repository.dart';
import '../data/score_queue_store.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final scoreQueueProvider =
    StateNotifierProvider<ScoreQueueNotifier, List<SyncQueueEntry>>(
  (ref) => ScoreQueueNotifier(
    ScoreQueueStore(),
    ref.watch(matchRepositoryProvider),
  ),
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class ScoreQueueNotifier extends StateNotifier<List<SyncQueueEntry>> {
  ScoreQueueNotifier(this._store, this._repo) : super(const []) {
    _init();
  }

  final ScoreQueueStore _store;
  final MatchRepository _repo;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Future<void> _init() async {
    final raw = await _store.loadAll();
    if (mounted) {
      state = raw.map(SyncQueueEntry.fromJson).toList();
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) syncAll();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Queue mutations ─────────────────────────────────────────────────────────

  Future<void> enqueueUpdateScore({
    required String matchId,
    required List<SetScoreInput> sets,
  }) async {
    final entry = SyncQueueEntry(
      id: '${matchId}_UPDATE_${DateTime.now().millisecondsSinceEpoch}',
      matchId: matchId,
      operationType: SyncQueueOpType.updateScore,
      sets: sets.map((s) => s.toJson()).toList(),
      localTimestamp: DateTime.now().toUtc().toIso8601String(),
      status: SyncQueueEntryStatus.pending,
    );
    _upsert(entry);
    await _save();
  }

  Future<void> enqueueCompleteMatch({
    required String matchId,
    required String winnerParticipantId,
    List<SetScoreInput>? sets,
  }) async {
    final entry = SyncQueueEntry(
      id: '${matchId}_COMPLETE_${DateTime.now().millisecondsSinceEpoch}',
      matchId: matchId,
      operationType: SyncQueueOpType.completeMatch,
      sets: sets?.map((s) => s.toJson()).toList() ?? [],
      winnerParticipantId: winnerParticipantId,
      localTimestamp: DateTime.now().toUtc().toIso8601String(),
      status: SyncQueueEntryStatus.pending,
    );
    _upsert(entry);
    await _save();
  }

  void dismiss(String entryId) {
    state = state.where((e) => e.id != entryId).toList();
    _save();
  }

  void removeForMatch(String matchId) {
    final updated = state.where((e) => e.matchId != matchId).toList();
    if (updated.length != state.length) {
      state = updated;
      _save();
    }
  }

  // ── Sync ────────────────────────────────────────────────────────────────────

  Future<void> syncAll() async {
    final pending = state.where((e) => e.isPending).toList();
    if (pending.isEmpty) return;

    // Keep only the latest entry per matchId (discard superseded updates).
    final Map<String, SyncQueueEntry> latest = {};
    for (final e in pending) {
      final existing = latest[e.matchId];
      if (existing == null ||
          e.localTimestamp.compareTo(existing.localTimestamp) > 0) {
        latest[e.matchId] = e;
      }
    }

    // Remove superseded entries from state before syncing.
    final supersededIds = pending
        .where((e) => latest[e.matchId]!.id != e.id)
        .map((e) => e.id)
        .toSet();
    if (supersededIds.isNotEmpty && mounted) {
      state = state.where((e) => !supersededIds.contains(e.id)).toList();
      await _save();
    }

    for (final entry in latest.values) {
      if (!mounted) break;
      await _syncEntry(entry);
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Replace any existing entry for the same matchId + operationType,
  /// then append the new one (latest wins).
  void _upsert(SyncQueueEntry entry) {
    final filtered = state
        .where((e) =>
            !(e.matchId == entry.matchId &&
              e.operationType == entry.operationType))
        .toList();
    state = [...filtered, entry];
  }

  Future<void> _syncEntry(SyncQueueEntry entry) async {
    try {
      if (entry.operationType == SyncQueueOpType.updateScore) {
        final req = UpdateScoreRequest(
          sets: entry.sets.map(SetScoreInput.fromJson).toList(),
          // No clientUpdatedAt for queued ops — we don't know the server version.
        );
        await _repo.updateScore(entry.matchId, req);
      } else {
        final req = CompleteMatchRequest(
          winnerParticipantId: entry.winnerParticipantId!,
          sets: entry.sets.isEmpty
              ? null
              : entry.sets.map(SetScoreInput.fromJson).toList(),
        );
        await _repo.completeMatch(entry.matchId, req);
      }
      // Success — remove from queue.
      removeForMatch(entry.matchId);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) {
        final body = e.response?.data as Map<String, dynamic>?;
        final errObj = body?['error'] as Map<String, dynamic>?;
        if (errObj?['code'] == 'SYNC_CONFLICT' && mounted) {
          final conflictType =
              errObj?['conflict_type'] as String? ?? 'MATCH_COMPLETED';
          final message =
              errObj?['message'] as String? ?? 'Sync conflict';
          state = state.map((en) {
            if (en.id == entry.id) {
              return en.copyWith(
                status: SyncQueueEntryStatus.conflict,
                conflictType: conflictType,
                conflictMessage: message,
              );
            }
            return en;
          }).toList();
          await _save();
        }
      }
      // Other errors: leave as pending to retry next time we come online.
    }
  }

  Future<void> _save() async {
    await _store.saveAll(state.map((e) => e.toJson()).toList());
  }
}
