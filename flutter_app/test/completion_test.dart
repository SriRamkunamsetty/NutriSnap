import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/coach/trends.dart';
import 'package:nutrisnap_app/core/database/app_database.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/models/user_profile.dart';
import 'package:nutrisnap_app/core/services/activity_math.dart';
import 'package:nutrisnap_app/core/services/phone_step_service.dart';

import 'support/test_env.dart';

class FakeSteps implements StepCounterSource {
  FakeSteps({this.granted = true, this.count});
  bool granted;
  int? count;
  int requests = 0;

  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<int?> readCount() async => count;
}

ActivityEntry entry(DateTime start, int mins, int steps, {String source = DataSource.healthConnect}) => ActivityEntry(
      id: '${start.millisecondsSinceEpoch}$source',
      start: start,
      end: start.add(Duration(minutes: mins)),
      steps: steps,
      source: source,
    );

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  UserProfile profile(double w) => UserProfile(uid: 'x', email: '', weight: w, height: 170, createdAt: DateTime(2025));

  group('weight history', () {
    test('records a point only when the weight actually changes', () async {
      await env.profiles.save(profile(70));
      await env.profiles.save(profile(70));
      await env.profiles.save(profile(69.2));
      await env.profiles.save(profile(69.2).copyWith(displayName: 'Asha')); // unrelated edit
      final rows = await env.db.db.query(Tables.weightEntries, orderBy: 'measured_ms');
      expect(rows.map((r) => r['weight_kg']), [70.0, 69.2]);
    });

    test('ignores impossible values', () async {
      await env.profiles.save(profile(5));
      await env.profiles.save(profile(900));
      expect(await env.db.db.query(Tables.weightEntries), isEmpty);
    });

    test('is erased with the profile and carried by backups', () async {
      await env.profiles.save(profile(70));
      final json = await env.backup.buildSnapshot();
      expect((json['tables'] as Map)[Tables.weightEntries], hasLength(1));
      final other = await TestEnv.create();
      addTearDown(other.dispose);
      await other.backup.restoreFromJson(_enc(json), replace: true);
      expect(await other.db.db.query(Tables.weightEntries), hasLength(1));
      await env.profiles.deleteAll();
      expect(await env.db.db.query(Tables.weightEntries), isEmpty);
    });

    test('trend needs two recordings, or one before the window', () {
      TrendReport r(List<(String, double)> w, {(String, double)? before}) => TrendCalculator.build(
            today: DateTime(2025, 3, 10),
            windowDays: 7,
            summaries: const [],
            activity: const [],
            sleep: const [],
            goals: const TrendGoals(),
            weights: w,
            weightBefore: before,
          );
      expect(r([]).weightChange, isNull);
      expect(r([('2025-03-08', 70)]).weightChange, isNull, reason: 'a single point is not a trend');
      expect(r([('2025-03-05', 70), ('2025-03-09', 69.2)]).weightChange, closeTo(-0.8, 1e-9));
      expect(r([('2025-03-09', 69.2)], before: ('2025-02-20', 70)).weightChange, closeTo(-0.8, 1e-9));
    });
  });

  group('inactive hours', () {
    final now = DateTime(2025, 3, 10, 12, 30); // hours 7..11 are finished

    test('is unknown without an automatic source', () {
      expect(ActivityMath.inactiveHours([entry(DateTime(2025, 3, 10, 8), 30, 500, source: DataSource.manual)], now), isNull);
      expect(ActivityMath.inactiveHours(const [], now), isNull);
    });

    test('counts finished waking hours with few steps', () {
      final hours = ActivityMath.inactiveHours([
        entry(DateTime(2025, 3, 10, 8), 30, 900), // active 08
        entry(DateTime(2025, 3, 10, 10), 20, 300), // active 10
      ], now);
      expect(hours, 3); // 07, 09, 11
    });

    test('spreads a record across the hours it spans', () {
      // 2 hours, 600 steps => 300/h: both hours active
      final hours = ActivityMath.inactiveHours([entry(DateTime(2025, 3, 10, 9), 120, 600)], now);
      expect(hours, 3); // 07, 08, 11
    });

    test('does not judge hours covered by one long record', () {
      final hours = ActivityMath.inactiveHours([entry(DateTime(2025, 3, 10, 7), 300, 2000, source: DataSource.phoneSensor)], now);
      expect(hours, 0);
    });
  });

  group('phone step sensor', () {
    late FakeSteps sensor;
    late PhoneStepService svc;
    var clock = DateTime(2025, 3, 10, 9);

    setUp(() {
      clock = DateTime(2025, 3, 10, 9);
      sensor = FakeSteps(count: 10000);
      svc = PhoneStepService(env.db, env.activity, sensor, clock: () => clock);
    });

    test('is off until enabled', () async {
      expect(await svc.sync(), PhoneStepResult.off);
    });

    test('enabling sets a baseline and never invents earlier steps', () async {
      expect(await svc.enable(), isTrue);
      expect(await env.activity.timeline('2025-03-10'), isEmpty);
      expect(await svc.isEnabled(), isTrue);
    });

    test('records only the steps gained since the last reading', () async {
      await svc.enable();
      clock = DateTime(2025, 3, 10, 11);
      sensor.count = 10800;
      expect(await svc.sync(), PhoneStepResult.recorded);
      final e = (await env.activity.timeline('2025-03-10')).single;
      expect(e.steps, 800);
      expect(e.source, DataSource.phoneSensor);
      expect(e.start, DateTime(2025, 3, 10, 9));
      expect(e.end, DateTime(2025, 3, 10, 11));

      clock = DateTime(2025, 3, 10, 12);
      expect(await svc.sync(), PhoneStepResult.nothingNew);
      expect((await env.activity.daily('2025-03-10')).steps, 800);
    });

    test('a reboot resets the counter without losing or duplicating steps', () async {
      await svc.enable();
      clock = DateTime(2025, 3, 10, 10);
      sensor.count = 350; // phone restarted; 350 steps since boot
      await svc.sync();
      expect((await env.activity.daily('2025-03-10')).steps, 350);
    });

    test('denied permission turns nothing on', () async {
      sensor.granted = false;
      expect(await svc.enable(), isFalse);
      expect(sensor.requests, 1);
      expect(await svc.isEnabled(), isFalse);
    });

    test('a phone without a step sensor reports that, not zero steps', () async {
      await svc.enable();
      sensor.count = null;
      expect(await svc.sync(), PhoneStepResult.noSensor);
      expect(await env.activity.timeline('2025-03-10'), isEmpty);
    });

    test('a very old baseline is capped instead of back-filling days', () async {
      await svc.enable();
      clock = DateTime(2025, 3, 12, 9); // two days later
      sensor.count = 15000;
      await svc.sync();
      final all = await env.db.db.query(Tables.activityEntries);
      final start = DateTime.fromMillisecondsSinceEpoch(all.single['start_ms'] as int);
      expect(clock.difference(start), PhoneStepService.maxSpan);
    });

    test('disabling can remove the recorded steps', () async {
      await svc.enable();
      clock = DateTime(2025, 3, 10, 10);
      sensor.count = 10500;
      await svc.sync();
      await svc.disable(deleteData: true);
      expect(await svc.isEnabled(), isFalse);
      expect(await env.db.db.query(Tables.activityEntries), isEmpty);
    });
  });
}

String _enc(Map<String, dynamic> m) => jsonEncode(m);
