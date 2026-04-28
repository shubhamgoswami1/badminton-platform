import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    Future.microtask(
      () => ref
          .read(tournamentDetailProvider(widget.tournamentId).notifier)
          .load(),
    );
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
      // Refresh my-joined list so it shows up there too.
      ref.read(myJoinedProvider.notifier).reload();
    }
    // Error is shown inline — no extra snackbar needed.
  }

  @override
  Widget build(BuildContext context) {
    final detailState =
        ref.watch(tournamentDetailProvider(widget.tournamentId));

    // Show join error in a snackbar (fire-once pattern).
    ref.listen<TournamentDetailState>(
      tournamentDetailProvider(widget.tournamentId),
      (prev, next) {
        if (prev?.joinError == null &&
            next.joinError != null &&
            mounted) {
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
        onRetry: () =>
            ref
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
          // ── Hero card ──────────────────────────────────────────────
          _HeroCard(tournament: t),
          const SizedBox(height: 16),

          // ── Details section ────────────────────────────────────────
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

          // ── Description ────────────────────────────────────────────
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

          const SizedBox(height: 32),

          // ── Join action ────────────────────────────────────────────
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

          if (state.hasJoined)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.success),
                  SizedBox(width: 8),
                  Text(
                    'You are registered!',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          if (isOrganiser && t.isRegistrationOpen)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      color: AppColors.info),
                  SizedBox(width: 8),
                  Text(
                    'You are the organiser',
                    style: TextStyle(color: AppColors.info),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
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
