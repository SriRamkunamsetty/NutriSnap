import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/chat_message.dart';
import '../models/daily_summary.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // User Profile
  Stream<UserProfile?> streamUserProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserProfile.fromMap(snap.data()!);
    });
  }

  Future<void> updateUserProfile(UserProfile profile) async {
    await _db.collection('users').doc(profile.uid).set(profile.toMap(), SetOptions(merge: true));
  }

  // Scans
  Stream<List<ScanResult>> streamScans(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => ScanResult.fromMap(doc.data(), doc.id)).toList());
  }

  Future<void> addScan(ScanResult scan) async {
    final docRef = _db.collection('users').doc(scan.userId).collection('scans').doc();
    await docRef.set(scan.toMap());
    await _updateDailySummary(scan.userId, scan);
  }

  Future<String> uploadImage(File file, String path) async {
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  // Daily Summary
  Stream<DailySummary?> streamDailySummary(String uid, String date) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('daily_summary')
        .doc(date)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return DailySummary.fromMap(snap.data()!);
    });
  }

  Future<void> _updateDailySummary(String uid, ScanResult scan) async {
    final date = DateFormat('yyyy-MM-dd').format(scan.timestamp);
    final docRef = _db.collection('users').doc(uid).collection('daily_summary').doc(date);

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        transaction.set(docRef, {
          'date': date,
          'totalCalories': scan.calories,
          'totalProtein': scan.protein,
          'totalCarbs': scan.carbs,
          'totalFats': scan.fats,
          'totalWater': 0,
        });
      } else {
        transaction.update(docRef, {
          'totalCalories': FieldValue.increment(scan.calories),
          'totalProtein': FieldValue.increment(scan.protein),
          'totalCarbs': FieldValue.increment(scan.carbs),
          'totalFats': FieldValue.increment(scan.fats),
        });
      }
    });
  }

  Future<void> updateWaterIntake(String uid, int amount) async {
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docRef = _db.collection('users').doc(uid).collection('daily_summary').doc(date);

    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'date': date,
        'totalCalories': 0,
        'totalProtein': 0,
        'totalCarbs': 0,
        'totalFats': 0,
        'totalWater': amount,
      });
    } else {
      await docRef.update({'totalWater': FieldValue.increment(amount)});
    }
  }

  // Chat
  Stream<List<ChatMessage>> streamMessages(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => ChatMessage.fromMap(doc.data())).toList());
  }

  Future<void> addMessage(ChatMessage message) async {
    await _db.collection('users').doc(message.userId).collection('messages').add(message.toMap());
  }
}
