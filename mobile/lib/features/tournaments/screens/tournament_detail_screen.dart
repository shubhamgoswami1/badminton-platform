import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/data/discovery_models.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../data/tournament_models.dart';
import '../providers/tournament_provider.dart';
import 'edit_tournament_screen.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
}

class _TournamentDetailScreenState
    extends ConsumerState<TournamentDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(tournamentDetailProvider(widget.tournamentId).notifier)
          .load();
    });
  }

  Future<void> _handleJoin() async {
    final tournament = ref
        .read(tournamentDetailProvider(widget.tournamentId))
        .tournament;
    final isDoubles = tournament != null &&
        (tournament.playType == PlayType.doubles ||
            tournament.playType == PlayType.mixedDoubles);

    String? partnerUserId;

    if (isDoubles) {
      // Show partner entry sheet before joining
      partnerUserId = await _showPartnerSheet();
      if (partnerUserId == null) return; // user dismissed
    }

    final ok = await ref
        .read(tournamentDetailProvider(widget.tournamentId).notifier)
        .join(partnerUserId: partnerUserId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have joined the tournament!'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.read(myJoinedProvider.notifier).reload();
    }
  }

  /// Shows a bottom sheet with player search for the partner.
  /// Returns the partner's userId string if confirmed, or null if dismissed.
  Future<String?> _showPartnerSheet() async {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PartnerEntrySheet(),
    );
  }

  Future<void> _handleStart() async {
    final ok = await ref
        .read(tournamentDetailProvider(widget.tournamentId).notifier)
        .startTournament();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tournament started!'),
          backgroundColor: AppColors.success,
        ),
      );
      ref.read(myHostedProvider.notifier).reload();
      // Reload participants to reflect any auto-changes.
      ref.read(participantsProvider(widget.tournamentId).notifier).reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailState =
        ref.watch(tournamentDetailProvider(widget.tournamentId));

    // Join error → snackbar (fire-once).
    ref.listen<TournamentDetailState>(
      tournamentDetailProvider(widget.tournamentId),
      (prev, next) {
        if (!mounted) return;
        if (prev?.joinError == null && next.joinError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.joinError!),
              backgroundColor: AppColors.error,
            ),
          );
          ref
              .read(tournamentDetailProvider(widget.tournamentId).notifier)
              .clearJoinError();
        }
        if (prev?.startError == null && next.startError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.startError!),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
          ref
              .read(tournamentDetailProvider(widget.tournamentId).notifier)
              .clearStartError();
        }
        if (prev?.transitionError == null && next.transitionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.transitionError!),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
          ref
              .read(tournamentDetailProvider(widget.tournamentId).notifier)
              .clearTransitionError();
        }
      },
    );

    final t = detailState.tournament;
    final userId = ref.watch(authProvider).userId;
    final isOrganiser = t != null && userId != null && t.organiserId == userId;
    final canEdit = isOrganiser &&
        (t.status == TournamentStatus.draft ||
            t.status == TournamentStatus.registrationOpen);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t?.title ?? 'Tournament',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit tournament',
              onPressed: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditTournamentScreen(tournament: t),
                  ),
                );
                if (updated == true && mounted) {
                  ref
                      .read(tournamentDetailProvider(widget.tournamentId).notifier)
                      .reload();
                }
              },
            ),
        ],
      ),
      body: _buildBody(context, detailState),
    );
  }

  Widget _buildBody(BuildContext context, TournamentDetailState state) {
    if (state.isLoading && state.tournament == null) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.tournament == null) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref
            .read(tournamentDetailProvider(widget.tournamentId).notifier)
            .load(),
      );
    }

    final t = state.tournament;
    if (t == null) return const SizedBox.shrink();

    final userId = ref.watch(authProvider).userId;
    final isOrganiser = userId != null && t.organiserId == userId;
    final isTransitioning = state.isTransitioning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCard(tournament: t),
          const SizedBox(height: 16),

          // ── Host dashboard (organiser only) ────────────────────────
          if (isOrganiser) ...[
            _HostDashboard(
              tournament: t,
              tournamentId: widget.tournamentId,
              isStarting: state.isStarting,
              isTransitioning: isTransitioning,
              onStart: _handleStart,
              onTransition: (nextStatus) async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await ref
                    .read(tournamentDetailProvider(widget.tournamentId).notifier)
                    .transitionStatus(nextStatus);
                if (ok && mounted) {
                  ref.read(myHostedProvider.notifier).reload();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Status updated!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],

          // ── Tournament details ─────────────────────────────────────
          const _SectionTitle(title: 'Tournament Details'),
          _DetailRow(
            icon: Icons.account_tree_outlined,
            label: 'Format',
            value: TournamentFormat.label(t.format),
          ),
          _DetailRow(
            icon: Icons.sports_outlined,
            label: 'Play Type',
            value: PlayType.label(t.playType),
          ),
          _DetailRow(
            icon: Icons.sports_score_outlined,
            label: 'Match Format',
            value: MatchFormat.label(t.matchFormat),
          ),
          if (t.city != null)
            _DetailRow(
              icon: Icons.location_city_outlined,
              label: 'City',
              value: t.city!,
            ),
          if (t.maxParticipants != null)
            _DetailRow(
              icon: Icons.people_outline,
              label: 'Participants',
              value: '${t.participantCount} / ${t.maxParticipants}',
            )
          else
            _DetailRow(
              icon: Icons.people_outline,
              label: 'Registered',
              value: '${t.participantCount}',
            ),
          if (t.registrationDeadlineDate != null)
            _DetailRow(
              icon: Icons.event_outlined,
              label: 'Registration closes',
              value: _fmtDate(t.registrationDeadlineDate!),
            ),
          if (t.startsAtDate != null)
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Starts',
              value: _fmtDate(t.startsAtDate!),
            ),
          if (t.distanceKm != null)
            _DetailRow(
              icon: Icons.near_me_outlined,
              label: 'Distance',
              value: '${t.distanceKm!.toStringAsFixed(1)} km from you',
            ),

          if (t.description != null && t.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionTitle(title: 'About'),
            Text(
              t.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
          ],

          // ── Fixtures entry point ───────────────────────────────────
          if (t.bracketGenerated) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.grid_view_outlined),
                label: const Text('View Fixtures & Bracket'),
                onPressed: () => context.push(
                  AppRoutes.tournamentFixturesPath(t.id),
                  extra: t,
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── Player actions (non-organiser) ─────────────────────────
          if (!isOrganiser && t.isRegistrationOpen && !state.hasJoined)
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Join Tournament',
                icon: Icons.how_to_reg_outlined,
                isLoading: state.isJoining,
                onPressed: _handleJoin,
              ),
            ),

          if (!isOrganiser && state.hasJoined)
            const _StatusBanner(
              icon: Icons.check_circle_outline,
              message: 'You are registered!',
              color: AppColors.success,
            ),

          if (isOrganiser)
            const _StatusBanner(
              icon: Icons.admin_panel_settings_outlined,
              message: 'You are the organiser',
              color: AppColors.info,
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Host dashboard ─────────────────────────────────────────────────────────

class _HostDashboard extends ConsumerStatefulWidget {
  const _HostDashboard({
    required this.tournament,
    required this.tournamentId,
    required this.isStarting,
    required this.isTransitioning,
    required this.onStart,
    required this.onTransition,
  });

  final Tournament tournament;
  final String tournamentId;
  final bool isStarting;
  final bool isTransitioning;
  final VoidCallback onStart;
  final void Function(String nextStatus) onTransition;

  @override
  ConsumerState<_HostDashboard> createState() => _HostDashboardState();
}

class _HostDashboardState extends ConsumerState<_HostDashboard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(participantsProvider(widget.tournamentId).notifier)
          .load(),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, TournamentParticipant p) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove participant?'),
        content: Text(
          'Remove player ${p.shortId}…? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(participantsProvider(widget.tournamentId).notifier)
        .remove(p.id);
    if (!mounted) return;

    if (!ok) {
      final err =
          ref.read(participantsProvider(widget.tournamentId)).removeError;
      messenger.showSnackBar(
        SnackBar(
          content: Text(err ?? 'Could not remove participant.'),
          backgroundColor: AppColors.error,
        ),
      );
      ref
          .read(participantsProvider(widget.tournamentId).notifier)
          .clearRemoveError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pState = ref.watch(participantsProvider(widget.tournamentId));
    final t = widget.tournament;

    final activeCount = pState.active.length;
    final hasEnough = activeCount >= 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────
        Row(
          children: [
            const _SectionTitle(title: 'Host Dashboard'),
            const Spacer(),
            if (pState.isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => ref
                    .read(participantsProvider(widget.tournamentId).notifier)
                    .reload(),
                tooltip: 'Refresh participants',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),

        // ── Stat row ────────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.people_outline,
                  label: 'Registered',
                  value: '$activeCount',
                  color: hasEnough ? AppColors.success : AppColors.warning,
                ),
                if (t.maxParticipants != null) ...[
                  const SizedBox(width: 16),
                  _StatChip(
                    icon: Icons.event_seat_outlined,
                    label: 'Capacity',
                    value: '${t.maxParticipants}',
                    color: AppColors.info,
                  ),
                ],
                const SizedBox(width: 16),
                _StatChip(
                  icon: Icons.info_outline,
                  label: 'Status',
                  value: TournamentStatus.label(t.status),
                  color: _statusColor(t.status),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Participant list ─────────────────────────────────────────
        if (pState.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              pState.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),

        if (!pState.isLoading && pState.active.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No participants yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < pState.active.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _ParticipantRow(
                    participant: pState.active[i],
                    index: i + 1,
                    isRemoving:
                        pState.removingId == pState.active[i].id,
                    canRemove: t.status == TournamentStatus.registrationOpen ||
                        t.status == TournamentStatus.registrationClosed,
                    onRemove: () =>
                        _confirmRemove(context, pState.active[i]),
                  ),
                ],
              ],
            ),
          ),

        const SizedBox(height: 16),

        // ── Lifecycle action buttons ─────────────────────────────────
        if (t.status == TournamentStatus.draft) ...[
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Open Registration',
              icon: Icons.how_to_reg_outlined,
              isLoading: widget.isTransitioning,
              onPressed: widget.isTransitioning
                  ? null
                  : () => widget.onTransition(TournamentStatus.registrationOpen),
            ),
          ),
          const SizedBox(height: 8),
          _CancelButton(
            isLoading: widget.isTransitioning,
            onPressed: () => widget.onTransition(TournamentStatus.cancelled),
          ),
        ],

        if (t.status == TournamentStatus.registrationOpen) ...[
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Close Registration',
              icon: Icons.lock_outline,
              isLoading: widget.isTransitioning,
              onPressed: widget.isTransitioning
                  ? null
                  : () => widget.onTransition(TournamentStatus.registrationClosed),
            ),
          ),
          const SizedBox(height: 8),
          _CancelButton(
            isLoading: widget.isTransitioning,
            onPressed: () => widget.onTransition(TournamentStatus.cancelled),
          ),
        ],

        if (t.status == TournamentStatus.registrationClosed) ...[
          if (!hasEnough)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Need at least 4 participants (${4 - activeCount} more needed).',
                      style: const TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Start Tournament',
              icon: Icons.play_arrow_outlined,
              isLoading: widget.isStarting,
              onPressed: hasEnough ? widget.onStart : null,
            ),
          ),
          const SizedBox(height: 8),
          _CancelButton(
            isLoading: widget.isTransitioning,
            onPressed: () => widget.onTransition(TournamentStatus.cancelled),
          ),
        ],

        if (t.isInProgress)
          const _StatusBanner(
            icon: Icons.sports_outlined,
            message: 'Tournament is in progress',
            color: AppColors.statusInProgress,
          ),

        if (t.isCompleted)
          const _StatusBanner(
            icon: Icons.emoji_events_outlined,
            message: 'Tournament completed',
            color: AppColors.statusCompleted,
          ),

        if (t.status == TournamentStatus.cancelled)
          const _StatusBanner(
            icon: Icons.cancel_outlined,
            message: 'Tournament cancelled',
            color: AppColors.error,
          ),
      ],
    );
  }
}

