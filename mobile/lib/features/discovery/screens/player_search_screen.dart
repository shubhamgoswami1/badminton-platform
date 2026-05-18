import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _PlayerSearchScreenState extends ConsumerState<PlayerSearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Load venues when tab is first selected
      if (_tabController.index == 1 &&
          ref.read(venuesProvider).venues.isEmpty &&
          !ref.read(venuesProvider).isLoading) {
        ref.read(venuesProvider.notifier).load();
      }
    });
    Future.microtask(() => ref.read(discoveryProvider.notifier).init());
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  void _openAddVenueSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddVenueSheet(
        onSubmit: (data) async {
          final ok = await ref.read(venuesProvider.notifier).submit(data);
          if (ok && mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Venue submitted — thanks!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          if (_tabController.index == 0)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.tune_outlined),
                  tooltip: 'Filters',
                  onPressed: _openFilterSheet,
                ),
                if (discoveryState.hasFilters)
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
          if (_tabController.index == 1)
            IconButton(
              icon: const Icon(Icons.add_location_alt_outlined),
              tooltip: 'Add venue',
              onPressed: _openAddVenueSheet,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}), // refresh actions
          tabs: const [
            Tab(icon: Icon(Icons.person_search_outlined), text: 'Players'),
            Tab(icon: Icon(Icons.location_on_outlined), text: 'Venues'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PlayersTab(
            searchController: _searchController,
            state: discoveryState,
          ),
          const _VenuesTab(),
        ],
      ),
    );
  }
}

// ── Players tab ───────────────────────────────────────────────────────────────

class _PlayersTab extends ConsumerWidget {
  const _PlayersTab({
    required this.searchController,
    required this.state,
  });

  final TextEditingController searchController;
  final DiscoveryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search by name…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: state.query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        ref.read(discoveryProvider.notifier).setQuery('');
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
            onChanged: (v) => ref.read(discoveryProvider.notifier).setQuery(v),
          ),
        ),
        Expanded(child: _PlayersList(state: state)),
      ],
    );
  }
}

class _PlayersList extends ConsumerWidget {
  const _PlayersList({required this.state});

  final DiscoveryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

// ── Venues tab ────────────────────────────────────────────────────────────────

class _VenuesTab extends ConsumerStatefulWidget {
  const _VenuesTab();

  @override
  ConsumerState<_VenuesTab> createState() => _VenuesTabState();
}

class _VenuesTabState extends ConsumerState<_VenuesTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(venuesProvider).venues.isEmpty) {
        ref.read(venuesProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(venuesProvider);

    if (state.isLoading && state.venues.isEmpty) {
      return const LoadingIndicator();
    }

    if (state.error != null && state.venues.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(venuesProvider.notifier).load(),
      );
    }

    if (state.venues.isEmpty) {
      return const EmptyState(
        icon: Icons.location_off_outlined,
        title: 'No venues yet',
        subtitle: 'Tap the + button above\nto add the first venue.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(venuesProvider.notifier).load(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.venues.length,
        itemBuilder: (context, index) =>
            _VenueCard(venue: state.venues[index]),
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.sports_tennis, color: AppColors.primary),
      ),
      title: Text(
        venue.name,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Wrap(
          spacing: 8,
          children: [
            if (venue.city != null)
              _VenueChip(
                icon: Icons.location_on_outlined,
                label: venue.city!,
              ),
            if (venue.address != null)
              _VenueChip(
                icon: Icons.map_outlined,
                label: venue.address!,
              ),
            if (venue.courtCount != null)
              _VenueChip(
                icon: Icons.grid_view_outlined,
                label: '${venue.courtCount} ${venue.courtCount == 1 ? 'court' : 'courts'}',
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _VenueChip extends StatelessWidget {
  const _VenueChip({required this.icon, required this.label, this.color});

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
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(color: c),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Add venue bottom sheet ─────────────────────────────────────────────────────

class _AddVenueSheet extends ConsumerStatefulWidget {
  const _AddVenueSheet({required this.onSubmit});

  final Future<void> Function(VenueCreate data) onSubmit;

  @override
  ConsumerState<_AddVenueSheet> createState() => _AddVenueSheetState();
}

class _AddVenueSheetState extends ConsumerState<_AddVenueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _courtCountCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _courtCountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(venuesProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
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
            Text('Add Venue', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Venue name *',
                hintText: 'e.g. City Badminton Hall',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _cityCtrl,
              decoration: const InputDecoration(
                labelText: 'City (optional)',
                hintText: 'e.g. Mumbai',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                hintText: 'Street address or landmark',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _courtCountCtrl,
              decoration: const InputDecoration(
                labelText: 'Number of courts (optional)',
                hintText: 'e.g. 4',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = int.tryParse(v);
                if (n == null || n < 1) return 'Must be at least 1';
                return null;
              },
            ),

            if (state.submitError != null) ...[
              const SizedBox(height: 10),
              Text(
                state.submitError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.error),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: state.isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_location_alt),
                label: Text(state.isSubmitting ? 'Submitting…' : 'Submit Venue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: state.isSubmitting
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        final courtCount = _courtCountCtrl.text.isNotEmpty
                            ? int.tryParse(_courtCountCtrl.text)
                            : null;
                        await widget.onSubmit(
                          VenueCreate(
                            name: _nameCtrl.text.trim(),
                            city: _cityCtrl.text.trim().isEmpty
                                ? null
                                : _cityCtrl.text.trim(),
                            address: _addressCtrl.text.trim().isEmpty
                                ? null
                                : _addressCtrl.text.trim(),
                            courtCount: courtCount,
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
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
