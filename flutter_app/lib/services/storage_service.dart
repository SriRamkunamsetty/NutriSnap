import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../types.dart';
import 'firebase_service.dart';

enum OperationType { create, update, delete, list, get, write }

void handleFirestoreError(dynamic error, OperationType operationType, String? path) {
  final user = firebaseService.auth.currentUser;
  final errInfo = {
    'error': error.toString(),
    'authInfo': {
      'userId': user?.uid,
      'email': user?.email,
      'emailVerified': user?.emailVerified,
      'isAnonymous': user?.isAnonymous,
      'tenantId': user?.tenantId,
      'providerInfo': user?.providerData.map((p) => {
        'providerId': p.providerId,
        'displayName': p.displayName,
        'email': p.email,
        'photoUrl': p.photoURL,
      }).toList() ?? [],
    },
    'operationType': operationType.name,
    'path': path,
  };
  print('Firestore Error: $errInfo');
  throw Exception(errInfo.toString());
}

class StorageService {
  static final db = firebaseService.db;
  static final auth = firebaseService.auth;
  static final storage = firebaseService.storage;

  static Future<String> uploadProfileImage(File file) async {
    final user = auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final storageRef = storage.ref('users/${user.uid}/profile_${DateTime.now().millisecondsSinceEpoch}');
    await storageRef.putFile(file);
    final downloadURL = await storageRef.getDownloadURL();

    await saveUserProfile(UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      photoURL: downloadURL,
      createdAt: DateTime.now(),
    ));

