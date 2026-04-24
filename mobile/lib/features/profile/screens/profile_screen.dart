import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
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
    // Load profile whenever this screen is entered.
    Future.microtask(() => ref.read(profileProvider.notifier).load());
  }

  Future<void> _openEdit(PlayerProfile profile) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(existing: profile),
      ),
    );
    // Refresh data if user saved changes.
    if (result == true && mounted) {
      await ref.read(profileProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      body: _buildBody(theme, state),
    );
  }

  Widget _buildBody(ThemeData theme, ProfileState state) {
    // Loading skeleton
    if (state.isLoading && state.userWithProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error with no cached data
    if (state.error != null && state.userWithProfile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.read(profileProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final profile = state.profile;

    return RefreshIndicator(
      onRefresh: () => ref.read(profileProvider.notifier).load(),
      child: ListView(
        children: [
          // Avatar + name header
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 32),
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
                const SizedBox(height: 4),
                Text(
                  profile == null
                      ? 'Tap edit to set up your profile'
                      : _reliabilityLabel(profile.reliabilityScore),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Profile fields
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

          const Divider(height: 1),

          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Career Stats', style: theme.textTheme.titleMedium),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _StatTile(label: 'Tournaments', value: '0')),
                SizedBox(width: 12),
                Expanded(child: _StatTile(label: 'Matches Won', value: '0')),
                SizedBox(width: 12),
                Expanded(child: _StatTile(label: 'Win Rate', value: '–')),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(height: 1),

          // Log out
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: Text(
              'Log out',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: AppColors.error),
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

  String _reliabilityLabel(double score) {
    if (score >= 4.5) return '⭐ Reliability: ${score.toStringAsFixed(1)}';
    if (score >= 3.0) return 'Reliability: ${score.toStringAsFixed(1)}';
    return '⚠️ Reliability: ${score.toStringAsFixed(1)}';
  }

  String _formatEnum(String raw) {
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

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
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
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
            ),
          ],
        ),
      ),
    );
  }
}
