import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/chat_message.dart';
import '../models/daily_summary.dart';
import '../models/food_memory_item.dart';
import '../db/local_database.dart';
import 'local_file_service.dart';

// Standalone On-Device Storage Service Provider
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

// Standardized Output Streams
final scanHistoryStreamProvider = StreamProvider.autoDispose<List<ScanResult>>((ref) {
  return ref.watch(storageServiceProvider).streamScanHistory();
});

final chatHistoryStreamProvider = StreamProvider.autoDispose<List<ChatMessage>>((ref) {
  return ref.watch(storageServiceProvider).streamChatHistory();
});

final dailySummaryStreamProvider = StreamProvider.autoDispose<DailySummary?>((ref) {
  return ref.watch(storageServiceProvider).streamDailySummary();
});

/// NutriSnap AI - 100% On-Device Private Local Storage Service for Flutter
/// Every write here goes straight to the on-device SQLite database
/// (LocalDatabase), so scans, chats and summaries survive app restarts.
/// The in-memory caches below exist only to drive instant stream updates
/// for the UI — LocalDatabase is always the source of truth.
class StorageService {
  String _currentUid = 'local_user_default';

  // In-memory reactive state caches (mirrors of on-device SQLite rows)
  final List<ScanResult> _cachedScans = [];
  final List<ChatMessage> _cachedMessages = [];
  final Map<String, DailySummary> _cachedSummaries = {};
  UserProfile? _cachedProfile;

  // Stream controllers for real-time reactivity
  final _scansController = StreamController<List<ScanResult>>.broadcast();
  final _chatController = StreamController<List<ChatMessage>>.broadcast();
  final _summaryController = StreamController<DailySummary?>.broadcast();

  void setCurrentUid(String uid) {
    if (_currentUid == uid) return;
    _currentUid = uid;
    // Drop stale in-memory state from the previous user; the next stream
    // subscription / getter call re-hydrates from LocalDatabase for this uid.
    _cachedScans.clear();
    _cachedMessages.clear();
    _cachedSummaries.clear();
    _cachedProfile = null;
  }

  String get currentUid => _currentUid;

  String _formatDate(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  DailySummary _emptySummary(String date) => DailySummary(
        date: date,
        totalCalories: 0,
        totalProtein: 0,
        totalCarbs: 0,
        totalFats: 0,
        totalWater: 0,
      );

  // ==========================================
  // ON-DEVICE IMAGE HANDLING (Local file / Base64 fallback)
  // ==========================================

  Future<String> _fileToBase64DataUri(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      debugPrint('Error reading file to base64: $e');
      return file.path;
    }
  }

  Future<String> uploadProfileImage(File file, {Function(double)? onProgress}) async {
    onProgress?.call(0.3);
    String savedPath;
    try {
      final localFileService = LocalFileService();
      savedPath = await localFileService.saveProfilePicture(file, userId: _currentUid);
    } catch (_) {
      savedPath = await _fileToBase64DataUri(file);
    }
    onProgress?.call(1.0);
    if (_cachedProfile != null) {
      _cachedProfile = _cachedProfile!.copyWith(photoURL: savedPath);
      try {
        await LocalDatabase.instance.saveProfile(_cachedProfile!);
      } catch (e) {
        debugPrint('[StorageService] Error saving profile to LocalDatabase: $e');
      }
    }
    return savedPath;
  }

  Future<String> uploadBodyImage(File file, {Function(double)? onProgress}) async {
    onProgress?.call(0.3);
    String savedPath;
    try {
      final localFileService = LocalFileService();
      savedPath = await localFileService.saveBodyScanImage(file);
    } catch (_) {
      savedPath = await _fileToBase64DataUri(file);
    }
    onProgress?.call(1.0);
    if (_cachedProfile != null) {
      _cachedProfile = _cachedProfile!.copyWith(bodyScanURL: savedPath);
      try {
        await LocalDatabase.instance.saveProfile(_cachedProfile!);
      } catch (e) {
        debugPrint('[StorageService] Error saving profile to LocalDatabase: $e');
      }
    }
    return savedPath;
  }

  Future<String> uploadScanImage(File file, {Function(double)? onProgress}) async {
    onProgress?.call(0.3);
    String savedPath;
    try {
      final localFileService = LocalFileService();
      savedPath = await localFileService.saveFoodImage(file);
    } catch (_) {
      savedPath = await _fileToBase64DataUri(file);
    }
    onProgress?.call(1.0);
    return savedPath;
  }

