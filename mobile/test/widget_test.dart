import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:badminton_platform/app.dart';

void main() {
  setUp(() {
    // Provide a clean in-memory SharedPreferences for each test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App smoke test — renders splash without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    // App builds — MaterialApp is in the tree.
    expect(find.byType(MaterialApp), findsOneWidget);

    // Advance past the splash screen's 1.2 s timer so no pending timers remain.
    await tester.pump(const Duration(milliseconds: 1300));

    // Pump any resulting frames (e.g. router redirect after session check).
    await tester.pump();
  });
}
