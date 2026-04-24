// Unit tests for profile data models — no Flutter widgets needed.
import 'package:flutter_test/flutter_test.dart';

import 'package:badminton_platform/features/profile/data/profile_models.dart';

void main() {
  group('PlayerProfile', () {
    const baseJson = {
      'id': 'p-001',
      'user_id': 'u-001',
      'display_name': 'Alice Sharma',
      'city': 'Mumbai',
      'skill_level': 'ADVANCED',
      'play_style': 'SINGLES',
      'bio': null,
      'latitude': 19.076,
      'longitude': 72.8777,
      'reliability_score': 4.8,
      'rating': 8.0,
    };

    test('fromJson parses all fields correctly', () {
      final p = PlayerProfile.fromJson(baseJson);
      expect(p.id, 'p-001');
      expect(p.userId, 'u-001');
      expect(p.displayName, 'Alice Sharma');
      expect(p.city, 'Mumbai');
      expect(p.skillLevel, 'ADVANCED');
      expect(p.playStyle, 'SINGLES');
      expect(p.bio, isNull);
      expect(p.latitude, closeTo(19.076, 1e-6));
      expect(p.longitude, closeTo(72.8777, 1e-6));
      expect(p.reliabilityScore, closeTo(4.8, 1e-6));
      expect(p.rating, closeTo(8.0, 1e-6));
    });

    test('fromJson uses default reliability_score = 5.0 when absent', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..remove('reliability_score');
      final p = PlayerProfile.fromJson(json);
      expect(p.reliabilityScore, 5.0);
    });

    test('fromJson handles nullable rating as null', () {
      final json = Map<String, dynamic>.from(baseJson)..['rating'] = null;
      final p = PlayerProfile.fromJson(json);
      expect(p.rating, isNull);
    });

    group('initials', () {
      test('two-word name → first letters of each word uppercased', () {
        final p = PlayerProfile.fromJson(baseJson);
        expect(p.initials, 'AS');
      });

      test('single-word name → first letter uppercased', () {
        final json = Map<String, dynamic>.from(baseJson)
          ..['display_name'] = 'Dave';
        final p = PlayerProfile.fromJson(json);
        expect(p.initials, 'D');
      });

      test('three-word name → first and last letters', () {
        final json = Map<String, dynamic>.from(baseJson)
          ..['display_name'] = 'Alice B Sharma';
        final p = PlayerProfile.fromJson(json);
        expect(p.initials, 'AS');
      });

      test('empty display name → ?', () {
        final json = Map<String, dynamic>.from(baseJson)
          ..['display_name'] = '';
        final p = PlayerProfile.fromJson(json);
        expect(p.initials, '?');
      });
    });

    test('copyWith returns updated profile preserving unchanged fields', () {
      final p = PlayerProfile.fromJson(baseJson);
      final updated = p.copyWith(displayName: 'Bob', city: 'Delhi');
      expect(updated.displayName, 'Bob');
      expect(updated.city, 'Delhi');
      // Unchanged
      expect(updated.skillLevel, 'ADVANCED');
      expect(updated.rating, closeTo(8.0, 1e-6));
      expect(updated.id, 'p-001');
    });
  });

  group('AppUser', () {
    test('fromJson parses all fields', () {
      const json = {
        'id': 'u-001',
        'phone_number': '+919876543210',
        'is_verified': true,
      };
      final u = AppUser.fromJson(json);
      expect(u.id, 'u-001');
      expect(u.phoneNumber, '+919876543210');
      expect(u.isVerified, isTrue);
    });

    test('fromJson defaults is_verified to false when absent', () {
      const json = {'id': 'u-002', 'phone_number': '+910000000001'};
      final u = AppUser.fromJson(json);
      expect(u.isVerified, isFalse);
    });
  });

  group('UserWithProfile', () {
    const fullJson = {
      'user': {
        'id': 'u-001',
        'phone_number': '+919876543210',
        'is_verified': true,
      },
      'profile': {
        'id': 'p-001',
        'user_id': 'u-001',
        'display_name': 'Alice',
        'city': null,
        'skill_level': null,
        'play_style': null,
        'bio': null,
        'latitude': null,
        'longitude': null,
        'reliability_score': 5.0,
        'rating': null,
      },
    };

    test('fromJson with profile → hasProfile is true', () {
      final data = UserWithProfile.fromJson(fullJson);
      expect(data.hasProfile, isTrue);
      expect(data.profile?.displayName, 'Alice');
    });

    test('fromJson with null profile → hasProfile is false', () {
      final json = Map<String, dynamic>.from(fullJson)..['profile'] = null;
      final data = UserWithProfile.fromJson(json);
      expect(data.hasProfile, isFalse);
      expect(data.profile, isNull);
    });
  });
}