  // ==========================================
  // SCANS & HISTORY
  // ==========================================

  Future<ScanResult> saveScanResult(ScanResult scan) async {
    final newId = scan.id.isNotEmpty && scan.id != 'temp' ? scan.id : 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final finalScan = ScanResult(
      id: newId,
      userId: _currentUid,
      foodName: scan.foodName,
      type: scan.type,
      description: scan.description,
      details: scan.details,
      calories: scan.calories,
      protein: scan.protein,
      carbs: scan.carbs,
      fats: scan.fats,
      fatEstimate: scan.fatEstimate,
      confidence: scan.confidence,
      imageUrl: scan.imageUrl,
      timestamp: scan.timestamp.isNotEmpty ? scan.timestamp : DateTime.now().toIso8601String(),
    );

    _cachedScans.insert(0, finalScan);
    _scansController.add(List.unmodifiable(_cachedScans));

    await LocalDatabase.instance.insertScan(finalScan);
    await updateDailySummary(finalScan);

    // Personal Food Twin: learn from every food scan (not body/person/animal
    // detections), so regional & home-cooked dishes the user repeats get
    // recognized faster over time — entirely on-device.
    if (finalScan.type == 'food') {
      await recordFoodScanInMemory(finalScan);
    }

    return finalScan;
  }

  // ==========================================
  // PERSONAL FOOD TWIN (Food Memory)
  // ==========================================

  List<FoodMemoryItem> _defaultFoodMemory() {
    final now = DateTime.now();
    return [
      FoodMemoryItem(
        id: 'fm_1',
        foodName: 'Paneer Butter Masala & Roti',
        localName: 'North Indian Meal',
        category: 'Indian Curry',
        scanCount: 6,
        avgCalories: 580,
        lastEaten: now.subtract(const Duration(days: 1)).toIso8601String(),
        tags: const ['Vegetarian', 'High Protein', 'Comfort Food'],
        isPreferred: true,
        confidenceScore: 0.98,
      ),
      FoodMemoryItem(
        id: 'fm_2',
        foodName: 'Oats with Almonds & Banana',
        localName: 'Morning Oats Bowl',
        category: 'Breakfast',
        scanCount: 12,
        avgCalories: 340,
        lastEaten: now.toIso8601String(),
        tags: const ['High Fiber', 'Clean Carb', 'Quick Prep'],
        isPreferred: true,
        confidenceScore: 0.99,
      ),
      FoodMemoryItem(
        id: 'fm_3',
        foodName: 'Grilled Chicken Salad with Olive Oil',
        localName: 'Lean Salad',
        category: 'Salad',
        scanCount: 8,
        avgCalories: 410,
        lastEaten: now.subtract(const Duration(days: 2)).toIso8601String(),
        tags: const ['Lean Protein', 'Low Carb', 'Post-Workout'],
        isPreferred: true,
        confidenceScore: 0.96,
      ),
    ];
  }

  Future<List<FoodMemoryItem>> getFoodMemory() async {
    await LocalDatabase.instance.seedFoodMemoryIfEmpty(_defaultFoodMemory(), userId: _currentUid);
    return LocalDatabase.instance.getFoodMemory(userId: _currentUid);
  }

  Future<void> recordFoodScanInMemory(ScanResult scan) async {
    final db = LocalDatabase.instance;
    final existing = await db.findFoodMemoryByName(userId: _currentUid, foodName: scan.foodName);
    if (existing != null) {
      final newCount = existing.scanCount + 1;
      final newAvg = (((existing.avgCalories * existing.scanCount) + scan.calories) / newCount).round();
      await db.upsertFoodMemory(
        existing.copyWith(scanCount: newCount, avgCalories: newAvg, lastEaten: scan.timestamp),
        userId: _currentUid,
      );
    } else {
      await db.upsertFoodMemory(
        FoodMemoryItem(
          id: 'fm_${DateTime.now().millisecondsSinceEpoch}',
          foodName: scan.foodName,
          category: scan.type ?? 'Custom',
          scanCount: 1,
          avgCalories: scan.calories,
          lastEaten: scan.timestamp,
          tags: const ['Scanned Meal'],
          confidenceScore: scan.confidence > 0 ? scan.confidence : 0.9,
        ),
        userId: _currentUid,
      );
    }
  }

