import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../data/discovery_models.dart';
import '../providers/discovery_provider.dart';
import 'player_profile_view_screen.dart';

class PlayerSearchScreen extends ConsumerStatefulWidget {
  const PlayerSearchScreen({super.key});

  @override
  ConsumerState<PlayerSearchScreen> createState() =>
      _PlayerSearchScreenState();
}

class _PlayerSearchScreenState extends ConsumerState<PlayerSearchScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(discoveryProvider.notifier).init());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(
        state: ref.read(discoveryProvider),
        onApply: (eloMin, eloMax, useLocation, radiusKm) {
          ref.read(discoveryProvider.notifier).applyFilters(
                eloMin: eloMin,
                eloMax: eloMax,
                clearEloMin: eloMin == null,
                clearEloMax: eloMax == null,
                useLocation: useLocation,
                radiusKm: radiusKm,
              );
        },
        onClear: () => ref.read(discoveryProvider.notifier).clearFilters(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Players'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.tune_outlined),
                tooltip: 'Filters',
                onPressed: _openFilterSheet,
              ),
              if (state.hasFilters)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: state.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(discoveryProvider.notifier)
                              .setQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              ),
              onChanged: (v) =>
                  ref.read(discoveryProvider.notifier).setQuery(v),
            ),
          ),
        ),
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(DiscoveryState state) {
    if (state.isLoading && state.results.isEmpty) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.results.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(discoveryProvider.notifier).refresh(),
      );
    }

    if (state.results.isEmpty) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        title: 'No players found',
        subtitle: state.hasFilters
            ? 'Try adjusting your filters.'
            : 'Start typing to search for players.',
        action: state.hasFilters
            ? TextButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('Clear filters'),
                onPressed: () =>
                    ref.read(discoveryProvider.notifier).clearFilters(),
              )
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(discoveryProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.results.length,
        itemBuilder: (context, index) =>
            _PlayerCard(player: state.results[index]),
      ),
    );
  }
}

// ── Player card ───────────────────────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player});

  final PlayerSearchResult player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: AvatarWidget(initials: player.initials, radius: 24),
      title: Text(
        player.displayName,
        style: theme.textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Wrap(
          spacing: 8,
          children: [
            if (player.city != null)
              _Chip(
                icon: Icons.location_on_outlined,
                label: player.city!,
              ),
            if (player.skillLevel != null)
              _Chip(
                icon: Icons.bar_chart_outlined,
                label: _fmt(player.skillLevel!),
              ),
            if (player.distanceKm != null)
              _Chip(
                icon: Icons.near_me_outlined,
                label: '${player.distanceKm!.toStringAsFixed(1)} km',
                color: AppColors.primary,
              ),
          ],
        ),
      ),
      trailing: player.eloRating != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  player.eloRating!.round().toString(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Elo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PlayerProfileViewScreen(player: player),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 2),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: c),
        ),
      ],
    );
  }
}

// ── Filter bottom sheet ───────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.state,
    required this.onApply,
    required this.onClear,
  });

  final DiscoveryState state;
  final void Function(
    double? eloMin,
    double? eloMax,
    bool useLocation,
    double radiusKm,
  ) onApply;
  final VoidCallback onClear;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _eloAbsMin = 800.0;
  static const _eloAbsMax = 2200.0;

  late RangeValues _eloRange;
  late bool _eloEnabled;
  late bool _useLocation;
  late double _radiusKm;

  @override
  void initState() {
    super.initState();
    _eloEnabled =
        widget.state.eloMin != null || widget.state.eloMax != null;
    _eloRange = RangeValues(
      widget.state.eloMin ?? 1000.0,
      widget.state.eloMax ?? 1800.0,
    );
    _useLocation = widget.state.useLocation;
    _radiusKm = widget.state.radiusKm;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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

          Text('Filters', style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),

          // ── Elo range ─────────────────────────────────────
          Row(
            children: [
              Checkbox(
                value: _eloEnabled,
                onChanged: (v) => setState(() => _eloEnabled = v ?? false),
                activeColor: AppColors.primary,
              ),
              Text('Elo rating range', style: theme.textTheme.titleSmall),
            ],
          ),
          if (_eloEnabled) ...[
            RangeSlider(
              values: _eloRange,
              min: _eloAbsMin,
              max: _eloAbsMax,
              divisions: 28,
              activeColor: AppColors.primary,
              labels: RangeLabels(
                _eloRange.start.round().toString(),
                _eloRange.end.round().toString(),
              ),
              onChanged: (r) => setState(() => _eloRange = r),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _eloRange.start.round().toString(),
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(
                    _eloRange.end.round().toString(),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          const Divider(),

          // ── Location radius ───────────────────────────────
          if (widget.state.locationAvailable) ...[
            Row(
              children: [
                Switch(
                  value: _useLocation,
                  onChanged: (v) => setState(() => _useLocation = v),
                  activeThumbColor: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Near me', style: theme.textTheme.titleSmall),
                    Text(
                      'Filter by distance from your location',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_useLocation) ...[
              const SizedBox(height: 8),
              Text(
                'Radius: ${_radiusKm.round()} km',
                style: theme.textTheme.bodySmall,
              ),
              Slider(
                value: _radiusKm,
                min: 5,
                max: 200,
                divisions: 39,
                activeColor: AppColors.primary,
                label: '${_radiusKm.round()} km',
                onChanged: (v) => setState(() => _radiusKm = v),
              ),
              const SizedBox(height: 4),
            ],
            const Divider(),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.location_off_outlined,
                      size: 16, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Location unavailable',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],

          const SizedBox(height: 8),

          // ── Buttons ───────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onClear();
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onApply(
                      _eloEnabled ? _eloRange.start : null,
                      _eloEnabled ? _eloRange.end : null,
                      _useLocation,
                      _radiusKm,
                    );
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmt(String raw) {
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
}