    return downloadURL;
  }

  static Future<String> uploadAIAvatar(File file) async {
    final user = auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final storageRef = storage.ref('users/${user.uid}/ai_avatar_${DateTime.now().millisecondsSinceEpoch}');
    await storageRef.putFile(file);
    final downloadURL = await storageRef.getDownloadURL();

    await saveUserProfile(UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      aiAvatarURL: downloadURL,
      createdAt: DateTime.now(),
    ));

    return downloadURL;
  }

  static Future<String> uploadBodyImage(File file) async {
    final user = auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final storageRef = storage.ref('users/${user.uid}/body_scans/scan_${DateTime.now().millisecondsSinceEpoch}');
    await storageRef.putFile(file);
    final downloadURL = await storageRef.getDownloadURL();

    await saveUserProfile(UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      bodyScanURL: downloadURL,
      createdAt: DateTime.now(),
    ));

    return downloadURL;
  }

  static Future<String> uploadScanImage(File file) async {
    final user = auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final storageRef = storage.ref('users/${user.uid}/scans/scan_${DateTime.now().millisecondsSinceEpoch}');
    await storageRef.putFile(file);
    return await storageRef.getDownloadURL();
  }

  static Future<void> saveUserProfile(UserProfile profile) async {
    final user = auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final uid = user.uid;
    final path = 'users/$uid';
    try {
      final userDoc = db.collection('users').doc(uid);
      final data = profile.toMap();
      data['uid'] = uid;
      data['email'] = user.email;
      data['updatedAt'] = FieldValue.serverTimestamp();
      
      await userDoc.set(data, SetOptions(merge: true));
    } catch (error) {
      handleFirestoreError(error, OperationType.write, path);
    }
  }

  static Future<UserProfile?> getUserProfile(String uid) async {
    final path = 'users/$uid';
    try {
      final userDoc = db.collection('users').doc(uid);
      final snap = await userDoc.get();
      if (snap.exists && snap.data() != null) {
        return UserProfile.fromMap(snap.data()!);
      }
      return null;
    } catch (error) {
      handleFirestoreError(error, OperationType.get, path);
      return null;
    }
  }

  static Future<void> updateDailySummary(ScanResult scan) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final date = DateTime.now().toIso8601String().split('T')[0];
    final path = 'users/$uid/daily_summary/$date';

    try {
      final summaryDoc = db.collection('users').doc(uid).collection('daily_summary').doc(date);
      await summaryDoc.set({
        'date': date,
        'totalCalories': FieldValue.increment(scan.calories),
        'totalProtein': FieldValue.increment(scan.protein),
        'totalCarbs': FieldValue.increment(scan.carbs),
        'totalFats': FieldValue.increment(scan.fats),
      }, SetOptions(merge: true));
    } catch (error) {
      handleFirestoreError(error, OperationType.write, path);
    }
  }

  static Future<void> updateWaterIntake(int amount) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final date = DateTime.now().toIso8601String().split('T')[0];
    final path = 'users/$uid/daily_summary/$date';

    try {
      final summaryDoc = db.collection('users').doc(uid).collection('daily_summary').doc(date);
      await summaryDoc.set({
        'date': date,
        'totalWater': FieldValue.increment(amount),
      }, SetOptions(merge: true));
    } catch (error) {
      handleFirestoreError(error, OperationType.write, path);
    }
  }

  static void Function() getDailySummary(Function(DailySummary?) callback) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return () {};

    final date = DateTime.now().toIso8601String().split('T')[0];
    final path = 'users/$uid/daily_summary/$date';
    final summaryDoc = db.collection('users').doc(uid).collection('daily_summary').doc(date);

    final subscription = summaryDoc.snapshots().listen(
      (snap) {
        if (snap.exists && snap.data() != null) {
          callback(DailySummary.fromMap(snap.data()!));
        } else {
          callback(null);
        }
      },
      onError: (error) => handleFirestoreError(error, OperationType.get, path),
    );

    return subscription.cancel;
  }

  static Future<DailySummary?> getDailySummaryOnce() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return null;

    final date = DateTime.now().toIso8601String().split('T')[0];
    final path = 'users/$uid/daily_summary/$date';
    final summaryDoc = db.collection('users').doc(uid).collection('daily_summary').doc(date);

    try {
      final snap = await summaryDoc.get();
      if (snap.exists && snap.data() != null) {
        return DailySummary.fromMap(snap.data()!);
      }
      return null;
    } catch (error) {
      handleFirestoreError(error, OperationType.get, path);
      return null;
    }
  }

  static Future<ScanResult?> saveScanResult(ScanResult scan) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    final path = 'users/$uid/scans';
    try {
      final scanData = scan.toMap();
      scanData['userId'] = uid;
      scanData['timestamp'] = FieldValue.serverTimestamp();
      
      final docRef = await db.collection('users').doc(uid).collection('scans').add(scanData);
      
      await updateDailySummary(scan);
      
      return ScanResult.fromMap(scanData, docRef.id);
    } catch (error) {
      handleFirestoreError(error, OperationType.create, path);
      return null;
    }
  }

  static void Function() getScanHistory(Function(List<ScanResult>) callback) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return () {};

    final path = 'users/$uid/scans';
    final q = db.collection('users').doc(uid).collection('scans')
        .orderBy('timestamp', descending: true)
        .limit(50);

    final subscription = q.snapshots().listen(
      (snapshot) {
        final scans = snapshot.docs.map((doc) => ScanResult.fromMap(doc.data(), doc.id)).toList();
        callback(scans);
      },
      onError: (error) => handleFirestoreError(error, OperationType.list, path),
    );

    return subscription.cancel;
  }

  static Future<void> saveChatMessage(ChatRole role, String text) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    final path = 'users/$uid/messages';
    try {
      await db.collection('users').doc(uid).collection('messages').add({
        'userId': uid,
        'role': role.name,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      handleFirestoreError(error, OperationType.create, path);
    }
  }

  static void Function() getChatHistory(Function(List<ChatMessage>) callback) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return () {};

    final path = 'users/$uid/messages';
    final q = db.collection('users').doc(uid).collection('messages')
        .orderBy('timestamp', descending: false)
        .limit(100);

    final subscription = q.snapshots().listen(
      (snapshot) {
        final messages = snapshot.docs.map((doc) => ChatMessage.fromMap(doc.data(), doc.id)).toList();
        callback(messages);
      },
      onError: (error) => handleFirestoreError(error, OperationType.list, path),
    );

    return subscription.cancel;
  }

  static Future<void> clearChatHistory() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    final path = 'users/$uid/messages';
    try {
      final q = db.collection('users').doc(uid).collection('messages');
      final snapshot = await q.get();
      
      final batch = db.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (error) {
      handleFirestoreError(error, OperationType.delete, path);
    }
  }
}