  Future<ScanResult?> getScanResult(String id) async {
    final cached = _cachedScans.where((s) => s.id == id).firstOrNull;
    if (cached != null) return cached;
    final scans = await LocalDatabase.instance.getScans(userId: _currentUid);
    return scans.where((s) => s.id == id).firstOrNull;
  }

  Future<void> deleteScanResult(String id, ScanResult scan) async {
    _cachedScans.removeWhere((s) => s.id == id);
    _scansController.add(List.unmodifiable(_cachedScans));

    await LocalDatabase.instance.deleteScan(id, userId: _currentUid);
    await _adjustDailySummary(scan, reverse: true);
  }

  Future<void> updateScanResult(ScanResult updatedScan) async {
    final idx = _cachedScans.indexWhere((s) => s.id == updatedScan.id);
    ScanResult? previous;
    if (idx != -1) {
      previous = _cachedScans[idx];
      _cachedScans[idx] = updatedScan;
    }
    _scansController.add(List.unmodifiable(_cachedScans));

    await LocalDatabase.instance.insertScan(updatedScan);
    if (previous != null) {
      await _adjustDailySummary(previous, reverse: true);
      await _adjustDailySummary(updatedScan, reverse: false);
    }
  }

  Stream<List<ScanResult>> streamScanHistory() async* {
    final fromDb = await LocalDatabase.instance.getScans(userId: _currentUid);
    _cachedScans
      ..clear()
      ..addAll(fromDb);
    yield List.unmodifiable(_cachedScans);
    yield* _scansController.stream;
  }

  Future<List<ScanResult>> getScanHistory() async {
    final scans = await LocalDatabase.instance.getScans(userId: _currentUid);
    _cachedScans
      ..clear()
      ..addAll(scans);
    return scans;
  }

  Future<List<ScanResult>> getRecentScans({int limit = 15}) async {
    final scans = await getScanHistory();
    return scans.take(limit).toList();
  }

  // ==========================================
  // DAILY SUMMARY & WATER TRACKING
  // ==========================================

  Future<void> _adjustDailySummary(ScanResult scan, {required bool reverse}) async {
    final date = scan.timestamp.isNotEmpty ? scan.timestamp.split('T').first : _formatDate(DateTime.now());
    final sign = reverse ? -1 : 1;
    final onDevice = await LocalDatabase.instance.getDailySummary(date, userId: _currentUid);
    final current = onDevice ?? _cachedSummaries[date] ?? _emptySummary(date);

    final updated = current.copyWith(
      totalCalories: (current.totalCalories + sign * scan.calories).clamp(0, 1 << 30).toInt(),
      totalProtein: (current.totalProtein + sign * scan.protein).clamp(0, 1 << 30).toInt(),
      totalCarbs: (current.totalCarbs + sign * scan.carbs).clamp(0, 1 << 30).toInt(),
      totalFats: (current.totalFats + sign * scan.fats).clamp(0, 1 << 30).toInt(),
    );

    _cachedSummaries[date] = updated;
    await LocalDatabase.instance.saveDailySummary(updated, userId: _currentUid);
    final today = _formatDate(DateTime.now());
    if (date == today) _summaryController.add(updated);
  }

  Future<void> updateDailySummary(ScanResult scan) async {
    await _adjustDailySummary(scan, reverse: false);
  }

  Future<void> updateWaterIntake(int amount) async {
    final today = _formatDate(DateTime.now());
    final onDevice = await LocalDatabase.instance.getDailySummary(today, userId: _currentUid);
    final current = onDevice ?? _cachedSummaries[today] ?? _emptySummary(today);

    final newWater = (current.totalWater + amount).clamp(0, 50000).toInt();
    final updated = current.copyWith(totalWater: newWater);

    _cachedSummaries[today] = updated;
    await LocalDatabase.instance.saveDailySummary(updated, userId: _currentUid);
    _summaryController.add(updated);
  }

  Future<DailySummary?> getDailySummary([DateTime? targetDate]) async {
    final dateKey = _formatDate(targetDate ?? DateTime.now());
    final onDevice = await LocalDatabase.instance.getDailySummary(dateKey, userId: _currentUid);
    final summary = onDevice ?? _emptySummary(dateKey);
    _cachedSummaries[dateKey] = summary;
    return summary;
  }

