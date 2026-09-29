import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Names of every table, so repositories and change notifications agree.
class Tables {
  const Tables._();
  static const profiles = 'profiles';
  static const scans = 'scans';
  static const waterIntake = 'water_intake';
  static const chatMessages = 'chat_messages';
  static const kv = 'kv';
  static const archiveLog = 'archive_log';
  static const mealItems = 'meal_items';
  static const activityEntries = 'activity_entries';
  static const workouts = 'workouts';
  static const sleepEntries = 'sleep_entries';
  static const foods = 'foods';
  static const foodCorrections = 'food_corrections';
  static const messes = 'messes';
  static const messMenus = 'mess_menus';
  static const messMeals = 'mess_meals';
  static const weightEntries = 'weight_entries';
}

/// On-device SQLite database (`nutrisnap.db`).
///
/// All health data lives here and in the app's private documents directory.
/// Nothing is ever sent off the device.
///
/// Schema changes go through [_migrations]; never edit a released migration,
/// append a new one and bump [schemaVersion] implicitly via the list length.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const String fileName = 'nutrisnap.db';

  final StreamController<String> _changes = StreamController<String>.broadcast();

  /// Opens (creating / migrating if needed) the database.
  ///
  /// Pass [path] = `inMemoryDatabasePath` in tests.
  static Future<AppDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      dbPath,
      version: _migrations.length,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final migration in _migrations) {
          await migration(db);
        }
      },
      onUpgrade: (db, from, to) async {
        for (var v = from; v < to; v++) {
          await _migrations[v](db);
        }
      },
    );
    return AppDatabase._(db);
  }

  static int get schemaVersion => _migrations.length;

  /// Ordered migrations. Index `i` upgrades schema version `i` -> `i + 1`.
  static final List<Future<void> Function(Database)> _migrations = [
    (db) async {
      await db.execute('''
        CREATE TABLE ${Tables.profiles} (
          uid TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE ${Tables.scans} (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          food_name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'food',
          description TEXT,
          details TEXT,
          calories INTEGER NOT NULL DEFAULT 0,
          protein INTEGER NOT NULL DEFAULT 0,
          carbs INTEGER NOT NULL DEFAULT 0,
          fats INTEGER NOT NULL DEFAULT 0,
          fat_estimate REAL,
          confidence REAL NOT NULL DEFAULT 0,
          image_path TEXT,
          logged_at INTEGER NOT NULL,
          local_date TEXT NOT NULL
        )''');
      await db.execute(
          'CREATE INDEX idx_scans_user_time ON ${Tables.scans}(user_id, logged_at DESC)');
      await db.execute(
          'CREATE INDEX idx_scans_user_date ON ${Tables.scans}(user_id, local_date)');
      await db.execute('''
        CREATE TABLE ${Tables.waterIntake} (
          user_id TEXT NOT NULL,
          local_date TEXT NOT NULL,
          total_ml INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (user_id, local_date)
        )''');
      await db.execute('''
        CREATE TABLE ${Tables.chatMessages} (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          role TEXT NOT NULL CHECK (role IN ('user', 'model')),
          text TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      await db.execute(
          'CREATE INDEX idx_chat_user_time ON ${Tables.chatMessages}(user_id, created_at)');
      await db.execute('''
        CREATE TABLE ${Tables.kv} (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE ${Tables.archiveLog} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          scans_count INTEGER NOT NULL,
          chat_count INTEGER NOT NULL,
          water_days INTEGER NOT NULL,
          retention_days INTEGER
        )''');
    },
    // v2: a meal can contain several foods.
    (db) async {
      await db.execute('ALTER TABLE ${Tables.scans} ADD COLUMN model_version TEXT');
      await db.execute(
          "ALTER TABLE ${Tables.scans} ADD COLUMN analysis_status TEXT NOT NULL DEFAULT 'confirmed'");
      await db.execute('''
        CREATE TABLE ${Tables.mealItems} (
          id TEXT PRIMARY KEY,
          scan_id TEXT NOT NULL REFERENCES ${Tables.scans}(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'other',
          weight REAL NOT NULL,
          unit TEXT NOT NULL DEFAULT 'g',
          calories REAL NOT NULL DEFAULT 0,
          protein REAL NOT NULL DEFAULT 0,
          carbs REAL NOT NULL DEFAULT 0,
          fats REAL NOT NULL DEFAULT 0,
          confidence REAL NOT NULL DEFAULT 1,
          source TEXT NOT NULL DEFAULT 'ai',
          original_name TEXT,
          original_calories REAL
        )''');
      await db.execute(
          'CREATE INDEX idx_items_scan ON ${Tables.mealItems}(scan_id, position)');
      // Existing meals had a single implicit food. Give each one an explicit
      // item so old data behaves exactly like new data.
      await db.execute('''
        INSERT INTO ${Tables.mealItems}
          (id, scan_id, position, name, category, weight, unit,
           calories, protein, carbs, fats, confidence, source)
        SELECT 'item_' || id, id, 0, food_name, 'other', 1, 'serving',
               calories, protein, carbs, fats, confidence, 'manual'
        FROM ${Tables.scans} WHERE type = 'food'
      ''');
    },
    // v3: physical activity, workouts and sleep (manual or from Health Connect).
    (db) async {
      await db.execute('''
        CREATE TABLE ${Tables.activityEntries} (
          id TEXT PRIMARY KEY,
          local_date TEXT NOT NULL,
          start_ms INTEGER NOT NULL,
          end_ms INTEGER NOT NULL,
          type TEXT NOT NULL,
          steps INTEGER NOT NULL DEFAULT 0,
          distance_m REAL NOT NULL DEFAULT 0,
          active_kcal REAL NOT NULL DEFAULT 0,
          source TEXT NOT NULL,
          origin TEXT,
          external_id TEXT,
          UNIQUE (source, external_id)
        )''');
      await db.execute(
          'CREATE INDEX idx_activity_date ON ${Tables.activityEntries}(local_date, start_ms)');
      await db.execute('''
        CREATE TABLE ${Tables.workouts} (
          id TEXT PRIMARY KEY,
          local_date TEXT NOT NULL,
          type TEXT NOT NULL,
          start_ms INTEGER NOT NULL,
          end_ms INTEGER NOT NULL,
          calories REAL,
          calories_estimated INTEGER NOT NULL DEFAULT 0,
          distance_m REAL,
          avg_heart_rate INTEGER,
          notes TEXT,
          source TEXT NOT NULL,
          origin TEXT,
          external_id TEXT,
          UNIQUE (source, external_id)
        )''');
      await db.execute(
          'CREATE INDEX idx_workouts_date ON ${Tables.workouts}(local_date, start_ms)');
      await db.execute('''
        CREATE TABLE ${Tables.sleepEntries} (
          id TEXT PRIMARY KEY,
          local_date TEXT NOT NULL,
          start_ms INTEGER NOT NULL,
          end_ms INTEGER NOT NULL,
          minutes_asleep INTEGER NOT NULL,
          source TEXT NOT NULL,
          origin TEXT,
          external_id TEXT,
          UNIQUE (source, external_id)
        )''');
      await db.execute(
          'CREATE INDEX idx_sleep_date ON ${Tables.sleepEntries}(local_date)');
    },
    // v4: food library (built-in + custom) and Food Twin corrections.
    (db) async {
      await db.execute('''
        CREATE TABLE ${Tables.foods} (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          aliases TEXT NOT NULL DEFAULT '',
          tags TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT 'other',
          serving TEXT NOT NULL,
          serving_grams REAL NOT NULL,
          calories REAL NOT NULL,
          protein REAL NOT NULL,
          carbs REAL NOT NULL,
          fats REAL NOT NULL,
          fiber REAL,
          source TEXT NOT NULL,
          confidence REAL NOT NULL DEFAULT 0.75,
          is_custom INTEGER NOT NULL DEFAULT 0,
          search_text TEXT NOT NULL,
          use_count INTEGER NOT NULL DEFAULT 0,
          last_used_ms INTEGER,
          created_ms INTEGER NOT NULL
        )''');
      await db.execute('CREATE INDEX idx_foods_name ON ${Tables.foods}(name)');
      await db.execute('CREATE INDEX idx_foods_used ON ${Tables.foods}(last_used_ms DESC)');
      await db.execute('''
        CREATE TABLE ${Tables.foodCorrections} (
          id TEXT PRIMARY KEY,
          scan_id TEXT NOT NULL REFERENCES ${Tables.scans}(id) ON DELETE CASCADE,
          item_id TEXT NOT NULL,
          key TEXT NOT NULL,
          original_name TEXT NOT NULL,
          corrected_name TEXT NOT NULL,
          original_kcal REAL NOT NULL,
          corrected_kcal REAL NOT NULL,
          weight REAL,
          unit TEXT,
          created_ms INTEGER NOT NULL
        )''');
      await db.execute('CREATE INDEX idx_corr_key ON ${Tables.foodCorrections}(key)');
    },
    // v5: MessOS - campus / hostel menus.
    (db) async {
      await db.execute('''
        CREATE TABLE ${Tables.messes} (
          id TEXT PRIMARY KEY,
          college TEXT NOT NULL,
          hostel TEXT NOT NULL,
          name TEXT NOT NULL,
          created_ms INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE ${Tables.messMenus} (
          id TEXT PRIMARY KEY,
          mess_id TEXT NOT NULL REFERENCES ${Tables.messes}(id) ON DELETE CASCADE,
          local_date TEXT NOT NULL,
          updated_ms INTEGER NOT NULL,
          UNIQUE (mess_id, local_date)
        )''');
      await db.execute('''
        CREATE TABLE ${Tables.messMeals} (
          id TEXT PRIMARY KEY,
          menu_id TEXT NOT NULL REFERENCES ${Tables.messMenus}(id) ON DELETE CASCADE,
          meal_type TEXT NOT NULL,
          dishes TEXT NOT NULL,
          logged_scan_id TEXT REFERENCES ${Tables.scans}(id) ON DELETE SET NULL,
          updated_ms INTEGER NOT NULL,
          UNIQUE (menu_id, meal_type)
        )''');
      await db.execute('CREATE INDEX idx_mess_menu_date ON ${Tables.messMenus}(mess_id, local_date DESC)');
    },
    // v6: weight history (one row each time the weight is recorded).
    (db) async {
      await db.execute('''
        CREATE TABLE ${Tables.weightEntries} (
          id TEXT PRIMARY KEY,
          weight_kg REAL NOT NULL,
          measured_ms INTEGER NOT NULL,
          local_date TEXT NOT NULL
        )''');
      await db.execute('CREATE INDEX idx_weight_date ON ${Tables.weightEntries}(local_date, measured_ms)');
    },
  ];

  // ---------------------------------------------------------------------------
  // Change notification (drives reactive streams in the UI)
  // ---------------------------------------------------------------------------

  /// Repositories call this after every write.
  void notify(String table) {
    if (!_changes.isClosed) _changes.add(table);
  }

  /// Emits [query]'s result now and again whenever any of [tables] changes.
  /// Bursts of writes are coalesced so a slow query never queues up.
  Stream<T> watch<T>(Set<String> tables, Future<T> Function() query) {
    late final StreamController<T> controller;
    StreamSubscription<String>? sub;
    var running = false;
    var dirty = false;

    Future<void> run() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      try {
        do {
          dirty = false;
          final value = await query();
          if (!controller.isClosed) controller.add(value);
        } while (dirty);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      } finally {
        running = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.where(tables.contains).listen((_) => run());
        run();
      },
      onCancel: () async {
        await sub?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // Key/value settings
  // ---------------------------------------------------------------------------

  Future<String?> getKv(String key) async {
    final rows = await db.query(Tables.kv,
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setKv(String key, String? value) async {
    if (value == null) {
      await db.delete(Tables.kv, where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert(Tables.kv, {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    notify(Tables.kv);
  }

  Future<void> close() async {
    await _changes.close();
    await db.close();
    debugPrint('[AppDatabase] closed');
  }
}
