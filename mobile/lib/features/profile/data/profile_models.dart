// Profile data models — mirrors backend PlayerProfileResponse / UserWithProfile.

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    this.city,
    this.skillLevel,
    this.playStyle,
    this.bio,
    this.latitude,
    this.longitude,
    this.reliabilityScore = 5.0,
    this.rating,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String,
        city: json['city'] as String?,
        skillLevel: json['skill_level'] as String?,
        playStyle: json['play_style'] as String?,
        bio: json['bio'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        reliabilityScore:
            (json['reliability_score'] as num?)?.toDouble() ?? 5.0,
        rating: (json['rating'] as num?)?.toDouble(),
      );

  final String id;
  final String userId;
  final String displayName;
  final String? city;
  final String? skillLevel;
  final String? playStyle;
  final String? bio;
  final double? latitude;
  final double? longitude;
  final double reliabilityScore;
  final double? rating;

  /// Returns the 1–2 letter initials used in the avatar.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  PlayerProfile copyWith({
    String? displayName,
    String? city,
    String? skillLevel,
    String? playStyle,
    String? bio,
    double? latitude,
    double? longitude,
    double? rating,
    double? reliabilityScore,
  }) =>
      PlayerProfile(
        id: id,
        userId: userId,
        displayName: displayName ?? this.displayName,
        city: city ?? this.city,
        skillLevel: skillLevel ?? this.skillLevel,
        playStyle: playStyle ?? this.playStyle,
        bio: bio ?? this.bio,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        reliabilityScore: reliabilityScore ?? this.reliabilityScore,
        rating: rating ?? this.rating,
      );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.phoneNumber,
    required this.isVerified,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        phoneNumber: json['phone_number'] as String,
        isVerified: json['is_verified'] as bool? ?? false,
      );

  final String id;
  final String phoneNumber;
  final bool isVerified;
}

class UserWithProfile {
  const UserWithProfile({required this.user, this.profile});

  factory UserWithProfile.fromJson(Map<String, dynamic> json) =>
      UserWithProfile(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        profile: json['profile'] != null
            ? PlayerProfile.fromJson(json['profile'] as Map<String, dynamic>)
            : null,
      );

  final AppUser user;
  final PlayerProfile? profile;

  /// Convenience: true when the backend has no profile record yet for this user.
  bool get hasProfile => profile != null;
}
