// Tournament domain models — mirrors backend TournamentResponse /
// TournamentNearbyResult schemas.

// ── Enums (string constants matching backend) ─────────────────────────────

abstract final class TournamentFormat {
  static const knockout = 'KNOCKOUT';
  static const roundRobin = 'ROUND_ROBIN';

  static const all = [knockout, roundRobin];
  static String label(String v) =>
      const {knockout: 'Knockout', roundRobin: 'Round Robin'}[v] ?? v;
}

abstract final class MatchFormat {
  static const bestOf1 = 'BEST_OF_1';
  static const bestOf3 = 'BEST_OF_3';
  static const bestOf5 = 'BEST_OF_5';

  static const all = [bestOf1, bestOf3, bestOf5];
  static String label(String v) =>
      const {bestOf1: 'Best of 1', bestOf3: 'Best of 3', bestOf5: 'Best of 5'}[v] ?? v;
}

abstract final class PlayType {
  static const singles = 'SINGLES';
  static const doubles = 'DOUBLES';
  static const mixedDoubles = 'MIXED_DOUBLES';

  static const all = [singles, doubles, mixedDoubles];
  static String label(String v) =>
      const {singles: 'Singles', doubles: 'Doubles', mixedDoubles: 'Mixed Doubles'}[v] ?? v;
}

abstract final class TournamentStatus {
  static const draft = 'DRAFT';
  static const registrationOpen = 'REGISTRATION_OPEN';
  static const registrationClosed = 'REGISTRATION_CLOSED';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';

  static String label(String v) => const {
        draft: 'Draft',
        registrationOpen: 'Open',
        registrationClosed: 'Registration Closed',
        inProgress: 'In Progress',
        completed: 'Completed',
        cancelled: 'Cancelled',
      }[v] ??
      v;
}

abstract final class ParticipantStatus {
  static const active = 'ACTIVE';
  static const withdrawn = 'WITHDRAWN';
}

// ── Tournament ────────────────────────────────────────────────────────────

class Tournament {
  const Tournament({
    required this.id,
    required this.organiserId,
    required this.title,
    this.description,
    this.city,
    required this.format,
    required this.matchFormat,
    required this.playType,
    required this.status,
    this.maxParticipants,
    this.participantCount = 0,
    this.latitude,
    this.longitude,
    this.registrationDeadline,
    this.startsAt,
    this.bracketGenerated = false,
    this.distanceKm,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        id: json['id'] as String,
        organiserId: json['organiser_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        city: json['city'] as String?,
        format: json['format'] as String,
        matchFormat: json['match_format'] as String,
        playType: json['play_type'] as String,
        status: json['status'] as String,
        maxParticipants: json['max_participants'] as int?,
        participantCount: json['participant_count'] as int? ?? 0,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        registrationDeadline: json['registration_deadline'] as String?,
        startsAt: json['starts_at'] as String?,
        bracketGenerated: json['bracket_generated'] as bool? ?? false,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        createdAt: json['created_at'] as String,
        updatedAt: json['updated_at'] as String,
      );

  final String id;
  final String organiserId;
  final String title;
  final String? description;
  final String? city;
  final String format;
  final String matchFormat;
  final String playType;
  final String status;
  final int? maxParticipants;
  final int participantCount;
  final double? latitude;
  final double? longitude;
  final String? registrationDeadline;
  final String? startsAt;
  final bool bracketGenerated;
  final double? distanceKm; // only present in nearby results
  final String createdAt;
  final String updatedAt;

  bool get isRegistrationOpen => status == TournamentStatus.registrationOpen;
  bool get isDraft => status == TournamentStatus.draft;
  bool get isInProgress => status == TournamentStatus.inProgress;
  bool get isCompleted => status == TournamentStatus.completed;
  bool get isCancelled => status == TournamentStatus.cancelled;

  /// Human-readable start date, or null if not set.
  DateTime? get startsAtDate =>
      startsAt != null ? DateTime.tryParse(startsAt!) : null;

  /// Human-readable registration deadline, or null if not set.
  DateTime? get registrationDeadlineDate =>
      registrationDeadline != null
          ? DateTime.tryParse(registrationDeadline!)
          : null;
}

// ── Paginated list wrapper (used by /tournaments/nearby) ──────────────────

class PaginatedTournaments {
  const PaginatedTournaments({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.pages,
  });

  factory PaginatedTournaments.fromJson(Map<String, dynamic> json) =>
      PaginatedTournaments(
        items: (json['items'] as List<dynamic>)
            .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['page_size'] as int,
        pages: json['pages'] as int,
      );

  final List<Tournament> items;
  final int total;
  final int page;
  final int pageSize;
  final int pages;
}

// ── Create DTO ────────────────────────────────────────────────────────────

class CreateTournamentRequest {
  const CreateTournamentRequest({
    required this.title,
    this.description,
    this.city,
    required this.format,
    required this.matchFormat,
    required this.playType,
    this.maxParticipants,
    this.registrationDeadline,
    this.startsAt,
    this.latitude,
    this.longitude,
  });

  final String title;
  final String? description;
  final String? city;
  final String format;
  final String matchFormat;
  final String playType;
  final int? maxParticipants;
  final String? registrationDeadline; // ISO 8601
  final String? startsAt; // ISO 8601
  final double? latitude;
  final double? longitude;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'title': title,
      'format': format,
      'match_format': matchFormat,
      'play_type': playType,
    };
    if (description != null) map['description'] = description;
    if (city != null) map['city'] = city;
    if (maxParticipants != null) map['max_participants'] = maxParticipants;
    if (registrationDeadline != null) {
      map['registration_deadline'] = registrationDeadline;
    }
    if (startsAt != null) map['starts_at'] = startsAt;
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    return map;
  }
}

