import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/tournament_models.dart';

// ── Status chip colour helpers ─────────────────────────────────────────────

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

// ── Date formatter ─────────────────────────────────────────────────────────

String _fmtDate(DateTime? dt) {
  if (dt == null) return 'TBD';
  final local = dt.toLocal();
  return '${local.day} ${_month(local.month)} ${local.year}';
}

String _month(int m) => const [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m];

// ── Public widget ──────────────────────────────────────────────────────────

class TournamentCard extends StatelessWidget {
  const TournamentCard({
    super.key,
    required this.tournament,
    required this.onTap,
  });

  final Tournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final theme = Theme.of(context);
    final statusColor = _statusColor(t.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: title + status chip ──────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      t.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: TournamentStatus.label(t.status),
                    color: statusColor,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Info row ──────────────────────────────────────────────
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (t.city != null && t.city!.isNotEmpty)
                    _InfoItem(icon: Icons.location_city_outlined, label: t.city!),
                  _InfoItem(
                    icon: Icons.sports_outlined,
                    label: PlayType.label(t.playType),
                  ),
                  _InfoItem(
                    icon: Icons.account_tree_outlined,
                    label: TournamentFormat.label(t.format),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Participants + date row ────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.people_outline,
                      size: 15, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    t.maxParticipants != null
                        ? '${t.participantCount} / ${t.maxParticipants}'
                        : '${t.participantCount} registered',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // Show the next relevant date
                  _DateLabel(tournament: t),
                ],
              ),

              // ── Distance badge (nearby only) ──────────────────────────
              if (t.distanceKm != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.near_me_outlined,
                        size: 14, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Text(
                      '${t.distanceKm!.toStringAsFixed(1)} km away',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;

    // Show registration deadline if open, otherwise start date
    if (t.isRegistrationOpen && t.registrationDeadlineDate != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_outlined,
              size: 14, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            'Closes ${_fmtDate(t.registrationDeadlineDate)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
          ),
        ],
      );
    }

    if (t.startsAtDate != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 14, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'Starts ${_fmtDate(t.startsAtDate)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