  Stream<DailySummary?> streamDailySummary() async* {
    final today = _formatDate(DateTime.now());
    final fromDb = await LocalDatabase.instance.getDailySummary(today, userId: _currentUid);
    final summary = fromDb ?? _emptySummary(today);
    _cachedSummaries[today] = summary;
    yield summary;
    yield* _summaryController.stream;
  }

  // ==========================================
  // AI CHAT HISTORY
  // ==========================================

  Future<ChatMessage> saveChatMessage(String role, String text) async {
    final message = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      userId: _currentUid,
      role: role,
      text: text,
      timestamp: DateTime.now().toIso8601String(),
    );
    _cachedMessages.add(message);
    _chatController.add(List.unmodifiable(_cachedMessages));
    await LocalDatabase.instance.insertChatMessage(message);
    return message;
  }

  Stream<List<ChatMessage>> streamChatHistory() async* {
    final fromDb = await LocalDatabase.instance.getChatMessages(userId: _currentUid);
    _cachedMessages
      ..clear()
      ..addAll(fromDb);
    yield List.unmodifiable(_cachedMessages);
    yield* _chatController.stream;
  }

  Future<List<ChatMessage>> getChatHistory() async {
    final messages = await LocalDatabase.instance.getChatMessages(userId: _currentUid);
    _cachedMessages
      ..clear()
      ..addAll(messages);
    return messages;
  }

  Future<void> clearChatHistory() async {
    _cachedMessages.clear();
    _chatController.add(List.unmodifiable(_cachedMessages));
    await LocalDatabase.instance.clearChatMessages(userId: _currentUid);
  }

  // ==========================================
  // PROFILE MANAGEMENT & ON-DEVICE PRIVACY
  // ==========================================

  Future<void> saveUserProfile(UserProfile profile) async {
    _cachedProfile = profile;
    try {
      await LocalDatabase.instance.saveProfile(profile);
    } catch (e) {
      debugPrint('[StorageService] Error saving profile to LocalDatabase: $e');
    }
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    if (_cachedProfile != null && _cachedProfile!.uid == uid) return _cachedProfile;
    try {
      final fromDb = await LocalDatabase.instance.getProfile(uid);
      if (fromDb != null) {
        _cachedProfile = fromDb;
        return fromDb;
      }
    } catch (e) {
      debugPrint('[StorageService] Error loading profile from LocalDatabase: $e');
    }
    return _cachedProfile;
  }

  // ==========================================
  // BACKUP EXPORT / IMPORT / RESET
  // ==========================================

  Future<String> exportLocalDataJson() async {
    final map = await LocalDatabase.instance.getAllUserData(_currentUid);
    map['version'] = '2.0.0-on-device';
    return jsonEncode(map);
  }

  Future<bool> importLocalDataJson(String jsonStr) async {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final db = LocalDatabase.instance;

      if (map['profile'] != null) {
        final profile = UserProfile.fromMap(map['profile'] as Map<String, dynamic>);
        await db.saveProfile(profile);
        _cachedProfile = profile;
      }
      if (map['scans'] is List) {
        for (final s in (map['scans'] as List)) {
          await db.insertScan(ScanResult.fromMap(s as Map<String, dynamic>));
        }
      }
      if (map['summaries'] is List) {
        for (final s in (map['summaries'] as List)) {
          await db.saveDailySummary(DailySummary.fromMap(s as Map<String, dynamic>), userId: _currentUid);
        }
      } else if (map['summaries'] is Map) {
        for (final entry in (map['summaries'] as Map).entries) {
          await db.saveDailySummary(DailySummary.fromMap(entry.value as Map<String, dynamic>), userId: _currentUid);
        }
      }
      if (map['chat'] is List) {
        for (final c in (map['chat'] as List)) {
          await db.insertChatMessage(ChatMessage.fromMap(c as Map<String, dynamic>));
        }
      }

      _scansController.add(await db.getScans(userId: _currentUid));
      _chatController.add(await db.getChatMessages(userId: _currentUid));
      final today = _formatDate(DateTime.now());
      _summaryController.add(await db.getDailySummary(today, userId: _currentUid));
      return true;
    } catch (e) {
      debugPrint('Error importing local backup: $e');
      return false;
    }
  }

  Future<void> clearAllLocalData() async {
    _cachedScans.clear();
    _cachedMessages.clear();
    _cachedSummaries.clear();
    _cachedProfile = null;
    _scansController.add([]);
    _chatController.add([]);
    _summaryController.add(null);
    await LocalDatabase.instance.clearAllForUser(_currentUid);
  }
}
