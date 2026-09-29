import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/ai/ai_models.dart';
import 'package:nutrisnap_app/core/database/app_database.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_env.dart';

MealItem item(String name, double kcal, {double w = 100, double p = 10, double c = 20, double f = 5}) =>
    MealItem(
      id: 'item_$name',
      name: name,
      estimatedWeight: w,
      calories: kcal,
      protein: p,
      carbs: c,
      fats: f,
      confidence: 0.9,
    );

ScanResult meal(List<MealItem> items, {DateTime? at, String status = AnalysisStatus.confirmed}) => ScanResult(
      id: '',
      userId: '',
      foodName: MealAnalysisResult.titleOf(items),
      type: 'food',
      calories: 0,
      protein: 0,
      carbs: 0,
      fats: 0,
      confidence: 0.9,
      timestamp: (at ?? DateTime.now()).toIso8601String(),
      items: items,
      modelVersion: 'gemma-4-E2B-it',
      analysisStatus: status,
    );

void main() {
  group('portion maths', () {
    test('changing the amount scales all nutrition proportionally', () {
      final rice = item('Rice', 260, w: 200, p: 5, c: 57, f: 0.5);
      final half = rice.withWeight(100);
      expect(half.calories, 130);
      expect(half.carbs, 28.5);
      expect(half.estimatedWeight, 100);
      expect(rice.withWeight(400).calories, 520);
    });

    test('scaling is reversible and never produces NaN or negatives', () {
      final rice = item('Rice', 260, w: 200);
      expect(rice.withWeight(50).withWeight(200).calories, closeTo(260, 0.001));
      final zero = rice.withWeight(0);
      expect(zero.calories, 0);
      expect(zero.calories.isNaN, isFalse);
      // A zero-weight item can still be resized without dividing by zero.
      expect(zero.withWeight(100).calories.isFinite, isTrue);
      expect(rice.withWeight(-5).estimatedWeight, 0);
    });

    test('totals are the rounded sum of the items (sum first, then round)', () {
      final t = MealTotals.of([item('a', 100.4, p: 1.4), item('b', 100.4, p: 1.4)]);
      expect(t.calories, 201); // 200.8
      expect(t.protein, 3); // 2.8
    });
  });

  group('meal persistence', () {
    late TestEnv env;
    setUp(() async => env = await TestEnv.create());
    tearDown(() async => env.dispose());

    test('a multi-food meal saves and reloads with all its items in order', () async {
      final saved = await env.scans.add(meal([
        item('Chicken Curry', 320, w: 180),
        item('Rice', 260, w: 200),
        item('Curd', 60),
      ]));

      final loaded = (await env.scans.getById(saved.id))!;
      expect(loaded.items.map((i) => i.name), ['Chicken Curry', 'Rice', 'Curd']);
      expect(loaded.calories, 640); // totals derived from the items
      expect(loaded.modelVersion, 'gemma-4-E2B-it');
      expect(loaded.itemsSummary, 'Chicken Curry, Rice, Curd');
    });

    test('daily totals follow the items, including after an edit', () async {
      final saved = await env.scans.add(meal([item('A', 300), item('B', 200)]));
      var day = await env.summaries.forDate(DateTimeUtils.today());
      expect(day.totalCalories, 500);

      // Delete A and halve B's portion.
      await env.scans.update(saved.copyWith(
        items: [saved.items[1].withWeight(50)],
        analysisStatus: AnalysisStatus.edited,
      ));
      day = await env.summaries.forDate(DateTimeUtils.today());
      expect(day.totalCalories, 100);
      expect((await env.scans.getById(saved.id))!.analysisStatus, AnalysisStatus.edited);
    });

    test('deleting a meal removes its items and its calories everywhere', () async {
      final saved = await env.scans.add(meal([item('A', 300), item('B', 200)]));
      await env.scans.delete(saved.id);

      expect(await env.db.db.query(Tables.mealItems), isEmpty, reason: 'items must cascade with their meal');
      expect((await env.summaries.forDate(DateTimeUtils.today())).totalCalories, 0);
    });

    test('a food meal saved without items still gets one (manual or search log)', () async {
      final saved = await env.scans.add(const ScanResult(
        id: '',
        userId: '',
        foodName: 'Quick snack',
        type: 'food',
        calories: 180,
        protein: 4,
        carbs: 25,
        fats: 7,
        confidence: 1,
        timestamp: '2025-03-01T10:00:00.000',
      ));
      final loaded = (await env.scans.getById(saved.id))!;
      expect(loaded.items.single.name, 'Quick snack');
      expect(loaded.items.single.source, ItemSource.manual);
      expect(loaded.calories, 180);
    });

    test('body scans (non-food) never get items', () async {
      final saved = await env.scans.add(const ScanResult(
        id: '',
        userId: '',
        foodName: 'Body Scan',
        type: 'person',
        calories: 0,
        protein: 0,
        carbs: 0,
        fats: 0,
        fatEstimate: 18,
        confidence: 1,
        timestamp: '2025-03-01T10:00:00.000',
      ));
      expect((await env.scans.getById(saved.id))!.items, isEmpty);
    });

    test('backup round-trip keeps the individual foods', () async {
      await env.scans.add(meal([item('Idli', 120, w: 2), item('Sambar', 90, w: 150)], at: DateTime(2025, 2, 1, 8)));
      final json = await (await env.backup.exportToFile()).readAsString();
      expect(jsonDecode(json)['scans'][0]['items'], hasLength(2));

      final fresh = await TestEnv.create();
      addTearDown(fresh.dispose);
      await fresh.backup.restoreFromJson(json);
      final restored = (await fresh.scans.all()).single;
      expect(restored.items.map((i) => i.name), ['Idli', 'Sambar']);
      expect(restored.calories, 210);
    });

    test('history loads items for many meals in bulk', () async {
      for (var i = 0; i < 30; i++) {
        await env.scans.add(meal([item('F$i', 100), item('G$i', 50)], at: DateTime.now().subtract(Duration(minutes: i))));
      }
      final all = await env.scans.recent(limit: 50);
      expect(all.length, 30);
      expect(all.every((m) => m.items.length == 2), isTrue);
    });
  });

  group('migration v1 -> v2', () {
    test('existing meals survive and each food meal gets an explicit item', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('mig_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/old.db';

      // A genuine version-1 database, exactly as the first release created it.
      final v1 = await openDatabase(path, version: 1, onCreate: (db, _) async {
        await db.execute('CREATE TABLE profiles (uid TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at INTEGER NOT NULL)');
        await db.execute('CREATE TABLE scans ('
            'id TEXT PRIMARY KEY, user_id TEXT NOT NULL, food_name TEXT NOT NULL, type TEXT NOT NULL DEFAULT \'food\', '
            'description TEXT, details TEXT, calories INTEGER NOT NULL DEFAULT 0, protein INTEGER NOT NULL DEFAULT 0, '
            'carbs INTEGER NOT NULL DEFAULT 0, fats INTEGER NOT NULL DEFAULT 0, fat_estimate REAL, '
            'confidence REAL NOT NULL DEFAULT 0, image_path TEXT, logged_at INTEGER NOT NULL, local_date TEXT NOT NULL)');
        await db.execute('CREATE TABLE water_intake (user_id TEXT NOT NULL, local_date TEXT NOT NULL, '
            'total_ml INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, local_date))');
        await db.execute('CREATE TABLE chat_messages (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, '
            'role TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL)');
        await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE TABLE archive_log (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL, '
            'file_path TEXT NOT NULL, scans_count INTEGER NOT NULL, chat_count INTEGER NOT NULL, '
            'water_days INTEGER NOT NULL, retention_days INTEGER)');
      });
      await v1.insert('scans', {
        'id': 'old1', 'user_id': 'local_user', 'food_name': 'Masala Dosa', 'type': 'food',
        'calories': 350, 'protein': 8, 'carbs': 50, 'fats': 12, 'confidence': 0.9,
        'logged_at': DateTime(2025, 1, 1, 9).millisecondsSinceEpoch, 'local_date': '2025-01-01',
      });
      await v1.insert('scans', {
        'id': 'old2', 'user_id': 'local_user', 'food_name': 'Body Scan', 'type': 'person',
        'calories': 0, 'protein': 0, 'carbs': 0, 'fats': 0, 'confidence': 1, 'fat_estimate': 20,
        'logged_at': DateTime(2025, 1, 2, 9).millisecondsSinceEpoch, 'local_date': '2025-01-02',
      });
      await v1.close();

      // Opening with the current schema runs the migration.
      final db = await AppDatabase.open(path: path);
      addTearDown(db.close);

      final meals = await db.db.query('scans', orderBy: 'id');
      expect(meals.length, 2, reason: 'no meal may be lost');
      expect(meals.first['analysis_status'], 'confirmed');

      final items = await db.db.query('meal_items');
      expect(items.length, 1, reason: 'only the food meal gets an item');
      expect(items.single['name'], 'Masala Dosa');
      expect(items.single['calories'], 350);
      expect(items.single['scan_id'], 'old1');
    });
  });
}
