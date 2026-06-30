import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../data/discovery_models.dart';

class PlayerProfileViewScreen extends StatelessWidget {
  const PlayerProfileViewScreen({super.key, required this.player});

  final PlayerSearchResult player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(player.displayName)),
      body: ListView(
        children: [
          // ── Header ───────────────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                AvatarWidget(initials: player.initials, radius: 44),
                const SizedBox(height: 14),
                Text(
                  player.displayName,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                if (player.city != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        player.city!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                if (player.distanceKm != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${player.distanceKm!.toStringAsFixed(1)} km away',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Stats row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Stats', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Elo',
                    value: player.eloRating != null
                        ? player.eloRating!.round().toString()
                        : '–',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Matches',
                    value: '${player.matchesPlayed}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Win Rate',
                    value: player.winRate != null
                        ? '${player.winRate}%'
                        : '–',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(label: 'Wins', value: '${player.wins}'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      _StatCard(label: 'Losses', value: '${player.losses}'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Reliability',
                    value: player.reliabilityScore.toStringAsFixed(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Divider(height: 1),

          // ── Profile fields ────────────────────────────────────────
          if (player.skillLevel != null)
            _InfoTile(
              icon: Icons.bar_chart_outlined,
              label: 'Skill Level',
              value: _fmt(player.skillLevel!),
            ),
          if (player.playStyle != null)
            _InfoTile(
              icon: Icons.sports_tennis,
              label: 'Play Style',
              value: _fmt(player.playStyle!),
            ),
          if (player.bio != null && player.bio!.isNotEmpty)
            _InfoTile(
              icon: Icons.info_outline,
              label: 'Bio',
              value: player.bio!,
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

String _fmt(String raw) {
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label,
          style: Theme.of(context).textTheme.labelMedium),
      trailing: Flexible(
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
          textAlign: TextAlign.end,
        ),
      ),
    );
  }
}
