import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/daily_summary.dart';
import '../models/chat_message.dart';
import '../models/food_memory_item.dart';

/// Provider for LocalDatabase
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  return LocalDatabase.instance;
});

/// NutriSnap AI - On-Device SQLite Local Database
/// Real, persistent on-device storage (sqflite) for user profiles, meal scans,
/// daily summaries, and chat history. Nothing here ever leaves the device.
class LocalDatabase {
  static const String dbName = 'nutrisnap_ai.db';
  static const int dbVersion = 4;

  // Table Names
  static const String tableProfiles = 'profiles';
  static const String tableScans = 'scans';
  static const String tableDailySummaries = 'daily_summaries';
  static const String tableChatMessages = 'chat_messages';
  static const String tablePurgeLogs = 'purge_audit_logs';
  static const String tableFoodMemory = 'food_memory';

  static final LocalDatabase instance = LocalDatabase._internal();
  LocalDatabase._internal();

  Database? _database;
  Completer<Database>? _opening;

  // Reactive streams (still emitted by StorageService on writes; kept for
  // any direct LocalDatabase consumers).
  final _profileUpdateController = StreamController<UserProfile?>.broadcast();
  final _scansUpdateController = StreamController<List<ScanResult>>.broadcast();
  final _summaryUpdateController = StreamController<DailySummary?>.broadcast();
  final _chatUpdateController = StreamController<List<ChatMessage>>.broadcast();

  Stream<UserProfile?> get onProfileUpdated => _profileUpdateController.stream;
  Stream<List<ScanResult>> get onScansUpdated => _scansUpdateController.stream;
  Stream<DailySummary?> get onSummaryUpdated => _summaryUpdateController.stream;
  Stream<List<ChatMessage>> get onChatUpdated => _chatUpdateController.stream;

  static const String _createProfilesTableSQL = '''
    CREATE TABLE IF NOT EXISTS $tableProfiles (
      uid TEXT PRIMARY KEY,
      email TEXT NOT NULL,
      displayName TEXT,
      photoURL TEXT,
      localPhotoPath TEXT,
      height REAL,
      weight REAL,
      bmi REAL,
      age INTEGER DEFAULT 25,
      dob TEXT,
      gender TEXT DEFAULT 'male',
      bodyType TEXT DEFAULT 'mesomorph',
      fatEstimate REAL DEFAULT 18.0,
      muscleMass REAL DEFAULT 32.0,
      fitnessLevel TEXT DEFAULT 'Intermediate Fit',
      bodyScanURL TEXT,
      localBodyScanPath TEXT,
      goal TEXT DEFAULT 'maintain',
      calorieLimit INTEGER DEFAULT 2000,
      proteinGoal INTEGER DEFAULT 150,
      carbsGoal INTEGER DEFAULT 200,
      fatsGoal INTEGER DEFAULT 67,
      proteinPct REAL DEFAULT 30.0,
      carbsPct REAL DEFAULT 45.0,
      fatsPct REAL DEFAULT 25.0,
      waterGoal INTEGER DEFAULT 2500,
      lifestyle TEXT DEFAULT 'active',
      activityLevel TEXT DEFAULT 'moderate',
      dietaryPreferences TEXT,
      allergies TEXT,
      budgetRange TEXT DEFAULT 'moderate',
      isHostelUser INTEGER DEFAULT 0,
      isPremium INTEGER DEFAULT 0,
      reminders TEXT,
      theme TEXT DEFAULT 'light',
      hasCompletedOnboarding INTEGER DEFAULT 1,
      cloudAiConsent INTEGER DEFAULT 0,
      createdAt TEXT,
      lastLoginAt TEXT
    );
  ''';

  static const String _createScansTableSQL = '''
    CREATE TABLE IF NOT EXISTS $tableScans (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      foodName TEXT NOT NULL,
      calories INTEGER NOT NULL DEFAULT 0,
      protein REAL NOT NULL DEFAULT 0.0,
      carbs REAL NOT NULL DEFAULT 0.0,
      fats REAL NOT NULL DEFAULT 0.0,
      confidence REAL DEFAULT 1.0,
      imageUrl TEXT,
      localImagePath TEXT,
      type TEXT DEFAULT 'food',
      description TEXT,
      details TEXT,
      fatEstimate REAL DEFAULT 0.0,
      timestamp TEXT NOT NULL
    );
  ''';

  static const String _createDailySummariesTableSQL = '''
    CREATE TABLE IF NOT EXISTS $tableDailySummaries (
      date TEXT NOT NULL,
      userId TEXT NOT NULL,
      totalCalories INTEGER NOT NULL DEFAULT 0,
      totalProtein REAL NOT NULL DEFAULT 0.0,
      totalCarbs REAL NOT NULL DEFAULT 0.0,
      totalFats REAL NOT NULL DEFAULT 0.0,
      totalWater INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (date, userId)
    );
  ''';

