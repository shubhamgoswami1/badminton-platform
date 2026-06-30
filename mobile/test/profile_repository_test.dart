// Unit tests for ProfileUpdateRequest serialization.
import 'package:flutter_test/flutter_test.dart';

import 'package:badminton_platform/features/profile/data/profile_repository.dart';

void main() {
  group('ProfileUpdateRequest.toJson', () {
    test('includes only non-null fields', () {
      const req = ProfileUpdateRequest(
        displayName: 'Alice',
        city: 'Mumbai',
      );
      final json = req.toJson();
      expect(json, containsPair('display_name', 'Alice'));
      expect(json, containsPair('city', 'Mumbai'));
      expect(json.containsKey('skill_level'), isFalse);
      expect(json.containsKey('play_style'), isFalse);
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('longitude'), isFalse);
      expect(json.containsKey('rating'), isFalse);
    });

    test('includes GPS coords when both provided', () {
      const req = ProfileUpdateRequest(
        displayName: 'Bob',
        latitude: 19.076,
        longitude: 72.877,
      );
      final json = req.toJson();
      expect(json, containsPair('latitude', 19.076));
      expect(json, containsPair('longitude', 72.877));
    });

    test('includes skill_level and play_style when provided', () {
      const req = ProfileUpdateRequest(
        displayName: 'Carol',
        skillLevel: 'ADVANCED',
        playStyle: 'BOTH',
      );
      final json = req.toJson();
      expect(json, containsPair('skill_level', 'ADVANCED'));
      expect(json, containsPair('play_style', 'BOTH'));
    });

    test('empty request produces only display_name if set', () {
      const req = ProfileUpdateRequest();
      expect(req.toJson(), isEmpty);
    });
  });
}
