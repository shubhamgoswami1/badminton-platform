import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../providers/tournament_provider.dart';
import '../widgets/tournament_card.dart';

// ── Main screen ───────────────────────────────────────────────────────────

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabLabels = ['Nearby', 'Joined', 'Hosted'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    // Kick off data loads after the first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _kickNearby();
      ref.read(myJoinedProvider.notifier).load();
      ref.read(myHostedProvider.notifier).load();
    });
  }

  void _kickNearby() {
    final loc = ref.read(locationProvider);
    // If location is already available, start loading immediately.
    if (loc.hasPosition) {
      ref.read(nearbyTournamentsProvider.notifier).load(
            lat: loc.position!.latitude,
            lng: loc.position!.longitude,
          );
      return;
    }
    // Otherwise kick off the location fetch; the listener in build() will
    // trigger the nearby load once the position arrives.
    if (!loc.isLoading && !loc.permissionDenied) {
      ref.read(locationProvider.notifier).fetch();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When location resolves, automatically fire the nearby tournaments load.
    ref.listen<LocationState>(locationProvider, (prev, next) {
      if (prev?.position == null && next.position != null) {
        ref.read(nearbyTournamentsProvider.notifier).load(
              lat: next.position!.latitude,
              lng: next.position!.longitude,
            );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournaments'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.tournamentCreate),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _NearbyTab(),
          _MyListTab(type: _TabType.joined),
          _MyListTab(type: _TabType.hosted),
        ],
      ),
    );
  }
}

// ── Nearby tab ────────────────────────────────────────────────────────────

class _NearbyTab extends ConsumerWidget {
  const _NearbyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(locationProvider);
    final nearby = ref.watch(nearbyTournamentsProvider);

    // ── 1. Permission denied ──────────────────────────────────────────
    if (loc.permissionDenied) {
      return EmptyState(
        icon: Icons.location_off_outlined,
        title: 'Location access denied',
        subtitle:
            'Enable location permission in Settings to discover nearby tournaments.',
        action: TextButton.icon(
          onPressed: () => Geolocator.openAppSettings(),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open Settings'),
        ),
      );
    }

    // ── 2. Fetching location ──────────────────────────────────────────
    if (loc.isLoading) {
      return const LoadingIndicator(message: 'Getting your location…');
    }

    // ── 3. Location error ─────────────────────────────────────────────
    if (loc.error != null && !loc.hasPosition) {
      return ErrorView(
        message: loc.error!,
        onRetry: () => ref.read(locationProvider.notifier).refresh(),
      );
    }

    // ── 4. No position and not yet attempted ──────────────────────────
    if (!loc.hasPosition) {
      return EmptyState(
        icon: Icons.near_me_outlined,
        title: 'Discover nearby tournaments',
        subtitle: 'Tap below to use your current location.',
        action: TextButton.icon(
          onPressed: () => ref.read(locationProvider.notifier).fetch(),
          icon: const Icon(Icons.my_location),
          label: const Text('Use my location'),
        ),
      );
    }

    // ── 5. Loading nearby list ────────────────────────────────────────
    if (nearby.isLoading) {
      return const LoadingIndicator(message: 'Finding tournaments near you…');
    }

    // ── 6. Error loading nearby ───────────────────────────────────────
    if (nearby.error != null) {
      return ErrorView(
        message: nearby.error!,
        onRetry: () => ref
            .read(nearbyTournamentsProvider.notifier)
            .load(
                lat: loc.position!.latitude, lng: loc.position!.longitude),
      );
    }

    // ── 7. Empty result ───────────────────────────────────────────────
    if (nearby.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          ref.read(nearbyTournamentsProvider.notifier).reset();
          await ref
              .read(nearbyTournamentsProvider.notifier)
              .load(
                  lat: loc.position!.latitude,
                  lng: loc.position!.longitude);
        },
        child: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: 400,
            child: EmptyState(
              icon: Icons.search_off_outlined,
              title: 'No tournaments nearby',
              subtitle:
                  'No open tournaments within 50 km.\nTry creating one!',
            ),
          ),
        ),
      );
    }

    // ── 8. List ───────────────────────────────────────────────────────
    return RefreshIndicator(
      onRefresh: () async {
        ref.read(nearbyTournamentsProvider.notifier).reset();
        await ref.read(nearbyTournamentsProvider.notifier).load(
              lat: loc.position!.latitude,
              lng: loc.position!.longitude,
            );
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        itemCount: nearby.items.length,
        itemBuilder: (context, i) {
          final t = nearby.items[i];
          return TournamentCard(
            tournament: t,
            onTap: () =>
                context.push(AppRoutes.tournamentDetailPath(t.id)),
          );
        },
      ),
    );
  }
}

// ── Joined / Hosted tab ───────────────────────────────────────────────────

enum _TabType { joined, hosted }

class _MyListTab extends ConsumerWidget {
  const _MyListTab({required this.type});

  final _TabType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reference each provider by concrete type so Dart infers the concrete
    // notifier (MyJoinedNotifier / MyHostedNotifier) and exposes `reload`.
    if (type == _TabType.joined) {
      return _buildContent(
        context: context,
        state: ref.watch(myJoinedProvider),
        reload: ref.read(myJoinedProvider.notifier).reload,
        icon: Icons.how_to_reg_outlined,
        emptyTitle: 'No joined tournaments',
        emptySubtitle: 'Join a nearby tournament to see it here.',
      );
    } else {
      return _buildContent(
        context: context,
        state: ref.watch(myHostedProvider),
        reload: ref.read(myHostedProvider.notifier).reload,
        icon: Icons.emoji_events_outlined,
        emptyTitle: 'No hosted tournaments',
        emptySubtitle: 'Tap the + button to create your first tournament.',
      );
    }
  }

  Widget _buildContent({
    required BuildContext context,
    required MyTournamentsState state,
    required Future<void> Function() reload,
    required IconData icon,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (state.isLoading) return const LoadingIndicator();

    if (state.error != null) {
      return ErrorView(message: state.error!, onRetry: reload);
    }

    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: 400,
            child: EmptyState(
              icon: icon,
              title: emptyTitle,
              subtitle: emptySubtitle,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final t = state.items[i];
          return TournamentCard(
            tournament: t,
            onTap: () => context.push(AppRoutes.tournamentDetailPath(t.id)),
          );
        },
      ),
    );
  }
}
