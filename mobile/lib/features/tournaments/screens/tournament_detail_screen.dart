import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/tournament_models.dart';
import '../providers/tournament_provider.dart';

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
    final ok = await ref
        .read(tournamentDetailProvider(widget.tournamentId).notifier)
        .join();
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
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detailState.tournament?.title ?? 'Tournament',
          overflow: TextOverflow.ellipsis,
        ),
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
              onStart: _handleStart,
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
    required this.onStart,
  });

  final Tournament tournament;
  final String tournamentId;
  final bool isStarting;
  final VoidCallback onStart;

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

    final canStart = (t.status == TournamentStatus.registrationOpen ||
            t.status == TournamentStatus.registrationClosed) &&
        !t.isInProgress &&
        !t.isCompleted;

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

        // ── Start button ─────────────────────────────────────────────
        if (canStart) ...[
          if (!hasEnough)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Need at least 4 participants to start (${4 - activeCount} more needed).',
                    style: const TextStyle(
                        color: AppColors.warning, fontSize: 13),
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
