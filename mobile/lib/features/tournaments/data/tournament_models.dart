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
