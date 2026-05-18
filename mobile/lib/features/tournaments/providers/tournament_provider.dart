import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/tournament_models.dart';
import '../data/tournament_repository.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

/// Extract a friendly error message from a Dio 4xx response.
String _dioErrorMessage(Object e, String fallback) {
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == 409) {
      final data = e.response?.data;
      if (data is Map) {
        final msg =
            ((data['error'] as Map?))?['message']?.toString() ?? '';
        if (msg.contains('already') || msg.contains('duplicate')) {
          return 'You are already registered for this tournament.';
        }
        return 'Registration is not open for this tournament.';
      }
    }
    if (code == 403) return 'Organisers cannot join their own tournament.';
    if (code == 401) return 'Your session has expired. Please log in again.';
    if (code == 422) return 'Invalid data. Please check your inputs.';
  }
  return fallback;
}

/// Extract the backend error message verbatim (used for start/remove where
/// the backend message is already user-friendly).
String _backendMessage(Object e, String fallback) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = (data['error'] as Map?)?['message']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final detail = data['detail']?.toString();
      if (detail != null && detail.isNotEmpty) return detail;
    }
    final code = e.response?.statusCode;
    if (code == 403) return 'Only the organiser can perform this action.';
    if (code == 401) return 'Your session has expired. Please log in again.';
  }
  return fallback;
}

// ─────────────────────────────────────────────────────────────────────────────
// Location provider
// ─────────────────────────────────────────────────────────────────────────────

class LocationState {
  const LocationState({
    this.position,
    this.isLoading = false,
    this.error,
    this.permissionDenied = false,
  });

  final Position? position;
  final bool isLoading;
  final String? error;
  final bool permissionDenied;

  bool get hasPosition => position != null;

  LocationState copyWith({
    Position? position,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? permissionDenied,
  }) =>
      LocationState(
        position: position ?? this.position,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        permissionDenied: permissionDenied ?? this.permissionDenied,
      );
}

class LocationNotifier extends StateNotifier<LocationState> {
  LocationNotifier() : super(const LocationState());

  /// Fetch current position. No-op if already loading, already resolved, or
  /// if the user permanently denied permission.
  Future<void> fetch() async {
    if (state.isLoading ||
        state.position != null ||
        state.permissionDenied) {
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(isLoading: false, permissionDenied: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      state = state.copyWith(isLoading: false, position: pos);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not get location. Check your GPS settings.',
      );
    }
  }