// ── Participant ───────────────────────────────────────────────────────────

class TournamentParticipant {
  const TournamentParticipant({
    required this.id,
    required this.tournamentId,
    required this.userId,
    this.partnerUserId,
    this.seedOrder,
    required this.registeredAt,
    required this.status,
    this.displayName,
    this.partnerDisplayName,
  });

  factory TournamentParticipant.fromJson(Map<String, dynamic> json) =>
      TournamentParticipant(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        userId: json['user_id'] as String,
        partnerUserId: json['partner_user_id'] as String?,
        seedOrder: json['seed_order'] as int?,
        registeredAt: json['registered_at'] as String,
        status: json['status'] as String,
        displayName: json['display_name'] as String?,
        partnerDisplayName: json['partner_display_name'] as String?,
      );

  final String id;
  final String tournamentId;
  final String userId;
  final String? partnerUserId;
  final int? seedOrder;
  final String registeredAt;
  final String status;
  /// Player's display name from their profile (null if no profile yet).
  final String? displayName;
  /// Partner's display name for doubles (null for singles or no partner profile).
  final String? partnerDisplayName;

  bool get isActive => status == ParticipantStatus.active;

  /// Short display identifier: displayName if available, else first 8 chars of userId.
  String get shortId => displayName ?? (userId.length >= 8 ? userId.substring(0, 8) : userId);

  /// Label used in match cards. For doubles: "Name & Partner", for singles: "Name".
  String get matchLabel {
    final name = displayName ?? (userId.length >= 8 ? userId.substring(0, 8) : userId);
    if (partnerUserId != null) {
      final partner = partnerDisplayName ??
          (partnerUserId!.length >= 8 ? partnerUserId!.substring(0, 8) : partnerUserId!);
      return '$name & $partner';
    }
    return name;
  }
}

// ── Standing entry (round-robin) ──────────────────────────────────────────

class StandingEntry {
  const StandingEntry({
    required this.participantId,
    required this.userId,
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.points,
    required this.pointDiff,
  });

  factory StandingEntry.fromJson(Map<String, dynamic> json) => StandingEntry(
        participantId: json['participant_id'] as String,
        userId: json['user_id'] as String,
        matchesPlayed: json['matches_played'] as int,
        wins: json['wins'] as int,
        losses: json['losses'] as int,
        points: json['points'] as int,
        pointDiff: json['point_diff'] as int,
      );

  final String participantId;
  final String userId;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int points;
  final int pointDiff;

  String get shortId => userId.length >= 8 ? userId.substring(0, 8) : userId;
}
