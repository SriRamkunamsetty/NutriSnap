import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_service.dart';
import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/chat_message.dart';
import '../models/daily_summary.dart';
import '../utils/firebase_exception_handler.dart';

// Provides the standalone Storage Service via Riverpod
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(firebaseServiceProvider));
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

class StorageService {
  final FirebaseService _firebaseService;

  StorageService(this._firebaseService);

  FirebaseFirestore get _db => _firebaseService.db;
  Reference get _storageRef => _firebaseService.storage.ref();

  String? get _currentUid => _firebaseService.auth.currentUser?.uid;

  void _requireAuth() {
    if (_currentUid == null) throw Exception('User not authenticated');
  }

  /// Implements resilient 3-strike Retry logic for arbitrary async ops
  Future<T> _withRetry<T>(Future<T> Function() action, {int maxAttempts = 3}) async {
    int attempt = 0;
    while (attempt < maxAttempts) {
      try {
        return await action();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    throw Exception('Retry limit exceeded');
  }

  // ==========================================
  // STORAGE (FILES & IMAGES) 
  // ==========================================

  Future<String> _uploadImageHelper(File file, String pathPrefix, {Function(double)? onProgress}) async {
    _requireAuth();
    final path = 'users/$_currentUid/${pathPrefix}_${DateTime.now().millisecondsSinceEpoch}';
    final ref = _storageRef.child(path);
    
    // Upload State Handling
    final uploadTask = ref.putFile(file);
    uploadTask.snapshotEvents.listen((event) {
      if (onProgress != null && event.totalBytes > 0) {
        onProgress(event.bytesTransferred / event.totalBytes);
      }
    });

    return await _withRetry(() async {
      await uploadTask;
      return await ref.getDownloadURL();
    });
  }

  Future<String> uploadProfileImage(File file, {Function(double)? onProgress}) async {
    final downloadURL = await _uploadImageHelper(file, 'profile', onProgress: onProgress);
    await _withRetry(() => _db.collection('users').doc(_currentUid).update({'photoURL': downloadURL}));
    return downloadURL;
  }

  Future<String> uploadAIAvatar(File file, {Function(double)? onProgress}) async {
    final downloadURL = await _uploadImageHelper(file, 'ai_avatar', onProgress: onProgress);
    await _withRetry(() => _db.collection('users').doc(_currentUid).update({'aiAvatarURL': downloadURL}));
    return downloadURL;
  }

  Future<String> uploadBodyImage(File file, {Function(double)? onProgress}) async {
    final downloadURL = await _uploadImageHelper(file, 'body_scans/scan', onProgress: onProgress);
    await _withRetry(() => _db.collection('users').doc(_currentUid).update({'bodyScanURL': downloadURL}));
    return downloadURL;
  }

  Future<String> uploadScanImage(File file, {Function(double)? onProgress}) async {
    return await _uploadImageHelper(file, 'scans/scan', onProgress: onProgress);
  }

  // ==========================================
  // USER PROFILE
  // ==========================================
  
  Future<void> saveUserProfile(UserProfile profile) async {
    _requireAuth();
    try {
      final map = profile.toMap();
      map['updatedAt'] = FieldValue.serverTimestamp();
      await _withRetry(() => _db.collection('users').doc(profile.uid).set(map, SetOptions(merge: true)));
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'saveUserProfile');
      rethrow;
    }
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    try {
      // Optimized to one-time fetch over listener.
      final snap = await _withRetry(() => _db.collection('users').doc(uid).get());
      if (snap.exists) return UserProfile.fromMap(snap.data()!);
      return null;
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'getUserProfile');
      return null;
    }
  }

  // ==========================================
  // DAILY SUMMARY
  // ==========================================

  Future<void> updateDailySummary(ScanResult scan) async {
    _requireAuth();
    final date = DateTime.now().toIso8601String().split('T')[0];
    try {
      await _withRetry(() => _db.collection('users').doc(_currentUid).collection('daily_summary').doc(date).set({
        'date': date,
        'totalCalories': FieldValue.increment(scan.calories),
        'totalProtein': FieldValue.increment(scan.protein),
        'totalCarbs': FieldValue.increment(scan.carbs),
        'totalFats': FieldValue.increment(scan.fats),
      }, SetOptions(merge: true)));
    } catch (e) {
       FirebaseExceptionHandler.handleException(e, 'updateDailySummary');
    }
  }

