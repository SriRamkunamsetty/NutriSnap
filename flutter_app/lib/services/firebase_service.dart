import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/chat_message.dart';
import '../models/daily_summary.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

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

  Future<void> deleteScan(String uid, String scanId) async {
    final docRef = _db.collection('users').doc(uid).collection('scans').doc(scanId);
    final snap = await docRef.get();
    if (snap.exists) {
      final scan = ScanResult.fromMap(snap.data()!, scanId);
      await docRef.delete();
      await _updateDailySummary(uid, scan, isDelete: true);
    }
  }

  Future<String> uploadImage(File file, String path) async {
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<String> uploadBodyImage(File file) async {
    final path = 'body_scans/${currentUserId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await uploadImage(file, path);
  }

  // Auth
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpWithEmail(String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    if (cred.user != null) {
      await updateUserProfile(UserProfile(
        uid: cred.user!.uid,
        email: email,
        displayName: name,
        height: 0,
        weight: 0,
        bmi: 0,
        goal: 'maintain',
        calorieLimit: 2000,
        waterGoal: 2500,
        proteinGoal: 150,
        carbsGoal: 250,
        fatsGoal: 70,
      ));
    }
    return cred;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<UserCredential> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google Sign-In cancelled');

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    if (cred.user != null) {
      await _ensureUserProfile(cred.user!);
    }
    return cred;
  }

  Future<UserCredential> signInWithGithub() async {
    final GithubAuthProvider githubProvider = GithubAuthProvider();
    final cred = await _auth.signInWithProvider(githubProvider);
    if (cred.user != null) {
      await _ensureUserProfile(cred.user!);
    }
    return cred;
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> sendEmailVerification() async {
    if (_auth.currentUser != null) {
      await _auth.currentUser!.sendEmailVerification();
    }
  }

  Future<void> _ensureUserProfile(User user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      await updateUserProfile(UserProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'User',
        photoURL: user.photoURL,
        height: 0,
        weight: 0,
        bmi: 0,
        goal: 'maintain',
        calorieLimit: 2000,
        waterGoal: 2500,
        proteinGoal: 150,
        carbsGoal: 250,
        fatsGoal: 70,
      ));
    }
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

  Future<void> _updateDailySummary(String uid, ScanResult scan, {bool isDelete = false}) async {
    final date = DateFormat('yyyy-MM-dd').format(scan.timestamp);
    final docRef = _db.collection('users').doc(uid).collection('daily_summary').doc(date);

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      final multiplier = isDelete ? -1 : 1;

      if (!snap.exists) {
        if (!isDelete) {
          transaction.set(docRef, {
            'date': date,
            'totalCalories': scan.calories,
            'totalProtein': scan.protein,
            'totalCarbs': scan.carbs,
            'totalFats': scan.fats,
            'totalWater': 0,
          });
        }
      } else {
        transaction.update(docRef, {
          'totalCalories': FieldValue.increment(scan.calories * multiplier),
          'totalProtein': FieldValue.increment(scan.protein * multiplier),
          'totalCarbs': FieldValue.increment(scan.carbs * multiplier),
          'totalFats': FieldValue.increment(scan.fats * multiplier),
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
        .orderBy('timestamp', descending: false)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => ChatMessage.fromMap(doc.id, doc.data())).toList());
  }

  Future<void> addChatMessage(ChatMessage message) async {
    await _db.collection('users').doc(message.userId).collection('messages').add(message.toMap());
  }
}