  /// Clear the cached position and re-fetch (e.g. pull-to-refresh).
  Future<void> refresh() async {
    state = const LocationState();
    await fetch();
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>(
  (ref) => LocationNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Nearby tournaments
// ─────────────────────────────────────────────────────────────────────────────

class NearbyTournamentsState {
  const NearbyTournamentsState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Tournament> items;
  final bool isLoading;
  final String? error;

  NearbyTournamentsState copyWith({
    List<Tournament>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      NearbyTournamentsState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class NearbyTournamentsNotifier
    extends StateNotifier<NearbyTournamentsState> {
  NearbyTournamentsNotifier(this._repo)
      : super(const NearbyTournamentsState());

  final TournamentRepository _repo;

  Future<void> load({
    required double lat,
    required double lng,
    double radiusKm = 50,
  }) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repo.getNearbyTournaments(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
      );
      state = state.copyWith(isLoading: false, items: result.items);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load nearby tournaments.',
      );
    }
  }

  void reset() => state = const NearbyTournamentsState();
}

final nearbyTournamentsProvider = StateNotifierProvider<
    NearbyTournamentsNotifier, NearbyTournamentsState>(
  (ref) => NearbyTournamentsNotifier(ref.watch(tournamentRepositoryProvider)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Shared state for my-joined and my-hosted lists
// ─────────────────────────────────────────────────────────────────────────────

class MyTournamentsState {
  const MyTournamentsState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Tournament> items;
  final bool isLoading;
  final String? error;

  MyTournamentsState copyWith({
    List<Tournament>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      MyTournamentsState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// My-Joined
// ─────────────────────────────────────────────────────────────────────────────

class MyJoinedNotifier extends StateNotifier<MyTournamentsState> {
  MyJoinedNotifier(this._repo) : super(const MyTournamentsState());

  final TournamentRepository _repo;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repo.getMyJoined();
      state = state.copyWith(isLoading: false, items: items);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load your joined tournaments.',
      );
    }
  }

  Future<void> reload() async {
    state = const MyTournamentsState();
    await load();
  }
}

final myJoinedProvider =
    StateNotifierProvider<MyJoinedNotifier, MyTournamentsState>(
  (ref) => MyJoinedNotifier(ref.watch(tournamentRepositoryProvider)),
);

// ─────────────────────────────────────────────────────────────────────────────
// My-Hosted
// ─────────────────────────────────────────────────────────────────────────────

class MyHostedNotifier extends StateNotifier<MyTournamentsState> {
  MyHostedNotifier(this._repo) : super(const MyTournamentsState());

  final TournamentRepository _repo;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repo.getMyHosted();
      state = state.copyWith(isLoading: false, items: items);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load your hosted tournaments.',
      );
    }
  }

  Future<void> reload() async {
    state = const MyTournamentsState();
    await load();
  }
}

final myHostedProvider =
    StateNotifierProvider<MyHostedNotifier, MyTournamentsState>(
  (ref) => MyHostedNotifier(ref.watch(tournamentRepositoryProvider)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Tournament detail + join action
// ─────────────────────────────────────────────────────────────────────────────

class TournamentDetailState {
  const TournamentDetailState({
    this.tournament,
    this.isLoading = false,
    this.isJoining = false,
    this.hasJoined = false,
    this.isStarting = false,
    this.error,
    this.joinError,
    this.startError,
  });

  final Tournament? tournament;
  final bool isLoading;
  final bool isJoining;
  final bool hasJoined;
  final bool isStarting;
  final String? error;
  final String? joinError;
  final String? startError;

  TournamentDetailState copyWith({
    Tournament? tournament,
    bool? isLoading,
    bool? isJoining,
    bool? hasJoined,
    bool? isStarting,
    String? error,
    String? joinError,
    String? startError,
    bool clearError = false,
    bool clearJoinError = false,
    bool clearStartError = false,
  }) =>
      TournamentDetailState(
        tournament: tournament ?? this.tournament,
        isLoading: isLoading ?? this.isLoading,
        isJoining: isJoining ?? this.isJoining,
        hasJoined: hasJoined ?? this.hasJoined,
        isStarting: isStarting ?? this.isStarting,
        error: clearError ? null : (error ?? this.error),
        joinError: clearJoinError ? null : (joinError ?? this.joinError),
        startError: clearStartError ? null : (startError ?? this.startError),
      );
}

class TournamentDetailNotifier
    extends StateNotifier<TournamentDetailState> {
  TournamentDetailNotifier(this._repo, this._id)
      : super(const TournamentDetailState());

  final TournamentRepository _repo;
  final String _id;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final t = await _repo.getTournament(_id);
      state = state.copyWith(isLoading: false, tournament: t);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load tournament details.',
      );
    }
  }

  Future<bool> join({String? partnerUserId}) async {
    state = state.copyWith(isJoining: true, clearJoinError: true);
    try {
      await _repo.joinTournament(_id, partnerUserId: partnerUserId);
      // Refresh to get updated participant count.
      final t = await _repo.getTournament(_id);
      state = state.copyWith(
        isJoining: false,
        hasJoined: true,
        tournament: t,
      );
      return true;
    } catch (e) {
      final msg = _dioErrorMessage(e, 'Could not join tournament. Please try again.');
      state = state.copyWith(isJoining: false, joinError: msg);
      return false;
    }
  }

  Future<bool> startTournament() async {
    state = state.copyWith(isStarting: true, clearStartError: true);
    try {
      final t = await _repo.startTournament(_id);
      state = state.copyWith(isStarting: false, tournament: t);
      return true;
    } catch (e) {
      final msg = _backendMessage(e, 'Could not start tournament. Please try again.');
      state = state.copyWith(isStarting: false, startError: msg);
      return false;
    }
  }

  void clearJoinError() => state = state.copyWith(clearJoinError: true);
  void clearStartError() => state = state.copyWith(clearStartError: true);
}

final tournamentDetailProvider = StateNotifierProvider.family<
    TournamentDetailNotifier, TournamentDetailState, String>(
  (ref, id) =>
      TournamentDetailNotifier(ref.watch(tournamentRepositoryProvider), id),
);

// ─────────────────────────────────────────────────────────────────────────────
// Create tournament
// ─────────────────────────────────────────────────────────────────────────────

class CreateTournamentState {
  const CreateTournamentState({
    this.isSubmitting = false,
    this.created,
    this.error,
  });