  Future<void> updateWaterIntake(int amount) async {
    _requireAuth();
    final date = DateTime.now().toIso8601String().split('T')[0];
    try {
      await _withRetry(() => _db.collection('users').doc(_currentUid).collection('daily_summary').doc(date).set({
        'date': date,
        'totalWater': FieldValue.increment(amount),
      }, SetOptions(merge: true)));
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'updateWaterIntake');
    }
  }

  Stream<DailySummary?> streamDailySummary() {
    if (_currentUid == null) return const Stream.empty();
    final date = DateTime.now().toIso8601String().split('T')[0];
    
    // Streams handle their own native reconnect retries under the hood via Firestore
    return _db.collection('users').doc(_currentUid).collection('daily_summary').doc(date).snapshots()
      .map((snap) => snap.exists ? DailySummary.fromMap(snap.data()!) : null)
      .handleError((e) => FirebaseExceptionHandler.handleException(e, 'streamDailySummary'));
  }

  Future<DailySummary?> getDailySummaryOnce() async {
    if (_currentUid == null) return null;
    final date = DateTime.now().toIso8601String().split('T')[0];
    // Read optimized using one-off get()
    final snap = await _withRetry(() => _db.collection('users').doc(_currentUid).collection('daily_summary').doc(date).get());
    if (snap.exists) return DailySummary.fromMap(snap.data()!);
    return null;
  }

  // ==========================================
  // SCANS
  // ==========================================

  Future<ScanResult?> saveScanResult(ScanResult scan) async {
    _requireAuth();
    try {
      final scanData = scan.toMap();
      scanData['userId'] = _currentUid;
      scanData['timestamp'] = FieldValue.serverTimestamp();
      
      final docRef = await _withRetry(() => _db.collection('users').doc(_currentUid).collection('scans').add(scanData));
      await updateDailySummary(scan);
      
      return scan.copyWith(id: docRef.id, timestamp: DateTime.now().toIso8601String());
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'saveScanResult');
      return null;
    }
  }

  Future<void> updateScanResult(ScanResult updatedScan) async {
    _requireAuth();
    try {
      // 1. Fetch old scan to calculate nutritional diff
      final oldSnap = await _db.collection('users').doc(_currentUid).collection('scans').doc(updatedScan.id).get();
      if (!oldSnap.exists) return;
      
      final oldScan = ScanResult.fromMap({...oldSnap.data()!, 'id': oldSnap.id});
      
      // 2. Calculate Diffs
      final diffCal = updatedScan.calories - oldScan.calories;
      final diffPro = updatedScan.protein - oldScan.protein;
      final diffCarb = updatedScan.carbs - oldScan.carbs;
      final diffFat = updatedScan.fats - oldScan.fats;

      // 3. Update Scan Record
      final scanData = updatedScan.toMap();
      await _withRetry(() => _db.collection('users').doc(_currentUid).collection('scans').doc(updatedScan.id).update(scanData));
      
      // 4. Update Daily Summary with Diffs
      if (diffCal != 0 || diffPro != 0 || diffCarb != 0 || diffFat != 0) {
        final date = DateTime.now().toIso8601String().split('T')[0]; // Note: This assumes update happens on SAME day. Valid for most cases.
        await _withRetry(() => _db.collection('users').doc(_currentUid).collection('daily_summary').doc(date).set({
          'totalCalories': FieldValue.increment(diffCal),
          'totalProtein': FieldValue.increment(diffPro),
          'totalCarbs': FieldValue.increment(diffCarb),
          'totalFats': FieldValue.increment(diffFat),
        }, SetOptions(merge: true)));
      }
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'updateScanResult');
    }
  }

  Future<void> deleteScanResult(String id, ScanResult scan) async {
    _requireAuth();
    try {
      // 1. Delete image if exists
      if (scan.imageUrl != null && scan.imageUrl!.contains('firebasestorage')) {
        try {
          final ref = _storage.refFromURL(scan.imageUrl!);
          await ref.delete();
        } catch (e) {
          debugPrint('Failed to delete image from storage: $e');
        }
      }

      // 2. Delete scan document
      await _withRetry(() => _db.collection('users').doc(_currentUid).collection('scans').doc(id).delete());

      // 3. Update Daily Summary (decrement)
      if (scan.type == 'food') {
        final date = scan.timestamp.split('T')[0];
        await _withRetry(() => _db.collection('users').doc(_currentUid).collection('daily_summary').doc(date).set({
          'totalCalories': FieldValue.increment(-scan.calories),
          'totalProtein': FieldValue.increment(-scan.protein),
          'totalCarbs': FieldValue.increment(-scan.carbs),
          'totalFats': FieldValue.increment(-scan.fats),
        }, SetOptions(merge: true)));
      }
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'deleteScanResult');
    }
  }

  Stream<List<ScanResult>> streamScanHistory() {
    if (_currentUid == null) return const Stream.empty();
    
    // Explicit Pagination: Required orderBy and limit enforcement bounds loading.
    return _db.collection('users').doc(_currentUid).collection('scans')
      .orderBy('timestamp', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => ScanResult.fromMap({...doc.data(), 'id': doc.id})).toList())
      .handleError((e) => FirebaseExceptionHandler.handleException(e, 'streamScanHistory'));
  }

  Future<ScanResult?> getScanResult(String id) async {
    _requireAuth();
    try {
      final snap = await _withRetry(() => _db.collection('users').doc(_currentUid).collection('scans').doc(id).get());
      if (snap.exists) return ScanResult.fromMap({...snap.data()!, 'id': snap.id});
      return null;
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'getScanResult');
      return null;
    }
  }

  // ==========================================
  // CHAT
  // ==========================================

  Future<void> saveChatMessage(String role, String text) async {
    _requireAuth();
    try {
      await _withRetry(() => _db.collection('users').doc(_currentUid).collection('messages').add({
        'userId': _currentUid,
        'role': role,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      }));
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'saveChatMessage');
    }
  }

  Stream<List<ChatMessage>> streamChatHistory() {
    if (_currentUid == null) return const Stream.empty();
    
    // Explicit Pagination: Bounded limit
    return _db.collection('users').doc(_currentUid).collection('messages')
      .orderBy('timestamp', descending: false)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => ChatMessage.fromMap({...doc.data(), 'id': doc.id})).toList())
      .handleError((e) => FirebaseExceptionHandler.handleException(e, 'streamChatHistory'));
  }

  Future<void> clearChatHistory() async {
    _requireAuth();
    try {
      final snapshot = await _withRetry(() => _db.collection('users').doc(_currentUid).collection('messages').get());
      final batch = _db.batch();
      for (var doc in snapshot.docs) {
         batch.delete(doc.reference);
      }
      await _withRetry(() => batch.commit());
    } catch (e) {
      FirebaseExceptionHandler.handleException(e, 'clearChatHistory');
    }
  }
}
