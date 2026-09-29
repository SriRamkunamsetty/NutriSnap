import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/providers/app_providers.dart';
import 'package:nutrisnap_app/features/activity/screens/activity_screen.dart';
import 'package:nutrisnap_app/features/coach/widgets/trends_section.dart';
import 'package:nutrisnap_app/features/home/screens/history_screen.dart';

import 'support/fake_health.dart';
import 'support/test_env.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  Future<void> open(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(env.db),
        imageStoreProvider.overrideWithValue(env.images),
        healthDataSourceProvider.overrideWithValue(FakeHealth()),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: home))),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> seed() async {
    final now = DateTime.now();
    await env.activity.addManualEntry(start: now.subtract(const Duration(hours: 2)), end: now.subtract(const Duration(hours: 1)), steps: 3000);
    await env.activity.addWorkout(Workout(id: '', type: ActivityType.running, start: now.subtract(const Duration(hours: 5)), end: now.subtract(const Duration(hours: 4))));
    await env.summaries.addWater(600);
  }

  testWidgets('Activity: tap targets are at least 48dp and every tappable has a label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.runAsync(seed);
    await open(tester, const SizedBox(height: 4000, child: ActivityScreen()));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('History (meals and workouts): targets and labels', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.runAsync(seed);
    await open(tester, const SizedBox(height: 4000, child: HistoryScreen()));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text('Workouts'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Running'), findsWidgets);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('Trends: honest empty state, labelled, and text meets contrast', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, const TrendsSection());
    expect(find.text('No trends yet'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('Trends with data: cards are announced as one labelled item each', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.runAsync(seed);
    await open(tester, const TrendsSection());
    expect(find.bySemanticsLabel(RegExp('^Hydration\\.')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Steps\\.')), findsOneWidget);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
