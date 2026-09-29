import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/database/app_database.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/models/food.dart';
import 'package:nutrisnap_app/core/models/mess.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_env.dart';

Future<int> _count(AppDatabase db, String table, [String? where]) async {
  final r = await db.db.rawQuery('SELECT COUNT(*) c FROM $table${where == null ? '' : ' WHERE $where'}');
  return r.first['c'] as int;
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  Future<void> seedEverything() async {
    final now = DateTime.now();
    const item = MealItem(
      id: 'it1', name: 'Idli', estimatedWeight: 2, calories: 130, protein: 4, carbs: 26, fats: 0.5,
      originalName: 'Idli', originalCalories: 130,
    );
    final scan = await env.scans.add(ScanResult(
      id: '', userId: '', foodName: 'Idli', type: 'food', calories: 0, protein: 0, carbs: 0, fats: 0,
      confidence: 0.9, timestamp: now.toIso8601String(), items: [item],
    ));
    await env.twin.recordMeal(await env.scans.all().then((l) => l.first.copyWith(
          items: [item.copyWith(calories: 100)],
        )));
    await env.summaries.addWater(500);
    await env.chat.add('user', 'hello');
    await env.activity.addManualEntry(start: now.subtract(const Duration(hours: 2)), end: now.subtract(const Duration(hours: 1)), steps: 2500);
    await env.activity.addWorkout(Workout(id: '', type: ActivityType.walking, start: now.subtract(const Duration(hours: 5)), end: now.subtract(const Duration(hours: 4))));
    await env.activity.importBatch(sleep: [
      SleepEntry(id: 'sl', start: now.subtract(const Duration(hours: 14)), end: now.subtract(const Duration(hours: 7)), minutesAsleep: 400, externalId: 'x1'),
    ]);
    await env.foods.saveCustom(const Food(id: '', name: 'Amma Pulusu', serving: '1 bowl', servingGrams: 200, calories: 120, protein: 4, carbs: 15, fats: 4));
    final mess = await env.messes.createMess(college: 'JNTU', hostel: 'A', name: 'Main');
    await env.messes.saveMeal(
      messId: mess.id, date: DateTimeUtils.today(), mealType: MealType.lunch,
      dishes: const [MessDish(name: 'Rice', calories: 200, source: DishSource.library)],
    );
    // Link the mess meal to the diary entry
    final menu = await env.messes.menu(mess.id, DateTimeUtils.today());
    await env.messes.setLogged(menu!.meals.single.id, scan.id);
  }

  group('backup covers every module', () {
    test('round-trips activity, workouts, sleep, custom foods, corrections and messes', () async {
      await env.foods.ensureSeeded(File('assets/data/foods_in.json').readAsStringSync());
      await seedEverything();
      final json = jsonEncode(await env.backup.buildSnapshot());

      final other = await TestEnv.create();
      addTearDown(other.dispose);
      await other.foods.ensureSeeded(File('assets/data/foods_in.json').readAsStringSync());
      final result = await other.backup.restoreFromJson(json, replace: true);

      expect(result.skipped, 0);
      expect(result.extraRows, greaterThanOrEqualTo(6));
      for (final t in [Tables.activityEntries, Tables.workouts, Tables.sleepEntries, Tables.messes, Tables.messMenus, Tables.messMeals, Tables.foodCorrections]) {
        expect(await _count(other.db, t), await _count(env.db, t), reason: t);
      }
      expect(await _count(other.db, Tables.foods, 'is_custom = 1'), 1);
      expect((await other.foods.custom()).single.name, 'Amma Pulusu');
      // The built-in library is not duplicated into the backup or the restore.
      expect(await _count(other.db, Tables.foods), await _count(env.db, Tables.foods));
      // The diary link survived.
      final restoredMess = (await other.messes.messes()).single;
      final menu = await other.messes.menu(restoredMess.id, DateTimeUtils.today());
      expect(menu!.meals.single.loggedScanId, isNotNull);
    });

    test('replace removes the user\'s existing data in every module first', () async {
      await seedEverything();
      final json = jsonEncode(await env.backup.buildSnapshot());
      await env.activity.addManualEntry(start: DateTime.now().subtract(const Duration(hours: 1)), end: DateTime.now(), steps: 999);
      await env.backup.restoreFromJson(json, replace: true);
      expect(await _count(env.db, Tables.activityEntries), 1);
    });

    test('a bad row is skipped, not fatal, and links to missing meals are dropped', () async {
      await seedEverything();
      final map = await env.backup.buildSnapshot();
      final tables = Map<String, dynamic>.from(map['tables'] as Map);
      tables[Tables.workouts] = [
        ...(tables[Tables.workouts] as List),
        {'id': '', 'type': 'x'}, // no id
        'garbage',
      ];
      // A correction pointing at a meal that is not in the file
      tables[Tables.foodCorrections] = [
        ...(tables[Tables.foodCorrections] as List).map((r) => {...(r as Map), 'scan_id': 'nope'}),
      ];
      map['tables'] = tables;
      map['scans'] = [];

      final other = await TestEnv.create();
      addTearDown(other.dispose);
      final r = await other.backup.restoreFromJson(jsonEncode(map), replace: true);
      expect(await _count(other.db, Tables.workouts), 1);
      expect(await _count(other.db, Tables.foodCorrections), 0);
      expect(r.skipped, greaterThan(0));
      final meal = (await other.messes.menu((await other.messes.messes()).single.id, DateTimeUtils.today()))!.meals.single;
      expect(meal.loggedScanId, isNull);
    });

    test('columns unknown to this version and older (v3) backups are tolerated', () async {
      await seedEverything();
      final map = await env.backup.buildSnapshot();
      final tables = Map<String, dynamic>.from(map['tables'] as Map);
      tables[Tables.sleepEntries] = [
        for (final r in tables[Tables.sleepEntries] as List) {...(r as Map), 'from_the_future': 'x', 'nested': {'a': 1}},
      ];
      map['tables'] = tables;
      final other = await TestEnv.create();
      addTearDown(other.dispose);
      await other.backup.restoreFromJson(jsonEncode(map));
      expect(await _count(other.db, Tables.sleepEntries), 1);

      final v3 = {...map, 'version': 3}..remove('tables');
      final third = await TestEnv.create();
      addTearDown(third.dispose);
      final result = await third.backup.restoreFromJson(jsonEncode(v3));
      expect(result.scans, 1);
      expect(result.extraRows, 0);
    });
  });

  group('database migrations', () {
    test('a version-1 database upgrades in place without losing data', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('nutrisnap_mig_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/old.db';

      final old = await openDatabase(path, version: 1, onCreate: (db, _) async {
        await db.execute('CREATE TABLE profiles (uid TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at INTEGER NOT NULL)');
        await db.execute('''CREATE TABLE scans (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, food_name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'food', description TEXT, details TEXT, calories INTEGER NOT NULL DEFAULT 0,
          protein INTEGER NOT NULL DEFAULT 0, carbs INTEGER NOT NULL DEFAULT 0, fats INTEGER NOT NULL DEFAULT 0,
          fat_estimate REAL, confidence REAL NOT NULL DEFAULT 0, image_path TEXT, logged_at INTEGER NOT NULL, local_date TEXT NOT NULL)''');
        await db.execute('CREATE TABLE water_intake (user_id TEXT NOT NULL, local_date TEXT NOT NULL, total_ml INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, local_date))');
        await db.execute("CREATE TABLE chat_messages (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, role TEXT NOT NULL CHECK (role IN ('user','model')), text TEXT NOT NULL, created_at INTEGER NOT NULL)");
        await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE TABLE archive_log (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INTEGER NOT NULL, file_path TEXT NOT NULL, scans_count INTEGER NOT NULL, chat_count INTEGER NOT NULL, water_days INTEGER NOT NULL, retention_days INTEGER)');
      });
      await old.insert('scans', {
        'id': 's1', 'user_id': 'local_user', 'food_name': 'Dosa', 'type': 'food', 'calories': 300,
        'protein': 6, 'carbs': 50, 'fats': 8, 'confidence': 0.8, 'logged_at': 1700000000000, 'local_date': '2023-11-14',
      });
      await old.insert('scans', {
        'id': 's2', 'user_id': 'local_user', 'food_name': 'Body', 'type': 'body', 'calories': 0,
        'confidence': 0.5, 'logged_at': 1700000001000, 'local_date': '2023-11-14',
      });
      await old.insert('water_intake', {'user_id': 'local_user', 'local_date': '2023-11-14', 'total_ml': 1200});
      await old.close();

      final db = await AppDatabase.open(path: path);
      addTearDown(db.close);
      expect(await db.db.getVersion(), AppDatabase.schemaVersion);

      // Old data is intact and behaves like new data.
      expect(await _count(db, Tables.scans), 2);
      expect(await _count(db, Tables.waterIntake), 1);
      final migrated = await db.db.query(Tables.scans, where: "id = 's1'");
      expect(migrated.single['analysis_status'], 'confirmed');
      final items = await db.db.query(Tables.mealItems);
      expect(items.single['scan_id'], 's1', reason: 'only food scans get an item');
      expect(items.single['calories'], 300);

      // Every newer table exists and works.
      for (final t in [Tables.activityEntries, Tables.workouts, Tables.sleepEntries, Tables.foods, Tables.foodCorrections, Tables.messes, Tables.messMenus, Tables.messMeals]) {
        expect(await _count(db, t), 0, reason: t);
      }
      final fk = await db.db.rawQuery('PRAGMA foreign_key_check');
      expect(fk, isEmpty);
    });

    test('reopening an up-to-date database changes nothing', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('nutrisnap_mig2_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/db.sqlite';
      final a = await AppDatabase.open(path: path);
      await a.setKv('k', 'v');
      await a.close();
      final b = await AppDatabase.open(path: path);
      addTearDown(b.close);
      expect(await b.getKv('k'), 'v');
    });
  });

  group('delete-all-data validation', () {
    test('the repositories used by "Erase everything" leave nothing behind', () async {
      await env.foods.ensureSeeded(File('assets/data/foods_in.json').readAsStringSync());
      await seedEverything();
      await env.settings.setRetentionDays(90);

      await env.scans.deleteEverything();
      await env.summaries.deleteEverything();
      await env.chat.clear();
      await env.activity.deleteEverything();
      await env.messes.deleteEverything();
      await env.foods.resetUserData();
      await env.profiles.deleteAll();
      await env.settings.clear();
      await env.images.deleteAll();

      for (final t in [
        Tables.scans, Tables.mealItems, Tables.waterIntake, Tables.chatMessages, Tables.activityEntries, Tables.workouts,
        Tables.sleepEntries, Tables.foodCorrections, Tables.messes, Tables.messMenus, Tables.messMeals, Tables.profiles,
      ]) {
        expect(await _count(env.db, t), 0, reason: '$t should be empty');
      }
      expect(await _count(env.db, Tables.foods, 'is_custom = 1'), 0);
      expect(await _count(env.db, Tables.foods, 'use_count > 0'), 0);
      expect(await _count(env.db, Tables.kv), 0);
    });
  });
}
