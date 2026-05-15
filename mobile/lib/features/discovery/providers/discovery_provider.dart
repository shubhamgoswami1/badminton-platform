import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/discovery_models.dart';
import '../data/discovery_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class DiscoveryState {
  const DiscoveryState({
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.query = '',
    this.eloMin,
    this.eloMax,
    this.locationAvailable = false,
    this.useLocation = false,
    this.radiusKm = 50.0,
    this.currentLat,
    this.currentLng,
  });

  final List<PlayerSearchResult> results;
  final bool isLoading;
  final String? error;

  // Filters
  final String query;
  final double? eloMin;
  final double? eloMax;
  final bool locationAvailable;
  final bool useLocation;
  final double radiusKm;
  final double? currentLat;
  final double? currentLng;

  bool get hasFilters => eloMin != null || eloMax != null || useLocation;

  DiscoveryState copyWith({
    List<PlayerSearchResult>? results,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? query,
    double? eloMin,
    double? eloMax,
    bool clearEloMin = false,
    bool clearEloMax = false,
    bool? locationAvailable,
    bool? useLocation,
    double? radiusKm,
    double? currentLat,
    double? currentLng,
  }) =>
      DiscoveryState(
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        query: query ?? this.query,
        eloMin: clearEloMin ? null : (eloMin ?? this.eloMin),
        eloMax: clearEloMax ? null : (eloMax ?? this.eloMax),
        locationAvailable: locationAvailable ?? this.locationAvailable,
        useLocation: useLocation ?? this.useLocation,
        radiusKm: radiusKm ?? this.radiusKm,
        currentLat: currentLat ?? this.currentLat,
        currentLng: currentLng ?? this.currentLng,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class DiscoveryNotifier extends StateNotifier<DiscoveryState> {
  DiscoveryNotifier(this._repo) : super(const DiscoveryState());

  final DiscoveryRepository _repo;

  /// Call on screen init — checks location permission and loads initial results.
  Future<void> init() async {
    await _checkLocation();
    await search();
  }

  Future<void> _checkLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
      state = state.copyWith(
        locationAvailable: true,
        currentLat: pos.latitude,
        currentLng: pos.longitude,
      );
    } catch (_) {
      // Location unavailable — silently continue without it.
    }
  }

  Future<void> search() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repo.searchPlayers(
        query: state.query.isEmpty ? null : state.query,
        eloMin: state.eloMin,
        eloMax: state.eloMax,
        lat: state.useLocation ? state.currentLat : null,
        lng: state.useLocation ? state.currentLng : null,
        radiusKm: state.useLocation ? state.radiusKm : null,
      );
      state = state.copyWith(isLoading: false, results: result.items);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load players. Please try again.',
      );
    }
  }

  Future<void> setQuery(String q) async {
    state = state.copyWith(query: q);
    await search();
  }

  Future<void> applyFilters({
    double? eloMin,
    double? eloMax,
    bool clearEloMin = false,
    bool clearEloMax = false,
    bool? useLocation,
    double? radiusKm,
  }) async {
    state = state.copyWith(
      eloMin: eloMin,
      eloMax: eloMax,
      clearEloMin: clearEloMin,
      clearEloMax: clearEloMax,
      useLocation: useLocation,
      radiusKm: radiusKm,
    );
    await search();
  }

  Future<void> clearFilters() async {
    state = state.copyWith(
      clearEloMin: true,
      clearEloMax: true,
      useLocation: false,
    );
    await search();
  }

  Future<void> refresh() async {
    await search();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final discoveryProvider =
    StateNotifierProvider<DiscoveryNotifier, DiscoveryState>(
  (ref) => DiscoveryNotifier(ref.watch(discoveryRepositoryProvider)),
);