  static const String _createChatMessagesTableSQL = '''
    CREATE TABLE IF NOT EXISTS $tableChatMessages (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      role TEXT NOT NULL,
      text TEXT NOT NULL,
      timestamp TEXT NOT NULL
    );
  ''';

  static const String _createPurgeLogsTableSQL = '''
    CREATE TABLE IF NOT EXISTS $tablePurgeLogs (
      id TEXT PRIMARY KEY,
      userEmail TEXT NOT NULL,
      purgedScansCount INTEGER NOT NULL,
      purgedMessagesCount INTEGER NOT NULL,
      purgedSummariesCount INTEGER NOT NULL,
      backupPayloadSize INTEGER NOT NULL,
      timestamp TEXT NOT NULL
    );
  ''';

  /// "Personal Food Twin" — the on-device model of a user's most-eaten
  /// dishes, keyed per-user so regional/home-cooked/mess foods it has
  /// learned stay private to that profile.
  static const String _createFoodMemoryTableSQL = '''
    CREATE TABLE IF NOT EXISTS $tableFoodMemory (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      foodName TEXT NOT NULL,
      localName TEXT,
      category TEXT DEFAULT 'Custom',
      scanCount INTEGER NOT NULL DEFAULT 1,
      avgCalories INTEGER NOT NULL DEFAULT 0,
      lastEaten TEXT NOT NULL,
      tags TEXT,
      isAllergy INTEGER DEFAULT 0,
      isPreferred INTEGER DEFAULT 0,
      confidenceScore REAL DEFAULT 0.9
    );
  ''';

  /// Opens (or returns the already-open) on-device SQLite database.
  Future<Database> get _db async {
    if (_database != null) return _database!;
    if (_opening != null) return _opening!.future;

    _opening = Completer<Database>();
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docsDir.path, dbName);

      final db = await openDatabase(
        dbPath,
        version: dbVersion,
        onCreate: (db, version) async {
          debugPrint('[LocalDatabase] Creating SQLite tables at $dbPath');
          final batch = db.batch();
          batch.execute(_createProfilesTableSQL);
          batch.execute(_createScansTableSQL);
          batch.execute(_createDailySummariesTableSQL);
          batch.execute(_createChatMessagesTableSQL);
          batch.execute(_createPurgeLogsTableSQL);
          batch.execute(_createFoodMemoryTableSQL);
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // All CREATE statements are idempotent (IF NOT EXISTS), so simply
          // re-running them brings an older on-device schema up to date
          // without ever dropping existing user data.
          final batch = db.batch();
          batch.execute(_createProfilesTableSQL);
          batch.execute(_createScansTableSQL);
          batch.execute(_createDailySummariesTableSQL);
          batch.execute(_createChatMessagesTableSQL);
          batch.execute(_createPurgeLogsTableSQL);
          batch.execute(_createFoodMemoryTableSQL);
          await batch.commit(noResult: true);
        },
      );

