import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/match_models.dart';
import '../providers/match_provider.dart';

class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({super.key, required this.matchContext});

  final MatchWithContext matchContext;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(matchDetailProvider(widget.matchContext.match.id).notifier)
          .loadDetail(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchCtx = widget.matchContext;
    final match = matchCtx.match;
    final detailState = ref.watch(matchDetailProvider(match.id));

    // Use the live detail from server if available; fall back to the match
    // passed via navigation extra (may be stale).
    final liveStatus = detailState.matchDetail?.status ?? match.status;

    ref.listen<MatchDetailState>(
      matchDetailProvider(match.id),
      (prev, next) {
        if (!mounted) return;
        // Update-score error
        if (prev?.updateError == null && next.updateError != null) {
          _showError(next.updateError!);
          ref.read(matchDetailProvider(match.id).notifier).clearUpdateError();
        }
        // Complete error
        if (prev?.completeError == null && next.completeError != null) {
          _showError(next.completeError!);
          ref
              .read(matchDetailProvider(match.id).notifier)
              .clearCompleteError();
        }
        // Score saved (update-score)
        if (prev?.matchDetail?.status != next.matchDetail?.status &&
            next.matchDetail?.isInProgress == true) {
          _showSuccess('Progress saved!');
        }
        // Match completed
        if (prev?.matchDetail?.isDone != true &&
            next.matchDetail?.isDone == true) {
          _showSuccess('Match completed!');
          // Refresh the tab so it moves to "Completed" section.
          ref.read(allMatchesProvider.notifier).reload();
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${matchCtx.tournamentTitle} · R${match.round} M${match.matchNumber}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: detailState.isBusy
                ? null
                : () => ref
                    .read(matchDetailProvider(match.id).notifier)
                    .loadDetail(),
          ),
        ],
      ),
      body: _buildBody(context, matchCtx, liveStatus, detailState),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MatchWithContext matchCtx,
    String liveStatus,
    MatchDetailState state,
  ) {
    final match = matchCtx.match;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MatchHeader(
            round: match.round,
            matchNumber: match.matchNumber,
            status: liveStatus,
            version: state.matchDetail?.version,
          ),
          const SizedBox(height: 16),
          _SidesCard(
            match: match,
            winnerParticipantId:
                state.matchDetail?.winnerParticipantId ??
                state.matchScore?.winnerParticipantId,
          ),
          const SizedBox(height: 16),

          // ── Score / loading section ────────────────────────────────
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: LoadingIndicator(),
            )
          else if (state.error != null)
            ErrorView(
              message: state.error!,
              onRetry: () => ref
                  .read(matchDetailProvider(match.id).notifier)
                  .loadDetail(),
            )
          else if (state.matchDetail != null &&
              state.matchDetail!.sortedSets.isNotEmpty) ...[
            _ScoreDisplay(sets: state.matchDetail!.sortedSets),
            const SizedBox(height: 16),
          ],

          // ── Completed banner ───────────────────────────────────────
          if (_isMatchDone(liveStatus)) ...[
            _DoneBanner(
              status: liveStatus,
              winnerParticipantId: state.matchDetail?.winnerParticipantId,
              sideAParticipantId: match.sideAParticipantId,
              sideBParticipantId: match.sideBParticipantId,
              eloApplied: state.matchDetail?.eloApplied ?? false,
            ),
            const SizedBox(height: 24),
          ]

          // ── Score form (for PENDING / IN_PROGRESS) ─────────────────
          else ...[
            _ScoreForm(
              // Rebuild form with new key only on first load so pre-fill
              // works; further refreshes (version bumps) don't discard input.
              key: ValueKey(
                state.matchDetail != null ? 'loaded' : 'empty',
              ),
              match: match,
              matchContext: matchCtx,
              initialSets: state.matchDetail?.sortedSets ?? [],
              isUpdating: state.isUpdating,
              isCompleting: state.isCompleting,
              onUpdateScore: (sets) async {
                final ok = await ref
                    .read(matchDetailProvider(match.id).notifier)
                    .updateScore(UpdateScoreRequest(sets: sets));
                return ok;
              },
              onComplete: (request) async {
                final ok = await ref
                    .read(matchDetailProvider(match.id).notifier)
                    .completeMatch(request);
                return ok;
              },
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
      ),
    );
  }
}