// ── Participant row ────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.index,
    required this.isRemoving,
    required this.canRemove,
    required this.onRemove,
  });

  final TournamentParticipant participant;
  final int index;
  final bool isRemoving;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Seed / index badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${participant.seedOrder ?? index}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Player id
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Player ${participant.shortId}…',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (participant.partnerUserId != null)
                  Text(
                    'Partner: ${participant.partnerUserId!.substring(0, 8)}…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),

          // Remove button
          if (canRemove)
            isRemoving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.error),
                  )
                : IconButton(
                    icon: const Icon(Icons.person_remove_outlined,
                        size: 20, color: AppColors.error),
                    onPressed: onRemove,
                    tooltip: 'Remove participant',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
        ],
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Status banner (reused for organiser + player feedback) ─────────────────

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
              )
            : const Icon(Icons.cancel_outlined, color: AppColors.error),
        label: const Text('Cancel Tournament',
            style: TextStyle(color: AppColors.error)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error),
        ),
        onPressed: isLoading ? null : onPressed,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            message,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Hero card ──────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final statusColor = _statusColor(t.status);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    t.title,
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    TournamentStatus.label(t.status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (t.city != null && t.city!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    t.city!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section title ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Detail row ─────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

Color _statusColor(String status) {
  switch (status) {
    case TournamentStatus.registrationOpen:
      return AppColors.statusOpen;
    case TournamentStatus.registrationClosed:
      return AppColors.statusClosed;
    case TournamentStatus.inProgress:
      return AppColors.statusInProgress;
    case TournamentStatus.completed:
      return AppColors.statusCompleted;
    case TournamentStatus.cancelled:
      return AppColors.statusCancelled;
    default:
      return AppColors.statusDraft;
  }
}

String _fmtDate(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day} ${_month(local.month)} ${local.year}';
}

String _month(int m) => const [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m];

// ── Partner entry bottom sheet ────────────────────────────────────────────────

/// Shown when a player joins a DOUBLES or MIXED_DOUBLES tournament.
/// Lets the user search for their partner by name. Selecting a player card
/// confirms them as partner and pops the sheet with their userId.
class _PartnerEntrySheet extends ConsumerStatefulWidget {
  const _PartnerEntrySheet();

  @override
  ConsumerState<_PartnerEntrySheet> createState() => _PartnerEntrySheetState();
}

class _PartnerEntrySheetState extends ConsumerState<_PartnerEntrySheet> {
  final _searchCtrl = TextEditingController();
  PlayerSearchResult? _selected;

  // Debounce timer
  DateTime? _lastQuery;

  @override
  void initState() {
    super.initState();
    // Initialise with empty results (no location needed here).
    Future.microtask(() => ref.read(discoveryProvider.notifier).search());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final now = DateTime.now();
    _lastQuery = now;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_lastQuery == now) {
        ref.read(discoveryProvider.notifier).setQuery(query);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discoveryState = ref.watch(discoveryProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text('Find Your Partner', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Search by name to find your doubles partner.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // ── Search field ─────────────────────────────────────────────
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search players',
              hintText: 'Type a name…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search_outlined),
            ),
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),

          // ── Selected chip ─────────────────────────────────────────────
          if (_selected != null) ...[
            Chip(
              avatar: const Icon(Icons.person_outlined, size: 16),
              label: Text('Selected: ${_selected!.displayName}'),
              onDeleted: () => setState(() => _selected = null),
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.10),
              side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 12),
          ],

          // ── Results list ─────────────────────────────────────────────
          if (discoveryState.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (discoveryState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                discoveryState.error!,
                style: const TextStyle(
                    color: AppColors.error, fontSize: 13),
              ),
            )
          else if (discoveryState.results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _searchCtrl.text.isEmpty
                    ? 'Start typing to search for players.'
                    : 'No players found.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: discoveryState.results.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final player = discoveryState.results[i];
                  final isSelected = _selected?.userId == player.userId;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor:
                        AppColors.primary.withValues(alpha: 0.07),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      child: Text(
                        player.initials,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ),
                    title: Text(player.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      [
                        if (player.city != null) player.city!,
                        if (player.skillLevel != null) player.skillLevel!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: AppColors.primary, size: 18)
                        : null,
                    onTap: () => setState(() => _selected = player),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),

          // ── Action buttons ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.sports_tennis),
                  label: const Text('Confirm Partner'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _selected == null
                      ? null
                      : () =>
                          Navigator.of(context).pop(_selected!.userId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