  final bool isSubmitting;
  final Tournament? created;
  final String? error;

  CreateTournamentState copyWith({
    bool? isSubmitting,
    Tournament? created,
    String? error,
    bool clearError = false,
  }) =>
      CreateTournamentState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        created: created ?? this.created,
        error: clearError ? null : (error ?? this.error),
      );
}

class CreateTournamentNotifier
    extends StateNotifier<CreateTournamentState> {
  CreateTournamentNotifier(this._repo)
      : super(const CreateTournamentState());

  final TournamentRepository _repo;

  Future<bool> submit(CreateTournamentRequest req) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final t = await _repo.createTournament(req);
      state = state.copyWith(isSubmitting: false, created: t);
      return true;
    } catch (e) {
      final msg = _dioErrorMessage(
        e,
        'Could not create tournament. Please try again.',
      );
      state = state.copyWith(isSubmitting: false, error: msg);
      return false;
    }
  }
}

final createTournamentProvider =
    StateNotifierProvider<CreateTournamentNotifier, CreateTournamentState>(
  (ref) =>
      CreateTournamentNotifier(ref.watch(tournamentRepositoryProvider)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Participants (host view — family by tournamentId)
// ─────────────────────────────────────────────────────────────────────────────

class ParticipantsState {
  const ParticipantsState({
    this.items = const [],
    this.isLoading = false,
    this.removingId,
    this.error,
    this.removeError,
  });

  final List<TournamentParticipant> items;
  final bool isLoading;
  final String? removingId; // participantId currently being removed
  final String? error;
  final String? removeError;

  List<TournamentParticipant> get active =>
      items.where((p) => p.isActive).toList();

  ParticipantsState copyWith({
    List<TournamentParticipant>? items,
    bool? isLoading,
    String? removingId,
    String? error,
    String? removeError,
    bool clearRemovingId = false,
    bool clearError = false,
    bool clearRemoveError = false,
  }) =>
      ParticipantsState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        removingId: clearRemovingId ? null : (removingId ?? this.removingId),
        error: clearError ? null : (error ?? this.error),
        removeError:
            clearRemoveError ? null : (removeError ?? this.removeError),
      );
}

class ParticipantsNotifier extends StateNotifier<ParticipantsState> {
  ParticipantsNotifier(this._repo, this._tournamentId)
      : super(const ParticipantsState());

  final TournamentRepository _repo;
  final String _tournamentId;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repo.getParticipants(_tournamentId);
      state = state.copyWith(isLoading: false, items: items);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load participants.',
      );
    }
  }

  Future<void> reload() async {
    state = const ParticipantsState();
    await load();
  }

  Future<bool> remove(String participantId) async {
    state = state.copyWith(
      removingId: participantId,
      clearRemoveError: true,
    );
    try {
      await _repo.removeParticipant(_tournamentId, participantId);
      // Optimistically remove from local list; reload for server truth.
      final updated =
          state.items.where((p) => p.id != participantId).toList();
      state = state.copyWith(
        items: updated,
        clearRemovingId: true,
      );
      return true;
    } catch (e) {
      final msg =
          _backendMessage(e, 'Could not remove participant. Please try again.');
      state = state.copyWith(
        clearRemovingId: true,
        removeError: msg,
      );
      return false;
    }
  }

  void clearRemoveError() => state = state.copyWith(clearRemoveError: true);
}

final participantsProvider = StateNotifierProvider.family<ParticipantsNotifier,
    ParticipantsState, String>(
  (ref, tournamentId) => ParticipantsNotifier(
    ref.watch(tournamentRepositoryProvider),
    tournamentId,
  ),
);