bool _isMatchDone(String status) =>
    status == MatchStatus.completed ||
    status == MatchStatus.walkover ||
    status == MatchStatus.bye;

// ── Match header card ──────────────────────────────────────────────────────

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({
    required this.round,
    required this.matchNumber,
    required this.status,
    this.version,
  });

  final int round;
  final int matchNumber;
  final String status;
  final int? version;

  @override
  Widget build(BuildContext context) {
    final statusColor = _matchStatusColor(status);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Round $round · Match $matchNumber',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (version != null)
                    Text(
                      'v$version',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                MatchStatus.label(status),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sides card ─────────────────────────────────────────────────────────────

class _SidesCard extends StatelessWidget {
  const _SidesCard({
    required this.match,
    this.winnerParticipantId,
  });

  final Match match;
  final String? winnerParticipantId;

  @override
  Widget build(BuildContext context) {
    final sideAWon = winnerParticipantId != null &&
        winnerParticipantId == match.sideAParticipantId;
    final sideBWon = winnerParticipantId != null &&
        winnerParticipantId == match.sideBParticipantId;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: _SideLabel(
                label: 'Side A',
                participantId: match.sideAParticipantId,
                isWinner: sideAWon,
                alignment: CrossAxisAlignment.start,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'vs',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: _SideLabel(
                label: 'Side B',
                participantId: match.sideBParticipantId,
                isWinner: sideBWon,
                alignment: CrossAxisAlignment.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideLabel extends StatelessWidget {
  const _SideLabel({
    required this.label,
    this.participantId,
    required this.isWinner,
    required this.alignment,
  });

  final String label;
  final String? participantId;
  final bool isWinner;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment: alignment == CrossAxisAlignment.start
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          children: [
            if (isWinner) ...[
              const Icon(Icons.emoji_events,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isWinner ? AppColors.warning : null,
                  ),
            ),
          ],
        ),
        if (participantId != null) ...[
          const SizedBox(height: 2),
          Text(
            participantId!.length >= 8
                ? participantId!.substring(0, 8)
                : participantId!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
          ),
        ] else
          Text(
            'TBD',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.disabled,
                ),
          ),
      ],
    );
  }
}

// ── Score display (read-only table) ────────────────────────────────────────

class _ScoreDisplay extends StatelessWidget {
  const _ScoreDisplay({required this.sets});

  final List<SetScore> sets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scores',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _ScoreHeader(),
                const Divider(height: 1),
                ...sets.map((s) => _ScoreRow(set: s)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Set',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Side A',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Side B',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.set});

  final SetScore set;

  @override
  Widget build(BuildContext context) {
    final aWon = set.sideAScore > set.sideBScore;
    final bWon = set.sideBScore > set.sideAScore;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Set ${set.setNumber}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${set.sideAScore}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: aWon ? FontWeight.bold : FontWeight.normal,
                      color: aWon ? AppColors.primary : null,
                    ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${set.sideBScore}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: bWon ? FontWeight.bold : FontWeight.normal,
                      color: bWon ? AppColors.primary : null,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Completed / walkover banner ────────────────────────────────────────────

class _DoneBanner extends StatelessWidget {
  const _DoneBanner({
    required this.status,
    required this.winnerParticipantId,
    required this.sideAParticipantId,
    required this.sideBParticipantId,
    required this.eloApplied,
  });

  final String status;
  final String? winnerParticipantId;
  final String? sideAParticipantId;
  final String? sideBParticipantId;
  final bool eloApplied;

  @override
  Widget build(BuildContext context) {
    final isWalkover = status == MatchStatus.walkover;
    final winnerSide = winnerParticipantId == sideAParticipantId
        ? 'Side A'
        : winnerParticipantId == sideBParticipantId
            ? 'Side B'
            : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isWalkover
                    ? Icons.flag_outlined
                    : Icons.check_circle_outline,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                isWalkover ? 'Walkover' : 'Match Completed',
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (winnerSide != null) ...[
            const SizedBox(height: 4),
            Text(
              'Winner: $winnerSide',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                  ),
            ),
          ],
          if (eloApplied) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.trending_up, size: 14,
                    color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Elo ratings updated',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Score form ─────────────────────────────────────────────────────────────
// Two actions:
//   1. "Save Progress"  — update-score (no winner needed)
//   2. "Complete Match" — complete (winner required)

class _ScoreForm extends ConsumerStatefulWidget {
  const _ScoreForm({
    super.key,
    required this.match,
    required this.matchContext,
    required this.initialSets,
    required this.isUpdating,
    required this.isCompleting,
    required this.onUpdateScore,
    required this.onComplete,
  });

  final Match match;
  final MatchWithContext matchContext;
  final List<SetScore> initialSets;
  final bool isUpdating;
  final bool isCompleting;
  final Future<bool> Function(List<SetScoreInput>) onUpdateScore;
  final Future<bool> Function(CompleteMatchRequest) onComplete;

  @override
  ConsumerState<_ScoreForm> createState() => _ScoreFormState();
}

class _ScoreFormState extends ConsumerState<_ScoreForm> {
  late List<TextEditingController> _sideAControllers;
  late List<TextEditingController> _sideBControllers;
  String? _winnerId;
  late int _setCount;

  @override
  void initState() {
    super.initState();
    // Pre-fill from server data if available (e.g. IN_PROGRESS match).
    if (widget.initialSets.isNotEmpty) {
      _setCount = widget.initialSets.length;
      _sideAControllers = widget.initialSets
          .map((s) => TextEditingController(text: '${s.sideAScore}'))
          .toList();
      _sideBControllers = widget.initialSets
          .map((s) => TextEditingController(text: '${s.sideBScore}'))
          .toList();
    } else {
      _setCount = 1;
      _sideAControllers = [TextEditingController()];
      _sideBControllers = [TextEditingController()];
    }
  }

  @override
  void dispose() {
    for (final c in _sideAControllers) {
      c.dispose();
    }
    for (final c in _sideBControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addSet() {
    if (_setCount >= 5) return;
    setState(() {
      _setCount++;
      _sideAControllers.add(TextEditingController());
      _sideBControllers.add(TextEditingController());
    });
  }

  void _removeSet() {
    if (_setCount <= 1) return;
    setState(() {
      _sideAControllers.removeLast().dispose();
      _sideBControllers.removeLast().dispose();
      _setCount--;
    });
  }

  List<SetScoreInput> _buildSets() {
    return List.generate(_setCount, (i) {
      final a = int.tryParse(_sideAControllers[i].text.trim()) ?? 0;
      final b = int.tryParse(_sideBControllers[i].text.trim()) ?? 0;
      return SetScoreInput(setNumber: i + 1, sideAScore: a, sideBScore: b);
    });
  }

  Future<void> _handleSaveProgress() async {
    await widget.onUpdateScore(_buildSets());
  }

  Future<void> _handleComplete() async {
    if (_winnerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select the winner before completing.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    await widget.onComplete(
      CompleteMatchRequest(
        winnerParticipantId: _winnerId!,
        sets: _buildSets(),
      ),
    );
  }

  bool get _isBusy => widget.isUpdating || widget.isCompleting;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) return const SizedBox.shrink();

    final canSideA = widget.match.sideAParticipantId != null;
    final canSideB = widget.match.sideBParticipantId != null;
    final isOrganiser =
        auth.userId == widget.matchContext.organiserId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header + permission hint ──────────────────────
        Row(
          children: [
            Text(
              'Score Entry',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (isOrganiser)
              const _PermissionChip(label: 'Organiser', icon: Icons.manage_accounts)
            else
              const _PermissionChip(
                label: 'Participant',
                icon: Icons.sports_tennis,
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Set score inputs ────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 52),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Side A',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Side B',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(
                  _setCount,
                  (i) => _SetScoreRow(
                    setNumber: i + 1,
                    sideAController: _sideAControllers[i],
                    sideBController: _sideBControllers[i],
                    enabled: !_isBusy,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_setCount > 1)
                      TextButton.icon(
                        onPressed: _isBusy ? null : _removeSet,
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 18),
                        label: const Text('Remove Set'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    if (_setCount < 5)
                      TextButton.icon(
                        onPressed: _isBusy ? null : _addSet,
                        icon: const Icon(Icons.add_circle_outline,
                            size: 18),
                        label: const Text('Add Set'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Save Progress button (no winner needed) ─────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: widget.isUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save Progress'),
            onPressed: _isBusy ? null : _handleSaveProgress,
          ),
        ),

        const SizedBox(height: 20),

        // ── Winner selection ────────────────────────────────────
        Text(
          'Winner (required to complete)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _WinnerButton(
                label: 'Side A',
                selected: _winnerId == widget.match.sideAParticipantId,
                enabled: canSideA && !_isBusy,
                onTap: (canSideA && !_isBusy)
                    ? () => setState(
                        () => _winnerId = widget.match.sideAParticipantId)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WinnerButton(
                label: 'Side B',
                selected: _winnerId == widget.match.sideBParticipantId,
                enabled: canSideB && !_isBusy,
                onTap: (canSideB && !_isBusy)
                    ? () => setState(
                        () => _winnerId = widget.match.sideBParticipantId)
                    : null,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Complete Match button ────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Complete Match',
            icon: Icons.check_circle_outline,
            isLoading: widget.isCompleting,
            onPressed: _isBusy ? null : _handleComplete,
          ),
        ),

        // ── Organiser-only hint ─────────────────────────────────
        if (!isOrganiser) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline,
                  size: 13, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'Only the organiser or a match participant can score.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Permission chip ────────────────────────────────────────────────────────

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Set score input row ────────────────────────────────────────────────────

class _SetScoreRow extends StatelessWidget {
  const _SetScoreRow({
    required this.setNumber,
    required this.sideAController,
    required this.sideBController,
    required this.enabled,
  });

  final int setNumber;
  final TextEditingController sideAController;
  final TextEditingController sideBController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              'Set $setNumber',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: _ScoreTextField(
              controller: sideAController,
              enabled: enabled,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('–', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _ScoreTextField(
              controller: sideBController,
              enabled: enabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreTextField extends StatelessWidget {
  const _ScoreTextField({
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          hintText: '0',
        ),
      ),
    );
  }
}

// ── Winner selection button ────────────────────────────────────────────────

class _WinnerButton extends StatelessWidget {
  const _WinnerButton({
    required this.label,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.outline;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? color : AppColors.disabled,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle,
                      size: 16, color: AppColors.primary),
                ),
              Text(
                label,
                style: TextStyle(
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  color: enabled
                      ? (selected ? AppColors.primary : AppColors.onSurface)
                      : AppColors.disabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

Color _matchStatusColor(String status) {
  switch (status) {
    case MatchStatus.completed:
      return AppColors.statusCompleted;
    case MatchStatus.walkover:
      return AppColors.statusCancelled;
    case MatchStatus.bye:
      return AppColors.statusDraft;
    case MatchStatus.inProgress:
      return AppColors.statusInProgress;
    default:
      return AppColors.onSurfaceVariant;
  }
}
