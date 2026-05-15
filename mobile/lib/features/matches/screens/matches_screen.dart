import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../data/match_models.dart';
import '../providers/match_provider.dart';
import '../providers/score_queue_provider.dart';

class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(allMatchesProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Matches'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Ongoing'),
              Tab(text: 'Completed'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () =>
                  ref.read(allMatchesProvider.notifier).reload(),
            ),
          ],
        ),
        body: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(allMatchesProvider);
            final isEmpty = state.upcoming.isEmpty &&
                state.ongoing.isEmpty &&
                state.completed.isEmpty;

            if (state.isLoading && isEmpty) {
              return const LoadingIndicator();
            }

            if (state.error != null && isEmpty) {
              return ErrorView(
                message: state.error!,
                onRetry: () =>
                    ref.read(allMatchesProvider.notifier).reload(),
              );
            }

            return Column(
              children: [
                const _SyncBanner(),
                Expanded(
                  child: TabBarView(
                    children: [
                      _MatchList(
                        matches: state.upcoming,
                        emptyTitle: 'No upcoming matches',
                        emptySubtitle:
                            'Scheduled matches will appear here once\nyour tournaments are in progress.',
                        onRefresh: () =>
                            ref.read(allMatchesProvider.notifier).reload(),
                      ),
                      _MatchList(
                        matches: state.ongoing,
                        emptyTitle: 'No ongoing matches',
                        emptySubtitle: 'Matches in progress will appear here.',
                        onRefresh: () =>
                            ref.read(allMatchesProvider.notifier).reload(),
                      ),
                      _MatchList(
                        matches: state.completed,
                        emptyTitle: 'No completed matches',
                        emptySubtitle:
                            'Completed match results will appear here.',
                        onRefresh: () =>
                            ref.read(allMatchesProvider.notifier).reload(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Match list ────────────────────────────────────────────────────────────────

class _MatchList extends StatelessWidget {
  const _MatchList({
    required this.matches,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onRefresh,
  });

  final List<MatchWithContext> matches;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.sports_outlined,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _MatchCard(ctx: matches[i]),
      ),
    );
  }
}

// ── Match card ────────────────────────────────────────────────────────────────

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.ctx});

  final MatchWithContext ctx;

  @override
  Widget build(BuildContext context) {
    final m = ctx.match;
    final statusColor = _matchStatusColor(m.status);
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          AppRoutes.matchDetailPath(m.id),
          extra: ctx,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: tournament + status ───────────────────────────
              Row(
                children: [
                  const Icon(Icons.emoji_events_outlined,
                      size: 13, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      ctx.tournamentTitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusBadge(status: m.status, color: statusColor),
                ],
              ),
              const SizedBox(height: 10),

              // ── Sides ──────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _SideChip(
                      label: 'Side A',
                      participantId: m.sideAParticipantId,
                      isWinner: m.winnerParticipantId != null &&
                          m.winnerParticipantId == m.sideAParticipantId,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _CentreDisplay(match: m),
                  ),
                  Expanded(
                    child: _SideChip(
                      label: 'Side B',
                      participantId: m.sideBParticipantId,
                      isWinner: m.winnerParticipantId != null &&
                          m.winnerParticipantId == m.sideBParticipantId,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Footer: round + result snippet ─────────────────────────
              Row(
                children: [
                  Text(
                    'Round ${m.round} · Match ${m.matchNumber}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  _ResultSnippet(match: m),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.color});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == MatchStatus.inProgress) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            MatchStatus.label(status),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Centre display: "vs" for pending, live dot for in-progress ────────────────

class _CentreDisplay extends StatelessWidget {
  const _CentreDisplay({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    if (match.isInProgress) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.statusInProgress,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.statusInProgress,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
    }

    return const Text(
      'vs',
      style: TextStyle(
        color: AppColors.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }
}

// ── Result snippet shown below the card ───────────────────────────────────────

class _ResultSnippet extends StatelessWidget {
  const _ResultSnippet({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    if (match.status == MatchStatus.completed ||
        match.status == MatchStatus.walkover) {
      final isWalkover = match.status == MatchStatus.walkover;
      final winnerLabel = match.winnerParticipantId == null
          ? null
          : match.winnerParticipantId == match.sideAParticipantId
              ? 'A'
              : 'B';

      if (winnerLabel == null) return const SizedBox.shrink();

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events,
              size: 12, color: AppColors.warning),
          const SizedBox(width: 3),
          Text(
            isWalkover
                ? 'Side $winnerLabel (W/O)'
                : 'Side $winnerLabel won',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

// ── Side chip ─────────────────────────────────────────────────────────────────

class _SideChip extends StatelessWidget {
  const _SideChip({
    required this.label,
    this.participantId,
    required this.isWinner,
  });

  final String label;
  final String? participantId;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isWinner
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isWinner
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isWinner) ...[
                const Icon(Icons.emoji_events,
                    size: 12, color: AppColors.warning),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      isWinner ? AppColors.primary : AppColors.onSurface,
                ),
              ),
            ],
          ),
          if (participantId != null) ...[
            const SizedBox(height: 2),
            Text(
              participantId!.substring(0, 8),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ] else
            const Text(
              'TBD',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.disabled,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Needs Sync banner ─────────────────────────────────────────────────────────

class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(scoreQueueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();

    final conflicts = queue.where((e) => e.isConflict).toList();
    final pending = queue.where((e) => e.isPending).toList();
    final hasConflicts = conflicts.isNotEmpty;

    return Material(
      color: hasConflicts
          ? AppColors.error.withValues(alpha: 0.08)
          : AppColors.warning.withValues(alpha: 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _showQueueSheet(context, ref, queue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    hasConflicts ? Icons.warning_amber_rounded : Icons.sync,
                    size: 18,
                    color:
                        hasConflicts ? AppColors.error : AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasConflicts
                          ? '${conflicts.length} sync conflict${conflicts.length > 1 ? 's' : ''} — tap to review'
                          : '${pending.length} score update${pending.length > 1 ? 's' : ''} pending sync',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: hasConflicts
                            ? AppColors.error
                            : AppColors.warning,
                      ),
                    ),
                  ),
                  if (pending.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          ref.read(scoreQueueProvider.notifier).syncAll(),
                      child: Text(
                        'Sync now',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasConflicts
                              ? AppColors.error
                              : AppColors.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: hasConflicts
                ? AppColors.error.withValues(alpha: 0.2)
                : AppColors.warning.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  void _showQueueSheet(
      BuildContext context, WidgetRef ref, List<SyncQueueEntry> queue) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SyncQueueSheet(queue: queue, queueRef: ref),
    );
  }
}

// ── Sync queue bottom sheet ───────────────────────────────────────────────────

class _SyncQueueSheet extends ConsumerWidget {
  const _SyncQueueSheet({required this.queue, required this.queueRef});

  final List<SyncQueueEntry> queue;
  final WidgetRef queueRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveQueue = ref.watch(scoreQueueProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Pending Sync (${liveQueue.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  if (liveQueue.any((e) => e.isPending))
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(scoreQueueProvider.notifier).syncAll(),
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Sync all'),
                    ),
                ],
              ),
            ),
            const Divider(),
            if (liveQueue.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'All synced!',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: liveQueue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _QueueEntryTile(entry: liveQueue[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Queue entry tile ──────────────────────────────────────────────────────────

class _QueueEntryTile extends ConsumerWidget {
  const _QueueEntryTile({required this.entry});

  final SyncQueueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConflict = entry.isConflict;
    final opLabel = entry.operationType == SyncQueueOpType.updateScore
        ? 'Update Scores'
        : 'Complete Match';
    final matchShort = entry.matchId.substring(0, 8);

    return Card(
      margin: EdgeInsets.zero,
      color: isConflict
          ? AppColors.error.withValues(alpha: 0.05)
          : AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isConflict
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.outline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isConflict ? Icons.warning_amber_rounded : Icons.cloud_upload_outlined,
              size: 18,
              color: isConflict ? AppColors.error : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$opLabel · match $matchShort…',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isConflict
                          ? AppColors.error
                          : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isConflict
                        ? _conflictLabel(entry.conflictType)
                        : 'Waiting to sync…',
                    style: TextStyle(
                      fontSize: 11,
                      color: isConflict
                          ? AppColors.error
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Dismiss',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: AppColors.onSurfaceVariant,
              onPressed: () =>
                  ref.read(scoreQueueProvider.notifier).dismiss(entry.id),
            ),
          ],
        ),
      ),
    );
  }

  String _conflictLabel(String? conflictType) {
    if (conflictType == 'MATCH_COMPLETED') {
      return 'Match already completed on server — dismiss to clear';
    }
    if (conflictType == 'STALE_UPDATE') {
      return 'Scores updated by another device — dismiss to clear';
    }
    return 'Sync conflict — dismiss to clear';
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _matchStatusColor(String status) {
  switch (status) {
    case MatchStatus.inProgress:
      return AppColors.statusInProgress;
    case MatchStatus.completed:
      return AppColors.statusCompleted;
    case MatchStatus.walkover:
      return AppColors.statusCancelled;
    case MatchStatus.bye:
      return AppColors.statusDraft;
    default:
      return AppColors.onSurfaceVariant;
  }
}
