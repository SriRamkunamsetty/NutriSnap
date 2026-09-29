import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/services/activity_math.dart';
import 'package:nutrisnap_app/core/services/health_connect_service.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';

import 'support/fake_health.dart';
import 'support/test_env.dart';

ActivityEntry steps(String id, int hour, int minute, int minutes, int n,
        {String origin = 'phone', String source = DataSource.healthConnect, String? ext}) =>
    ActivityEntry(
      id: id,
      start: DateTime(2025, 3, 3, hour, minute),
      end: DateTime(2025, 3, 3, hour, minute).add(Duration(minutes: minutes)),
      steps: n,
      source: source,
      origin: origin,
      externalId: ext ?? id,
    );

void main() {
  group('ActivityMath.summarize', () {
    test('sums steps, distance and calories', () {
      final d = ActivityMath.summarize('2025-03-03', [
        steps('a', 8, 0, 10, 1200).copyForTest(distance: 900, kcal: 40),
        steps('b', 12, 0, 10, 800).copyForTest(distance: 600, kcal: 25),
      ], const []);
      expect(d.steps, 2000);
      expect(d.distanceMeters, 1500);
      expect(d.activeCalories, 65);
      expect(d.distanceKm, 1.5);
      expect(d.hasData, isTrue);
    });

    test('active minutes count only brisk stretches', () {
      final d = ActivityMath.summarize('2025-03-03', [
        steps('brisk', 8, 0, 10, 1000), // 100 steps/min -> active
        steps('slow', 9, 0, 10, 200), // 20 steps/min -> not active
      ], const []);
      expect(d.activeMinutes, 10);
    });

    test('overlapping active periods are counted once', () {
      final d = ActivityMath.summarize(
        '2025-03-03',
        [steps('walk', 17, 30, 30, 3000)], // 17:30-18:00 brisk
        [
          Workout(
            id: 'w',
            type: ActivityType.running,
            start: DateTime(2025, 3, 3, 17, 45),
            end: DateTime(2025, 3, 3, 18, 15),
          ),
        ],
      );
      expect(d.activeMinutes, 45); // 17:30-18:15, not 30 + 30
    });

    test('a manual workout adds its calories; a Health Connect one does not double count', () {
      final manual = Workout(
        id: 'm', type: ActivityType.workout, calories: 200,
        start: DateTime(2025, 3, 3, 7), end: DateTime(2025, 3, 3, 7, 30),
      );
      final hc = Workout(
        id: 'h', type: ActivityType.workout, calories: 300, source: DataSource.healthConnect,
        start: DateTime(2025, 3, 3, 18), end: DateTime(2025, 3, 3, 18, 30),
      );
      final d = ActivityMath.summarize('2025-03-03', const [], [manual, hc]);
      expect(d.activeCalories, 200); // HC's 300 is already inside HC's energy records
      expect(d.workoutCount, 2);
      expect(d.activeMinutes, 60);
    });

    test('no data means an honest empty summary', () {
      final d = ActivityMath.summarize('2025-03-03', const [], const []);
      expect(d.hasData, isFalse);
      expect(d.steps, 0);
      expect(d.sourceLabel, '');
    });

    test('tracks and labels data sources', () {
      final d = ActivityMath.summarize('2025-03-03', [
        steps('a', 8, 0, 10, 1000),
        steps('b', 9, 0, 10, 1000, source: DataSource.manual),
      ], const []);
      expect(d.sourceLabel, 'Health Connect + Manual');
    });
  });

  group('ActivityMath.dedupeOverlaps', () {
    test('when phone and watch both report the same minutes, only the fuller source counts', () {
      final phone = steps('p1', 10, 0, 10, 900, origin: 'phone');
      final watch = steps('w1', 10, 0, 10, 1000, origin: 'watch'); // same window, more steps
      final out = ActivityMath.dedupeOverlaps([phone, watch], DateTimeUtils.dayKey);
      expect(out.map((e) => e.origin), ['watch']);
      expect(out.fold<int>(0, (a, e) => a + e.steps), 1000, reason: 'not 1900');
    });

    test('a lesser source still fills gaps the main source missed', () {
      final watch = steps('w1', 10, 0, 10, 1000, origin: 'watch');
      final phoneGap = steps('p1', 14, 0, 10, 500, origin: 'phone'); // watch was off
      final phoneDup = steps('p2', 10, 2, 5, 400, origin: 'phone'); // overlaps watch
      final out = ActivityMath.dedupeOverlaps([watch, phoneGap, phoneDup], DateTimeUtils.dayKey);
      expect(out.fold<int>(0, (a, e) => a + e.steps), 1500);
    });

    test('days are handled independently', () {
      final d1 = steps('a', 10, 0, 10, 100, origin: 'phone');
      final d2 = ActivityEntry(
        id: 'b', start: DateTime(2025, 3, 4, 10), end: DateTime(2025, 3, 4, 10, 10),
        steps: 300, origin: 'watch', source: DataSource.healthConnect, externalId: 'b',
      );
      final out = ActivityMath.dedupeOverlaps([d1, d2], DateTimeUtils.dayKey);
      expect(out.length, 2);
    });
  });

  group('workout calories', () {
    test('MET estimate scales with weight and time and is only an estimate', () {
      final walk = ActivityType.estimateCalories(ActivityType.walking, minutes: 60, weightKg: 70);
      final run = ActivityType.estimateCalories(ActivityType.running, minutes: 60, weightKg: 70);
      expect(walk, closeTo(245, 0.01)); // 3.5 x 70 x 1
      expect(run, greaterThan(walk));
      expect(ActivityType.estimateCalories(ActivityType.running, minutes: 30, weightKg: 70), closeTo(run / 2, 0.01));
    });
  });

  group('sleep consistency', () {
    SleepEntry night(int day, int bedHour, [int bedMin = 0]) => SleepEntry(
          id: 's$day',
          start: DateTime(2025, 3, day, bedHour, bedMin),
          end: DateTime(2025, 3, day + 1, 6),
          minutesAsleep: 420,
        );

    test('needs at least three nights; otherwise no score is invented', () {
      expect(ActivityMath.consistency([night(1, 23), night(2, 23)]), isNull);
    });

    test('steady bedtimes are Good, erratic ones are Irregular', () {
      final steady = ActivityMath.consistency([night(1, 23), night(2, 23, 10), night(3, 22, 55), night(4, 23, 5)]);
      expect(steady!.label, SleepConsistency.good);
      final erratic = ActivityMath.consistency([night(1, 21), night(2, 2), night(3, 23), night(4, 1)]);
      expect(erratic!.label, SleepConsistency.irregular);
    });

    test('bedtimes that cross midnight are compared correctly', () {
      final c = ActivityMath.consistency([night(1, 23, 50), night(2, 0, 10), night(3, 23, 55), night(4, 0, 5)]);
      expect(c!.label, SleepConsistency.good);
    });
  });

  group('ActivityRepository', () {
    late TestEnv env;
    setUp(() async => env = await TestEnv.create());
    tearDown(() async => env.dispose());

    test('importing the same Health Connect records twice never duplicates them', () async {
      final batch = [steps('a', 8, 0, 10, 1000, ext: 'uuid-1'), steps('b', 9, 0, 10, 500, ext: 'uuid-2')];
      await env.activity.importBatch(entries: batch);
      await env.activity.importBatch(entries: batch);
      final d = await env.activity.daily('2025-03-03');
      expect(d.steps, 1500);
      expect((await env.activity.timeline('2025-03-03')).length, 2);
    });

    test('a changed record updates in place instead of adding a second one', () async {
      await env.activity.importBatch(entries: [steps('a', 8, 0, 10, 1000, ext: 'uuid-1')]);
      await env.activity.importBatch(entries: [steps('a2', 8, 0, 10, 1400, ext: 'uuid-1')]);
      expect((await env.activity.daily('2025-03-03')).steps, 1400);
    });

    test('window replace removes records deleted at the source', () async {
      await env.activity.importBatch(entries: [
        steps('a', 8, 0, 10, 1000, ext: 'u1'),
        steps('b', 9, 0, 10, 500, ext: 'u2'),
      ]);
      // Re-sync the day; the source no longer has u2.
      await env.activity.importBatch(
        entries: [steps('a', 8, 0, 10, 1000, ext: 'u1')],
        replaceSource: DataSource.healthConnect,
        windowStart: DateTime(2025, 3, 3),
        windowEnd: DateTime(2025, 3, 4),
      );
      expect((await env.activity.daily('2025-03-03')).steps, 1000);
    });

    test('window replace never touches manual entries', () async {
      await env.activity.addManualEntry(
        start: DateTime(2025, 3, 3, 7), end: DateTime(2025, 3, 3, 7, 20), steps: 2000,
      );
      await env.activity.importBatch(
        entries: const [],
        replaceSource: DataSource.healthConnect,
        windowStart: DateTime(2025, 3, 3),
        windowEnd: DateTime(2025, 3, 4),
      );
      expect((await env.activity.daily('2025-03-03')).steps, 2000);
    });

    test('workouts can be logged, listed and deleted', () async {
      final w = await env.activity.addWorkout(Workout(
        id: '', type: ActivityType.cycling, calories: 250, caloriesEstimated: true,
        start: DateTime(2025, 3, 3, 6), end: DateTime(2025, 3, 3, 6, 45),
      ));
      final list = await env.activity.workoutsOn('2025-03-03');
      expect(list.single.type, ActivityType.cycling);
      expect(list.single.caloriesEstimated, isTrue);
      expect(list.single.durationMinutes, 45);
      await env.activity.deleteWorkout(w.id);
      expect(await env.activity.workoutsOn('2025-03-03'), isEmpty);
    });

    test('range returns only days that have data, oldest first', () async {
      await env.activity.importBatch(entries: [
        ActivityEntry(id: 'x', start: DateTime(2025, 3, 5, 9), end: DateTime(2025, 3, 5, 9, 10), steps: 100, source: DataSource.healthConnect, externalId: 'x'),
        steps('y', 9, 0, 10, 200, ext: 'y'),
      ]);
      final r = await env.activity.range('2025-03-01', '2025-03-31');
      expect(r.map((d) => d.date), ['2025-03-03', '2025-03-05']);
    });

    test('deleting a source removes only that source', () async {
      await env.activity.importBatch(entries: [steps('a', 8, 0, 10, 1000, ext: 'u1')]);
      await env.activity.addManualEntry(start: DateTime(2025, 3, 3, 7), end: DateTime(2025, 3, 3, 7, 20), steps: 500);
      await env.activity.deleteBySource(DataSource.healthConnect);
      expect((await env.activity.daily('2025-03-03')).steps, 500);
    });

    test('activity goals persist and default sensibly', () async {
      expect((await env.settings.activityGoals()).dailySteps, 10000);
      await env.settings.setActivityGoals(const ActivityGoals(dailySteps: 7500, weeklyWorkouts: 4));
      final g = await env.settings.activityGoals();
      expect(g.dailySteps, 7500);
      expect(g.weeklyWorkouts, 4);
      expect(g.dailyActiveMinutes, 30);
    });
  });

  group('HealthNormalizer', () {
    final t0 = DateTime(2025, 3, 3, 8);
    RawHealthRecord rec(String kind, {double v = 0, int startMin = 0, int len = 10, String? uuid, String origin = 'fit', String? wt, double? kcal, double? dist}) =>
        RawHealthRecord(
          kind: kind, value: v, uuid: uuid, origin: origin, workoutType: wt, energyKcal: kcal, distanceMeters: dist,
          from: t0.add(Duration(minutes: startMin)), to: t0.add(Duration(minutes: startMin + len)),
        );

    test('maps steps, distance, energy and workouts', () {
      final n = HealthNormalizer.normalize([
        rec('steps', v: 1200, uuid: 's1'),
        rec('distance', v: 900, uuid: 'd1'),
        rec('energy', v: 45, uuid: 'e1'),
        rec('workout', startMin: 60, len: 30, uuid: 'w1', wt: 'RUNNING', kcal: 300, dist: 4200),
      ]);
      final d = ActivityMath.summarize('2025-03-03', n.entries, n.workouts);
      expect(d.steps, 1200);
      expect(d.distanceMeters, 900);
      expect(d.activeCalories, 45);
      expect(n.workouts.single.type, ActivityType.running);
      expect(n.workouts.single.calories, 300);
      expect(n.entries.every((e) => e.source == DataSource.healthConnect), isTrue);
    });

    test('drops empty records and keeps stable external ids', () {
      final n = HealthNormalizer.normalize([rec('steps', v: 0, uuid: 'z'), rec('steps', v: 50, uuid: 'keep')]);
      expect(n.entries.single.externalId, 'keep');
    });

    test('workout type mapping is forgiving', () {
      expect(HealthNormalizer.mapWorkoutType('WALKING_TREADMILL'), ActivityType.walking);
      expect(HealthNormalizer.mapWorkoutType('BIKING_STATIONARY'), ActivityType.cycling);
      expect(HealthNormalizer.mapWorkoutType('YOGA'), ActivityType.workout);
      expect(HealthNormalizer.mapWorkoutType(null), ActivityType.other);
    });

    test('average heart rate is attached only when samples exist inside the workout', () {
      final withHr = HealthNormalizer.normalize([
        rec('workout', startMin: 0, len: 30, uuid: 'w', wt: 'RUNNING'),
        rec('heart_rate', v: 120, startMin: 5, len: 0),
        rec('heart_rate', v: 140, startMin: 10, len: 0),
        rec('heart_rate', v: 60, startMin: 200, len: 0), // outside
      ]);
      expect(withHr.workouts.single.avgHeartRate, 130);
      final without = HealthNormalizer.normalize([rec('workout', uuid: 'w', wt: 'RUNNING')]);
      expect(without.workouts.single.avgHeartRate, isNull);
    });

    test('sleep prefers asleep stages; short blips are ignored; no stages falls back to session length', () {
      final n = HealthNormalizer.normalize([
        RawHealthRecord(kind: 'sleep_session', from: DateTime(2025, 3, 2, 23), to: DateTime(2025, 3, 3, 7), uuid: 'sl1'),
        RawHealthRecord(kind: 'sleep_stage', from: DateTime(2025, 3, 2, 23, 30), to: DateTime(2025, 3, 3, 6, 30)),
        RawHealthRecord(kind: 'sleep_session', from: DateTime(2025, 3, 3, 14), to: DateTime(2025, 3, 3, 14, 10), uuid: 'nap'),
        RawHealthRecord(kind: 'sleep_session', from: DateTime(2025, 3, 3, 23), to: DateTime(2025, 3, 4, 6), uuid: 'sl2'),
      ]);
      expect(n.sleep.length, 2);
      expect(n.sleep.first.minutesAsleep, 420); // 23:30 -> 06:30
      expect(n.sleep.last.minutesAsleep, 420); // no stages: whole session
    });
  });

  group('HealthConnectController', () {
    late TestEnv env;
    late FakeHealth source;
    late HealthConnectController hc;

    setUp(() async {
      env = await TestEnv.create();
      source = FakeHealth();
      hc = HealthConnectController(
        source: source,
        activity: env.activity,
        settings: env.settings,
        clock: () => DateTime(2025, 3, 3, 12),
      );
      await pumpMicrotasks();
    });
    tearDown(() async {
      hc.dispose();
      await env.dispose();
    });

    test('starts disconnected and does not ask for anything', () {
      expect(hc.state.connected, isFalse);
      expect(source.permissionRequests, isEmpty);
    });

    test('connecting requests only the groups asked for, then syncs', () async {
      source.records = [
        RawHealthRecord(kind: 'steps', value: 4000, from: DateTime(2025, 3, 3, 8), to: DateTime(2025, 3, 3, 9), uuid: 's1', origin: 'fit'),
      ];
      final ok = await hc.connect({HcGroup.activity});
      expect(ok, isTrue);
      expect(source.permissionRequests.single, {HcGroup.activity}, reason: 'sleep/heart rate not requested');
      expect(hc.state.connected, isTrue);
      expect(hc.state.prefs.sleep, isFalse);
      expect((await env.activity.daily('2025-03-03')).steps, 4000);
      expect(hc.state.prefs.lastSync, isNotNull);
    });

    test('syncing twice keeps a single copy of each record', () async {
      source.records = [
        RawHealthRecord(kind: 'steps', value: 4000, from: DateTime(2025, 3, 3, 8), to: DateTime(2025, 3, 3, 9), uuid: 's1', origin: 'fit'),
      ];
      await hc.connect({HcGroup.activity});
      await hc.sync(force: true);
      await hc.sync(force: true);
      expect((await env.activity.daily('2025-03-03')).steps, 4000);
      expect((await env.activity.timeline('2025-03-03')).length, 1);
    });

    test('denied permission keeps the app working and offers to retry', () async {
      source.grant = false;
      final ok = await hc.connect({HcGroup.activity});
      expect(ok, isFalse);
      expect(hc.state.permissionDenied, isTrue);
      expect(hc.state.connected, isFalse);
      expect(hc.state.error, isNull); // not an error, just a state
      // Manual logging still works.
      await env.activity.addManualEntry(start: DateTime(2025, 3, 3, 7), end: DateTime(2025, 3, 3, 7, 20), steps: 800);
      expect((await env.activity.daily('2025-03-03')).steps, 800);
    });

    test('permission revoked later in system settings is detected on refresh', () async {
      await hc.connect({HcGroup.activity});
      expect(hc.state.connected, isTrue);
      source.granted = false; // user removes access in Health Connect
      await hc.refresh();
      expect(hc.state.permissionDenied, isTrue);
      expect(hc.state.connected, isFalse);
    });

    test('Health Connect not installed: connect sends the user to install it', () async {
      source.avail = HcAvailability.unavailable;
      await hc.refresh();
      final ok = await hc.connect({HcGroup.activity});
      expect(ok, isFalse);
      expect(source.installOpened, isTrue);
    });

    test('a failing read surfaces a retryable error, never a crash', () async {
      await hc.connect({HcGroup.activity});
      source.throwOnRead = true;
      await hc.sync(force: true);
      expect(hc.state.error, isNotNull);
      expect(hc.state.syncing, isFalse);
    });

    test('disconnecting can delete imported data but keeps manual entries', () async {
      source.records = [
        RawHealthRecord(kind: 'steps', value: 4000, from: DateTime(2025, 3, 3, 8), to: DateTime(2025, 3, 3, 9), uuid: 's1', origin: 'fit'),
      ];
      await hc.connect({HcGroup.activity});
      await env.activity.addManualEntry(start: DateTime(2025, 3, 3, 7), end: DateTime(2025, 3, 3, 7, 20), steps: 500);
      await hc.disconnect(deleteImportedData: true);
      expect(hc.state.prefs.anyEnabled, isFalse);
      expect(source.revoked, isTrue);
      expect((await env.activity.daily('2025-03-03')).steps, 500);
    });

    test('syncIfStale skips a fresh sync but runs an old one', () async {
      await hc.connect({HcGroup.activity});
      final reads = source.reads;
      await hc.syncIfStale();
      expect(source.reads, reads, reason: 'synced moments ago');
      await env.settings.markHealthConnectSync(DateTime(2025, 3, 3, 10)); // 2h old
      await hc.refresh();
      await hc.syncIfStale();
      expect(source.reads, reads + 1);
    });
  });
}

Future<void> pumpMicrotasks() => Future<void>.delayed(const Duration(milliseconds: 50));

extension on ActivityEntry {
  ActivityEntry copyForTest({double distance = 0, double kcal = 0}) => ActivityEntry(
        id: this.id, start: this.start, end: this.end, type: this.type, steps: this.steps,
        distanceMeters: distance, activeCalories: kcal, source: this.source, origin: this.origin,
        externalId: this.externalId,
      );
}
