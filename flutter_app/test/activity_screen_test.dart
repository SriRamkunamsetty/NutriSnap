import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/providers/app_providers.dart';
import 'package:nutrisnap_app/core/services/health_connect_service.dart';
import 'package:nutrisnap_app/features/activity/screens/activity_screen.dart';

import 'support/fake_health.dart';
import 'support/test_env.dart';

void main() {
  late TestEnv env;
  late FakeHealth health;

  setUp(() async {
    env = await TestEnv.create();
    health = FakeHealth();
  });
  tearDown(() async => env.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(env.db),
        imageStoreProvider.overrideWithValue(env.images),
        healthDataSourceProvider.overrideWithValue(health),
      ],
      child: const MaterialApp(home: ActivityScreen()),
    ));
    // Real DB I/O completes only inside runAsync; alternate with frames.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a fresh install shows honest empty states and no invented numbers', (tester) async {
    await open(tester);

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('No steps yet'), findsOneWidget);
    expect(find.text('Connect your health data'), findsOneWidget);
    expect(find.text('No movement recorded today'), findsOneWidget);
    expect(find.text('No workouts today'), findsOneWidget);
    expect(find.textContaining('8,420'), findsNothing);
    // Metric tiles show a dash, not a fake zero-looking reading.
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('manual steps appear with their source', (tester) async {
    await tester.runAsync(() => env.activity.addManualEntry(
          start: DateTime.now().subtract(const Duration(minutes: 30)),
          end: DateTime.now().subtract(const Duration(minutes: 10)),
          steps: 3000,
          distanceMeters: 2100,
        ));
    await open(tester);

    expect(find.text('3,000'), findsWidgets);
    expect(find.text('Manual'), findsWidgets);
    expect(find.text('2.10'), findsOneWidget); // km
    expect(find.text('No steps yet'), findsNothing);
    expect(find.text('30% of your 10,000-step goal'), findsOneWidget);
  });

  testWidgets('a changed goal updates the screen', (tester) async {
    await tester.runAsync(() async {
      await env.activity.addManualEntry(
        start: DateTime.now().subtract(const Duration(minutes: 30)),
        end: DateTime.now().subtract(const Duration(minutes: 10)),
        steps: 3000,
      );
      await env.settings.setActivityGoals(const ActivityGoals(dailySteps: 6000));
    });
    await open(tester);
    expect(find.text('50% of your 6,000-step goal'), findsOneWidget);
  });

  testWidgets('Health Connect not installed explains why and offers to install it', (tester) async {
    health.avail = HcAvailability.unavailable;
    await open(tester);
    expect(find.text("Health Connect isn't installed"), findsOneWidget);
    expect(find.text('Get Health Connect'), findsOneWidget);

    await tester.tap(find.text('Get Health Connect'));
    await tester.pump();
    expect(health.installOpened, isTrue);
  });

  testWidgets('denied permission shows the unavailable state with a retry, and the app keeps working', (tester) async {
    health.grant = false;
    await open(tester);

    await tester.tap(find.text('Connect Health Data'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Health data connection unavailable'), findsOneWidget);
    expect(find.text('Connect Health Data'), findsOneWidget); // can try again
    expect(find.text('Activity'), findsOneWidget); // screen still fine
  });

  testWidgets('connected state shows sync status and imported steps', (tester) async {
    health.records = [
      RawHealthRecord(
        kind: 'steps', value: 5000, uuid: 's1', origin: 'fit',
        from: DateTime.now().subtract(const Duration(hours: 2)),
        to: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];
    await open(tester);
    await tester.tap(find.text('Connect Health Data'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Health Connect · synced'), findsOneWidget);
    expect(find.text('5,000'), findsWidgets);
    expect(find.text('Health Connect'), findsWidgets); // source chip
  });

  testWidgets('logging a workout puts it on the screen', (tester) async {
    await open(tester);
    await tester.tap(find.text('Log a workout'));
    await tester.pumpAndSettle();
    expect(find.text('Save workout'), findsOneWidget);

    await tester.tap(find.text('Save workout'));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('30 min'), findsWidgets);
    expect(find.text('No workouts today'), findsNothing);
  });
}