      _database = db;
      _opening!.complete(db);
      debugPrint('[LocalDatabase] SQLite initialization complete. Storage engine ready.');
      return db;
    } catch (e, st) {
      _opening!.completeError(e, st);
      _opening = null;
      rethrow;
    }
  }

  /// Kept for callers that explicitly warm up the database before first use.
  Future<void> initialize() async {
    await _db;
  }

  // ==========================================
  // JSON <-> SQL row helpers for complex fields
  // ==========================================

  Map<String, Object?> _profileRow(UserProfile profile) {
    final map = Map<String, dynamic>.from(profile.toMap());
    map['localPhotoPath'] = profile.photoURL;
    map['localBodyScanPath'] = profile.bodyScanURL;
    if (map['reminders'] != null) {
      map['reminders'] = jsonEncode(map['reminders']);
    }
    map['hasCompletedOnboarding'] = (map['hasCompletedOnboarding'] as bool?) == true ? 1 : 0;
    map['cloudAiConsent'] = (map['cloudAiConsent'] as bool?) == true ? 1 : 0;
    map['isHostelUser'] = (map['isHostelUser'] as bool?) == true ? 1 : 0;
    return map.map((key, value) => MapEntry(key, value as Object?));
  }

  UserProfile _profileFromRow(Map<String, Object?> row) {
    final map = Map<String, dynamic>.from(row);
    if (map['reminders'] is String && (map['reminders'] as String).isNotEmpty) {
      map['reminders'] = jsonDecode(map['reminders'] as String);
    }
    if (map['hasCompletedOnboarding'] is int) {
      map['hasCompletedOnboarding'] = map['hasCompletedOnboarding'] == 1;
    }
    if (map['cloudAiConsent'] is int) {
      map['cloudAiConsent'] = map['cloudAiConsent'] == 1;
    }
    if (map['isHostelUser'] is int) {
      map['isHostelUser'] = map['isHostelUser'] == 1;
    }
    return UserProfile.fromMap(map);
  }

  // ==========================================
  // PROFILE OPERATIONS
  // ==========================================

  Future<void> saveProfile(UserProfile profile) async {
    final db = await _db;
    await db.insert(
      tableProfiles,
      _profileRow(profile),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _profileUpdateController.add(profile);
    debugPrint('[LocalDatabase] Saved profile for ${profile.uid}');
  }

  Future<UserProfile?> getProfile(String uid) async {
    final db = await _db;
    final rows = await db.query(tableProfiles, where: 'uid = ?', whereArgs: [uid], limit: 1);
    if (rows.isEmpty) return null;
    return _profileFromRow(rows.first);
  }

  // ==========================================
  // SCANS OPERATIONS
  // ==========================================

  Future<void> insertScan(ScanResult scan) async {
    final db = await _db;
    final map = Map<String, Object?>.from(scan.toMap());
    map['localImagePath'] = scan.imageUrl;
    await db.insert(tableScans, map, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyScansChange(scan.userId);
  }

  Future<List<ScanResult>> getScans({String? userId, int limit = 200}) async {
    final db = await _db;
    final rows = await db.query(
      tableScans,
      where: userId != null ? 'userId = ?' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map((m) => ScanResult.fromMap(m)).toList();
  }

  Future<bool> deleteScan(String scanId, {String? userId}) async {
    final db = await _db;
    final removed = await db.delete(tableScans, where: 'id = ?', whereArgs: [scanId]);
    if (removed > 0) _notifyScansChange(userId);
    return removed > 0;
  }

  Future<int> deleteScansOlderThan(DateTime cutoff, {String? userId}) async {
    final db = await _db;
    final cutoffIso = cutoff.toIso8601String();
    final removed = await db.delete(
      tableScans,
      where: userId != null ? 'timestamp < ? AND userId = ?' : 'timestamp < ?',
      whereArgs: userId != null ? [cutoffIso, userId] : [cutoffIso],
    );
    if (removed > 0) _notifyScansChange(userId);
    return removed;
  }

  Future<void> _notifyScansChange(String? userId) async {
    final scans = await getScans(userId: userId);
    _scansUpdateController.add(List.unmodifiable(scans));
  }

  // ==========================================
  // DAILY SUMMARIES OPERATIONS
  // ==========================================

  Future<void> saveDailySummary(DailySummary summary, {String userId = 'local_user_default'}) async {
    final db = await _db;
    final map = Map<String, Object?>.from(summary.toMap());
    map['userId'] = userId;
    await db.insert(tableDailySummaries, map, conflictAlgorithm: ConflictAlgorithm.replace);
    _summaryUpdateController.add(summary);
  }

  Future<DailySummary?> getDailySummary(String date, {String userId = 'local_user_default'}) async {
    final db = await _db;
    final rows = await db.query(
      tableDailySummaries,
      where: 'date = ? AND userId = ?',
      whereArgs: [date, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailySummary.fromMap(rows.first);
  }

  Future<List<DailySummary>> getAllDailySummaries({String? userId}) async {
    final db = await _db;
    final rows = await db.query(
      tableDailySummaries,
      where: userId != null ? 'userId = ?' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'date DESC',
    );
    return rows.map((m) => DailySummary.fromMap(m)).toList();
  }

  Future<int> deleteDailySummariesOlderThan(DateTime cutoff, {String? userId}) async {
    final db = await _db;
    final cutoffDate =
        "${cutoff.year.toString().padLeft(4, '0')}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}";
    return db.delete(
      tableDailySummaries,
      where: userId != null ? 'date < ? AND userId = ?' : 'date < ?',
      whereArgs: userId != null ? [cutoffDate, userId] : [cutoffDate],
    );
  }

  // ==========================================
  // CHAT MESSAGES OPERATIONS
  // ==========================================

  Future<void> insertChatMessage(ChatMessage message) async {
    final db = await _db;
    await db.insert(tableChatMessages, Map<String, Object?>.from(message.toMap()), conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChatChange(message.userId);
  }

  Future<List<ChatMessage>> getChatMessages({String? userId}) async {
    final db = await _db;
    final rows = await db.query(
      tableChatMessages,
      where: userId != null ? 'userId = ?' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'timestamp ASC',
    );
    return rows.map((m) => ChatMessage.fromMap(m)).toList();
  }

  Future<void> clearChatMessages({String? userId}) async {
    final db = await _db;
    if (userId == null) {
      await db.delete(tableChatMessages);
    } else {
      await db.delete(tableChatMessages, where: 'userId = ?', whereArgs: [userId]);
    }
    _notifyChatChange(userId);
  }

  Future<int> deleteChatMessagesOlderThan(DateTime cutoff, {String? userId}) async {
    final db = await _db;
    final cutoffIso = cutoff.toIso8601String();
    final removed = await db.delete(
      tableChatMessages,
      where: userId != null ? 'timestamp < ? AND userId = ?' : 'timestamp < ?',
      whereArgs: userId != null ? [cutoffIso, userId] : [cutoffIso],
    );
    if (removed > 0) _notifyChatChange(userId);
    return removed;
  }

  Future<void> _notifyChatChange(String? userId) async {
    final messages = await getChatMessages(userId: userId);
    _chatUpdateController.add(List.unmodifiable(messages));
  }

  // ==========================================
  // PERSONAL FOOD TWIN (Food Memory)
  // ==========================================

  Map<String, Object?> _foodMemoryRow(FoodMemoryItem item, String userId) {
    final map = Map<String, dynamic>.from(item.toMap());
    map['userId'] = userId;
    map['tags'] = jsonEncode(item.tags);
    map['isAllergy'] = item.isAllergy == true ? 1 : 0;
    map['isPreferred'] = item.isPreferred == true ? 1 : 0;
    return map.map((key, value) => MapEntry(key, value as Object?));
  }

  FoodMemoryItem _foodMemoryFromRow(Map<String, Object?> row) {
    final map = Map<String, dynamic>.from(row);
    if (map['tags'] is String && (map['tags'] as String).isNotEmpty) {
      map['tags'] = jsonDecode(map['tags'] as String);
    }
    map['isAllergy'] = map['isAllergy'] == 1;
    map['isPreferred'] = map['isPreferred'] == 1;
    return FoodMemoryItem.fromMap(map);
  }

  Future<List<FoodMemoryItem>> getFoodMemory({required String userId}) async {
    final db = await _db;
    final rows = await db.query(
      tableFoodMemory,
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'scanCount DESC',
    );
    return rows.map(_foodMemoryFromRow).toList();
  }

  Future<FoodMemoryItem?> findFoodMemoryByName({required String userId, required String foodName}) async {
    final db = await _db;
    final rows = await db.query(
      tableFoodMemory,
      where: 'userId = ? AND LOWER(foodName) = ?',
      whereArgs: [userId, foodName.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _foodMemoryFromRow(rows.first);
  }

  Future<void> upsertFoodMemory(FoodMemoryItem item, {required String userId}) async {
    final db = await _db;
    await db.insert(tableFoodMemory, _foodMemoryRow(item, userId), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> seedFoodMemoryIfEmpty(List<FoodMemoryItem> defaults, {required String userId}) async {
    final existing = await getFoodMemory(userId: userId);
    if (existing.isNotEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final item in defaults) {
      batch.insert(tableFoodMemory, _foodMemoryRow(item, userId), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ==========================================
  // AUDIT LOGS & DATA EXTRACTION
  // ==========================================

  Future<void> recordPurgeLog(Map<String, dynamic> log) async {
    final db = await _db;
    await db.insert(tablePurgeLogs, Map<String, Object?>.from(log), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>> getAllUserData(String userId) async {
    final profile = await getProfile(userId);
    final scans = await getScans(userId: userId);
    final summaries = await getAllDailySummaries(userId: userId);
    final chat = await getChatMessages(userId: userId);

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'userId': userId,
      'profile': profile?.toMap(),
      'scans': scans.map((s) => s.toMap()).toList(),
      'summaries': summaries.map((s) => s.toMap()).toList(),
      'chat': chat.map((c) => c.toMap()).toList(),
    };
  }

  /// Wipes every on-device record for a given user (used by the in-app
  /// "clear all local data" / privacy reset action).
  Future<void> clearAllForUser(String userId) async {
    final db = await _db;
    final batch = db.batch();
    batch.delete(tableProfiles, where: 'uid = ?', whereArgs: [userId]);
    batch.delete(tableScans, where: 'userId = ?', whereArgs: [userId]);
    batch.delete(tableDailySummaries, where: 'userId = ?', whereArgs: [userId]);
    batch.delete(tableChatMessages, where: 'userId = ?', whereArgs: [userId]);
    batch.delete(tableFoodMemory, where: 'userId = ?', whereArgs: [userId]);
    await batch.commit(noResult: true);
    _profileUpdateController.add(null);
    _scansUpdateController.add(const []);
    _summaryUpdateController.add(null);
    _chatUpdateController.add(const []);
  }
}
