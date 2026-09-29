import 'dart:io';

import 'package:nutrisnap_app/core/database/app_database.dart';
import 'package:nutrisnap_app/core/repositories/activity_repository.dart';
import 'package:nutrisnap_app/core/repositories/chat_repository.dart';
import 'package:nutrisnap_app/core/repositories/food_repository.dart';
import 'package:nutrisnap_app/core/repositories/mess_repository.dart';
import 'package:nutrisnap_app/core/services/mess_service.dart';
import 'package:nutrisnap_app/core/services/food_twin_service.dart';
import 'package:nutrisnap_app/core/repositories/profile_repository.dart';
import 'package:nutrisnap_app/core/repositories/scan_repository.dart';
import 'package:nutrisnap_app/core/repositories/settings_repository.dart';
import 'package:nutrisnap_app/core/repositories/summary_repository.dart';
import 'package:nutrisnap_app/core/services/backup_service.dart';
import 'package:nutrisnap_app/core/services/image_store.dart';
import 'package:nutrisnap_app/core/services/retention_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A complete, isolated NutriSnap data stack backed by in-memory SQLite and a
/// temp directory. Create one per test and call [dispose].
class TestEnv {
  TestEnv._(this.dir, this.db, this.images) {
    profiles = ProfileRepository(db, images);
    scans = ScanRepository(db, images);
    summaries = SummaryRepository(db);
    chat = ChatRepository(db);
    activity = ActivityRepository(db);
    foods = FoodRepository(db);
    twin = FoodTwinService(db, foods);
    messes = MessRepository(db);
    mess = MessService(foods: foods, messes: messes, scans: scans);
    settings = SettingsRepository(db);
    backup = BackupService(
      database: db,
      images: images,
      profiles: profiles,
      scans: scans,
      summaries: summaries,
      chat: chat,
      tempDirectory: () async => Directory('${dir.path}/tmp')..createSync(recursive: true),
    );
    retention = RetentionService(
      database: db,
      scans: scans,
      chat: chat,
      summaries: summaries,
      settings: settings,
      archiveDirectory: () async => Directory('${dir.path}/archives')..createSync(recursive: true),
    );
  }

  final Directory dir;
  final AppDatabase db;
  final ImageStore images;

  late final ProfileRepository profiles;
  late final ScanRepository scans;
  late final SummaryRepository summaries;
  late final ChatRepository chat;
  late final ActivityRepository activity;
  late final FoodRepository foods;
  late final FoodTwinService twin;
  late final MessRepository messes;
  late final MessService mess;
  late final SettingsRepository settings;
  late final BackupService backup;
  late final RetentionService retention;

  /// A retention service that archives into [directory].
  RetentionService retentionWith(Future<Directory> Function() directory) => RetentionService(
        database: db,
        scans: scans,
        chat: chat,
        summaries: summaries,
        settings: settings,
        archiveDirectory: directory,
      );

  static bool _ffiReady = false;

  static Future<TestEnv> create() async {
    if (!_ffiReady) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiReady = true;
    }
    final dir = await Directory.systemTemp.createTemp('nutrisnap_test_');
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    final images = ImageStore(Directory('${dir.path}/images')..createSync(recursive: true));
    return TestEnv._(dir, db, images);
  }

  Future<void> dispose() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
