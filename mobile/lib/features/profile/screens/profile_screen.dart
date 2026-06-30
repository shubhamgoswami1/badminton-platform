import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/profile_models.dart';
import '../providers/profile_provider.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(profileProvider.notifier).load());
  }

  Future<void> _openEdit(PlayerProfile profile) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(existing: profile),
      ),
    );
    if (result == true && mounted) {
      await ref.read(profileProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (state.profile != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
              onPressed: () => _openEdit(state.profile!),
            ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(ProfileState state) {
    if (state.isLoading && state.userWithProfile == null) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.userWithProfile == null) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(profileProvider.notifier).load(),
      );
    }

    final profile = state.profile;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.read(profileProvider.notifier).load(),
      child: ListView(
        children: [
          // ── Avatar + name header ──────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
            child: Column(
              children: [
                AvatarWidget(
                  initials: profile?.initials ?? '?',
                  radius: 44,
                ),
                const SizedBox(height: 14),
                Text(
                  profile?.displayName ?? 'Your Name',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                if (profile == null)
                  Text(
                    'Tap edit to set up your profile',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (profile.skillLevel != null) ...[
                        _SkillChip(label: _formatEnum(profile.skillLevel!)),
                        const SizedBox(width: 8),
                      ],
                      _ReliabilityBadge(score: profile.reliabilityScore),
                    ],
                  ),
              ],
            ),
          ),

          const Divider(),

          // ── Profile fields ────────────────────────────────────────────
          _ProfileTile(
            icon: Icons.location_city_outlined,
            label: 'City',
            value: profile?.city ?? '–',
          ),
          _ProfileTile(
            icon: Icons.bar_chart_outlined,
            label: 'Skill Level',
            value: profile?.skillLevel != null
                ? _formatEnum(profile!.skillLevel!)
                : '–',
          ),
          _ProfileTile(
            icon: Icons.sports_tennis,
            label: 'Play Style',
            value: profile?.playStyle != null
                ? _formatEnum(profile!.playStyle!)
                : '–',
          ),
          if (profile?.bio != null && profile!.bio!.isNotEmpty)
            _ProfileTile(
              icon: Icons.info_outline,
              label: 'Bio',
              value: profile.bio!,
            ),
          if (profile?.rating != null)
            _ProfileTile(
              icon: Icons.star_outline,
              label: 'Rating',
              value: profile!.rating!.toStringAsFixed(1),
            ),

          const Divider(),

          // ── User ID (copy to clipboard) ───────────────────────────────
          _UserIdTile(userId: ref.watch(authProvider).userId),

          const Divider(),

          // ── Career stats ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text('Career Stats', style: theme.textTheme.titleMedium),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _StatTile(label: 'Tournaments', value: '–')),
                SizedBox(width: 10),
                Expanded(child: _StatTile(label: 'Matches Won', value: '–')),
                SizedBox(width: 10),
                Expanded(child: _StatTile(label: 'Win Rate', value: '–')),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),

          // ── Actions ───────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: Text(
              'Log out',
              style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.error),
            ),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (!mounted) return;
              context.go(AppRoutes.welcome);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatEnum(String raw) {
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ReliabilityBadge extends StatelessWidget {
  const _ReliabilityBadge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 4.5
        ? AppColors.success
        : score >= 3.0
            ? AppColors.warning
            : AppColors.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_outlined, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          score.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
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
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
        textAlign: TextAlign.end,
      ),
    );
  }
}

class _UserIdTile extends StatelessWidget {
  const _UserIdTile({required this.userId});

  final String? userId;

  @override
  Widget build(BuildContext context) {
    final id = userId ?? '–';
    return ListTile(
      leading: const Icon(Icons.person_outline, color: AppColors.primary, size: 22),
      title: const Text('Your User ID',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      subtitle: Text(
        id,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: AppColors.onSurfaceVariant,
        ),
      ),
      trailing: userId != null
          ? IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copy User ID',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User ID copied!')),
                  );
                }
              },
            )
          : null,
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

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
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
