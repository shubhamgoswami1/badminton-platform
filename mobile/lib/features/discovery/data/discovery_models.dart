// Discovery domain models — mirrors backend PlayerDiscoveryResponse.

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
