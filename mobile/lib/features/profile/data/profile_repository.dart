import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  /// GET /users/me — returns the authenticated user + profile (profile may be null).
  Future<UserWithProfile> getMe() async {
    final response = await _dio.get(ApiEndpoints.me);
    return UserWithProfile.fromJson(unwrap(response));
  }

  /// PUT /users/me/profile — upsert profile fields.
  /// Only non-null fields in [data] are sent to the backend.
  Future<PlayerProfile> updateProfile(ProfileUpdateRequest data) async {
    final response = await _dio.put(
      ApiEndpoints.myProfile,
      data: data.toJson(),
    );
    return PlayerProfile.fromJson(unwrap(response));
  }
}

/// DTO for profile upsert — mirrors backend PlayerProfileUpdate schema.
class ProfileUpdateRequest {
  const ProfileUpdateRequest({
    this.displayName,
    this.city,
    this.skillLevel,
    this.playStyle,
    this.bio,
    this.latitude,
    this.longitude,
    this.rating,
  });

  final String? displayName;
  final String? city;
  final String? skillLevel;
  final String? playStyle;
  final String? bio;
  final double? latitude;
  final double? longitude;
  final double? rating;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (displayName != null) map['display_name'] = displayName;
    if (city != null) map['city'] = city;
    if (skillLevel != null) map['skill_level'] = skillLevel;
    if (playStyle != null) map['play_style'] = playStyle;
    if (bio != null) map['bio'] = bio;
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    if (rating != null) map['rating'] = rating;
    return map;
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(dioClientProvider));
});
