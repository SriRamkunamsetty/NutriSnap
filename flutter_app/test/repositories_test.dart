import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/models/user_profile.dart';
import 'package:nutrisnap_app/core/enums/app_enums.dart';
import 'package:nutrisnap_app/core/services/image_store.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';

import 'support/test_env.dart';

ScanResult meal(String name, int kcal, {DateTime? at, String? image, int p = 10, int c = 20, int f = 5}) =>
    ScanResult(
      id: '',
      userId: '',
      foodName: name,
      type: 'food',
      calories: kcal,
      protein: p,
      carbs: c,
      fats: f,
      confidence: 0.9,
      imageUrl: image,
      timestamp: (at ?? DateTime.now()).toIso8601String(),
    );

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  group('scans', () {
    test('add / get / update / delete round-trip', () async {
      final saved = await env.scans.add(meal('Dosa', 300));
      expect(saved.id, startsWith('scan_'));

      final fetched = await env.scans.getById(saved.id);
      expect(fetched?.foodName, 'Dosa');

      // A meal's totals come from its foods, so edit the food.
      final loaded = (await env.scans.getById(saved.id))!;
      await env.scans.update(loaded.copyWith(
        foodName: 'Masala Dosa',
        items: [loaded.items.first.copyWith(name: 'Masala Dosa', calories: 350)],
      ));
      expect((await env.scans.getById(saved.id))?.calories, 350);
      expect((await env.scans.getById(saved.id))?.foodName, 'Masala Dosa');

      await env.scans.delete(saved.id);
      expect(await env.scans.getById(saved.id), isNull);
    });

    test('recent returns newest first', () async {
      final now = DateTime.now();
      await env.scans.add(meal('old', 100, at: now.subtract(const Duration(days: 2))));
      await env.scans.add(meal('new', 100, at: now));
      final recent = await env.scans.recent(limit: 10);
      expect(recent.map((s) => s.foodName), ['new', 'old']);
    });

    test('deleting a scan removes its image file', () async {
      final rel = await env.images.saveBytes(Uint8List.fromList([1, 2, 3]), ImageKind.scan);
      final abs = env.images.absolutePath(rel)!;
      final saved = await env.scans.add(meal('Salad', 150, image: abs));
      expect(File(abs).existsSync(), isTrue);
      expect(saved.imageUrl, abs);

      await env.scans.delete(saved.id);
      expect(File(abs).existsSync(), isFalse);
    });

    test('image paths outside the private store are never persisted', () async {
      final saved = await env.scans.add(meal('X', 100, image: '/tmp/picker_cache/photo.jpg'));
      expect((await env.scans.getById(saved.id))?.imageUrl, isNull);
    });

    test('watchAll emits again after a write', () async {
      final emissions = <int>[];
      final sub = env.scans.watchAll().listen((l) => emissions.add(l.length));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await env.scans.add(meal('A', 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      expect(emissions.first, 0);
      expect(emissions.last, 1);
    });
  });

  group('daily summaries', () {
    test('totals are computed from scans, so edit and delete stay consistent', () async {
      final a = await env.scans.add(meal('A', 300, p: 20, c: 30, f: 10));
      await env.scans.add(meal('B', 200, p: 10, c: 20, f: 5));

      var s = await env.summaries.forDate(DateTimeUtils.today());
      expect(s.totalCalories, 500);
      expect(s.totalProtein, 30);

      final loadedA = (await env.scans.getById(a.id))!;
      await env.scans.update(loadedA.copyWith(items: [loadedA.items.first.copyWith(calories: 100)]));
      s = await env.summaries.forDate(DateTimeUtils.today());
      expect(s.totalCalories, 300);

      await env.scans.delete(a.id);
      s = await env.summaries.forDate(DateTimeUtils.today());
      expect(s.totalCalories, 200);
    });

    test('a meal logged at 23:30 counts for that local day, not the next', () async {
      final late = DateTime(2025, 3, 10, 23, 30);
      await env.scans.add(meal('Late snack', 250, at: late));
      expect((await env.summaries.forDate('2025-03-10')).totalCalories, 250);
      expect((await env.summaries.forDate('2025-03-11')).totalCalories, 0);
    });

    test('water accumulates, never goes negative, and is capped', () async {
      expect(await env.summaries.addWater(250), 250);
      expect(await env.summaries.addWater(500), 750);
      expect(await env.summaries.addWater(-5000), 0);
      expect(await env.summaries.addWater(999999), 20000);
    });

    test('water and meals merge into one day', () async {
      await env.scans.add(meal('A', 300));
      await env.summaries.addWater(500);
      final s = await env.summaries.forDate(DateTimeUtils.today());
      expect(s.totalCalories, 300);
      expect(s.totalWater, 500);
    });

    test('range returns only days that have data, oldest first', () async {
      await env.scans.add(meal('A', 100, at: DateTime(2025, 1, 5, 12)));
      await env.scans.add(meal('B', 200, at: DateTime(2025, 1, 3, 12)));
      final r = await env.summaries.range('2025-01-01', '2025-01-31');
      expect(r.map((d) => d.date), ['2025-01-03', '2025-01-05']);
    });
  });

  group('chat', () {
    test('history is ordered oldest-first and limit keeps the newest', () async {
      final t = DateTime(2025, 1, 1);
      for (var i = 0; i < 5; i++) {
        await env.chat.add(i.isEven ? 'user' : 'model', 'm$i', at: t.add(Duration(minutes: i)));
      }
      expect((await env.chat.all()).map((m) => m.text), ['m0', 'm1', 'm2', 'm3', 'm4']);
      expect((await env.chat.all(limit: 2)).map((m) => m.text), ['m3', 'm4']);
    });

    test('clear empties the conversation', () async {
      await env.chat.add('user', 'hi');
      await env.chat.clear();
      expect(await env.chat.all(), isEmpty);
    });
  });

  group('profile', () {
    test('saves and reloads, resolving image paths to absolute', () async {
      final rel = await env.images.saveBytes(Uint8List.fromList([9]), ImageKind.profile);
      final abs = env.images.absolutePath(rel)!;
      await env.profiles.save(UserProfile(
        uid: 'whatever',
        email: '',
        displayName: 'Asha',
        calorieLimit: 1800,
        goal: Goal.lose,
        photoURL: abs,
        createdAt: DateTime(2025, 1, 1),
      ));

      final p = await env.profiles.get();
      expect(p?.uid, 'local_user'); // always normalised
      expect(p?.displayName, 'Asha');
      expect(p?.calorieLimit, 1800);
      expect(p?.goal, Goal.lose);
      expect(p?.photoURL, abs);
    });

    test('returns null before onboarding', () async {
      expect(await env.profiles.get(), isNull);
    });
  });

  group('image store', () {
    test('rejects path traversal and absolute paths', () {
      expect(env.images.isSafeRelative('scans/a.jpg'), isTrue);
      expect(env.images.isSafeRelative('../secret'), isFalse);
      expect(env.images.isSafeRelative('scans/../../secret'), isFalse);
      expect(env.images.isSafeRelative('/etc/passwd'), isFalse);
      expect(env.images.isSafeRelative(''), isFalse);
      expect(env.images.absolutePath('../secret'), isNull);
    });
  });
}
