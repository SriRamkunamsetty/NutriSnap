import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/chat_message.dart';
import '../models/daily_summary.dart';
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
/// Completely eliminates all external cloud databases (Firebase, Firestore, Firebase Storage).
/// Keeps user nutritional logs, scans, and AI chats securely on-device.
class StorageService {
  String _currentUid = 'local_user_default';
  
  // In-memory reactive state caches
  final List<ScanResult> _cachedScans = [];
  final List<ChatMessage> _cachedMessages = [];
  final Map<String, DailySummary> _cachedSummaries = {};
  UserProfile? _cachedProfile;

  // Stream controllers for real-time reactivity
  final _scansController = StreamController<List<ScanResult>>.broadcast();
  final _chatController = StreamController<List<ChatMessage>>.broadcast();
  final _summaryController = StreamController<DailySummary?>.broadcast();

  StorageService() {
    _initDefaults();
  }

  void setCurrentUid(String uid) {
    _currentUid = uid;
  }

  String get currentUid => _currentUid;

  void _initDefaults() {
    // Initial sample/clean state
    final today = _formatDate(DateTime.now());
    if (!_cachedSummaries.containsKey(today)) {
      _cachedSummaries[today] = DailySummary(
        date: today,
        totalCalories: 0,
        totalProtein: 0,
        totalCarbs: 0,
        totalFats: 0,
        totalWater: 0,
      );
    }
  }

  String _formatDate(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  // ==========================================
  // ON-DEVICE IMAGE HANDLING (Base64 / Local)
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
    final newId = scan.id.isNotEmpty ? scan.id : "scan_${DateTime.now().millisecondsSinceEpoch}";
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

    // Update today's nutrition
    await updateDailySummary(finalScan);

    return finalScan;
  }

  Future<void> deleteScan(String scanId) async {
    _cachedScans.removeWhere((s) => s.id == scanId);
    _scansController.add(List.unmodifiable(_cachedScans));
  }

  Stream<List<ScanResult>> streamScanHistory() async* {
    yield List.unmodifiable(_cachedScans);
    yield* _scansController.stream;
  }

  Future<List<ScanResult>> getRecentScans({int limit = 15}) async {
    return _cachedScans.take(limit).toList();
  }

  // ==========================================
  // DAILY SUMMARY & WATER TRACKING
  // ==========================================

  Future<void> updateDailySummary(ScanResult scan) async {
    final today = _formatDate(DateTime.now());
    final current = _cachedSummaries[today] ?? DailySummary(
      date: today,
      totalCalories: 0,
      totalProtein: 0,
      totalCarbs: 0,
      totalFats: 0,
      totalWater: 0,
    );

    final updated = current.copyWith(
      totalCalories: current.totalCalories + scan.calories,
      totalProtein: current.totalProtein + scan.protein,
      totalCarbs: current.totalCarbs + scan.carbs,
      totalFats: current.totalFats + scan.fats,
    );

    _cachedSummaries[today] = updated;
    _summaryController.add(updated);
  }

  Future<void> updateWaterIntake(int amount) async {
    final today = _formatDate(DateTime.now());
    final current = _cachedSummaries[today] ?? DailySummary(
      date: today,
      totalCalories: 0,
      totalProtein: 0,
      totalCarbs: 0,
      totalFats: 0,
      totalWater: 0,
    );

    final newWater = (current.totalWater + amount).clamp(0, 50000);
    final updated = current.copyWith(totalWater: newWater);

    _cachedSummaries[today] = updated;
    _summaryController.add(updated);
  }

  Future<DailySummary?> getDailySummary([DateTime? targetDate]) async {
    final dateKey = _formatDate(targetDate ?? DateTime.now());
    return _cachedSummaries[dateKey] ?? DailySummary(
      date: dateKey,
      totalCalories: 0,
      totalProtein: 0,
      totalCarbs: 0,
      totalFats: 0,
      totalWater: 0,
    );
  }

  Stream<DailySummary?> streamDailySummary() async* {
    final today = _formatDate(DateTime.now());
    yield _cachedSummaries[today];
    yield* _summaryController.stream;
  }

  // ==========================================
  // AI CHAT HISTORY
  // ==========================================

  Future<void> saveChatMessage(ChatMessage message) async {
    _cachedMessages.add(message);
    _chatController.add(List.unmodifiable(_cachedMessages));
  }

  Stream<List<ChatMessage>> streamChatHistory() async* {
    yield List.unmodifiable(_cachedMessages);
    yield* _chatController.stream;
  }

  Future<void> clearChatHistory() async {
    _cachedMessages.clear();
    _chatController.add(List.unmodifiable(_cachedMessages));
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
    if (_cachedProfile != null) return _cachedProfile;
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

  String exportLocalDataJson() {
    final map = {
      'version': '2.0.0-on-device',
      'exportDate': DateTime.now().toIso8601String(),
      'profile': _cachedProfile?.toMap(),
      'scans': _cachedScans.map((s) => s.toMap()).toList(),
      'summaries': _cachedSummaries.map((k, v) => MapEntry(k, v.toMap())),
      'chat': _cachedMessages.map((m) => m.toMap()).toList(),
    };
    return jsonEncode(map);
  }

  bool importLocalDataJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('profile') && map['profile'] != null) {
        _cachedProfile = UserProfile.fromMap(map['profile'] as Map<String, dynamic>);
      }
      if (map.containsKey('scans') && map['scans'] is List) {
        _cachedScans.clear();
        for (var s in map['scans']) {
          _cachedScans.add(ScanResult.fromMap(s as Map<String, dynamic>));
        }
        _scansController.add(List.unmodifiable(_cachedScans));
      }
      if (map.containsKey('summaries') && map['summaries'] is Map) {
        _cachedSummaries.clear();
        (map['summaries'] as Map).forEach((k, v) {
          _cachedSummaries[k.toString()] = DailySummary.fromMap(v as Map<String, dynamic>);
        });
        final today = _formatDate(DateTime.now());
        _summaryController.add(_cachedSummaries[today]);
      }
      return true;
    } catch (e) {
      debugPrint('Error importing local backup: $e');
      return false;
    }
  }

  void clearAllLocalData() {
    _cachedScans.clear();
    _cachedMessages.clear();
    _cachedSummaries.clear();
    _cachedProfile = null;
    _scansController.add([]);
    _chatController.add([]);
    _summaryController.add(null);
  }
}
