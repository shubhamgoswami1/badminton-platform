// Discovery domain models — mirrors backend PlayerDiscoveryResponse / VenueResponse.

class PlayerSearchResult {
  const PlayerSearchResult({
    required this.userId,
    required this.displayName,
    this.city,
    this.skillLevel,
    this.playStyle,
    this.bio,
    this.eloRating,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.reliabilityScore = 5.0,
    this.distanceKm,
  });

  factory PlayerSearchResult.fromJson(Map<String, dynamic> json) =>
      PlayerSearchResult(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String,
        city: json['city'] as String?,
        skillLevel: json['skill_level'] as String?,
        playStyle: json['play_style'] as String?,
        bio: json['bio'] as String?,
        eloRating: (json['elo_rating'] as num?)?.toDouble(),
        matchesPlayed: json['matches_played'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        losses: json['losses'] as int? ?? 0,
        reliabilityScore:
            (json['reliability_score'] as num?)?.toDouble() ?? 5.0,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
      );

  final String userId;
  final String displayName;
  final String? city;
  final String? skillLevel;
  final String? playStyle;
  final String? bio;
  final double? eloRating;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final double reliabilityScore;
  final double? distanceKm;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  int? get winRate => matchesPlayed == 0
      ? null
      : ((wins / matchesPlayed) * 100).round();
}

// ── Venue ─────────────────────────────────────────────────────────────────

class Venue {
  const Venue({
    required this.id,
    required this.name,
    this.city,
    this.address,
    this.courtCount,
    this.submittedBy,
    required this.createdAt,
  });

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String?,
        address: json['address'] as String?,
        courtCount: json['court_count'] as int?,
        submittedBy: json['submitted_by'] as String?,
        createdAt: json['created_at'] as String,
      );

  final String id;
  final String name;
  final String? city;
  final String? address;
  final int? courtCount;
  final String? submittedBy;
  final String createdAt;
}

// ── Discovery Tournament ──────────────────────────────────────────────────

class DiscoveryTournament {
  const DiscoveryTournament({
    required this.id,
    required this.title,
    required this.format,
    required this.playType,
    required this.status,
    this.city,
    this.startsAt,
    this.maxParticipants,
  });

  factory DiscoveryTournament.fromJson(Map<String, dynamic> json) =>
      DiscoveryTournament(
        id: json['id'] as String,
        title: json['title'] as String,
        format: json['format'] as String,
        playType: json['play_type'] as String,
        status: json['status'] as String,
        city: json['city'] as String?,
        startsAt: json['starts_at'] as String?,
        maxParticipants: json['max_participants'] as int?,
      );

  final String id;
  final String title;
  final String format;
  final String playType;
  final String status;
  final String? city;
  final String? startsAt;
  final int? maxParticipants;
}

class VenueCreate {
  const VenueCreate({
    required this.name,
    this.city,
    this.address,
    this.courtCount,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (city != null) 'city': city,
        if (address != null) 'address': address,
        if (courtCount != null) 'court_count': courtCount,
      };

  final String name;
  final String? city;
  final String? address;
  final int? courtCount;
}
