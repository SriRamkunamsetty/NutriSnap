import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../types.dart';
import '../firebase_service.dart';
import '../services/storage_service.dart';
import '../lib/notifications.dart';

class UserProvider extends ChangeNotifier {
  User? _user;
  UserProfile? _profile;
  List<ScanResult> _scans = [];
  DailySummary? _dailySummary;
  bool _loading = true;

  User? get user => _user;
  UserProfile? get profile => _profile;
  List<ScanResult> get scans => _scans;
  DailySummary? get dailySummary => _dailySummary;
  bool get loading => _loading;

  StreamSubscription<User?>? _authSubscription;
  void Function()? _scansSubscription;
  void Function()? _summarySubscription;
  Timer? _reminderTimer;

  UserProvider() {
    _init();
  }

  void _init() {
    _authSubscription = firebaseService.auth.authStateChanges().listen((currentUser) async {
      _user = currentUser;
      
      if (currentUser != null) {
        // Load profile
        final p = await StorageService.getUserProfile(currentUser.uid);
        if (p != null) {
          _profile = p.copyWith(
            height: p.height ?? 175,
            weight: p.weight ?? 70,
            calorieLimit: p.calorieLimit ?? 2000,
            waterGoal: p.waterGoal ?? 2500,
            proteinGoal: p.proteinGoal ?? 150,
            carbsGoal: p.carbsGoal ?? 200,
            fatsGoal: p.fatsGoal ?? 67,
          );
        } else {
          // Create initial profile if doesn't exist
          final initialProfile = UserProfile(
            uid: currentUser.uid,
            email: currentUser.email ?? '',
            displayName: currentUser.displayName ?? 'User',
            photoURL: currentUser.photoURL ?? '',
            height: 175,
            weight: 70,
            bmi: 22.9,
            goal: Goal.maintain,
            calorieLimit: 2000,
            createdAt: DateTime.now(),
            lastLoginAt: DateTime.now(),
          );
          await StorageService.saveUserProfile(initialProfile);
          _profile = initialProfile;
        }

        // Listen to scans
        _scansSubscription?.call(); // Cancel previous if exists
        _scansSubscription = StorageService.getScanHistory((s) {
          _scans = s;
          notifyListeners();
        });
        
        // Listen to daily summary
        _summarySubscription?.call(); // Cancel previous if exists
        _summarySubscription = StorageService.getDailySummary((sum) {
          _dailySummary = sum;
          notifyListeners();
        });

        _setupReminders();
        _loading = false;
        notifyListeners();
      } else {
        _profile = null;
        _scans = [];
        _dailySummary = null;
        _loading = false;
        _cancelReminders();
        notifyListeners();
      }
    });
  }

  void _setupReminders() {
    _cancelReminders();
    
    if (_profile?.reminders == null || _profile!.reminders!.isEmpty) return;

    void checkReminders() {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      for (var reminder in _profile!.reminders!) {
        if (reminder.enabled && reminder.time == currentTime) {
          Notifications.sendLocalNotification(
            reminder.type == ReminderType.meal ? '🍽️ Time for a meal!' : '💧 Time to hydrate!',
            body: 'Don\'t forget to log your ${reminder.type.name} in NutriSnap.',
          );
        }
      }
    }

    // Check once immediately then every minute
    checkReminders();
    _reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) => checkReminders());
  }

  void _cancelReminders() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
  }

  Future<UserProfile?> refreshProfile() async {
    if (_user != null) {
      final p = await StorageService.getUserProfile(_user!.uid);
      _profile = p;
      notifyListeners();
      return p;
    }
    return null;
  }

  Future<void> updateProfile(UserProfile updates) async {
    if (_profile != null) {
      // Update state immediately for instant UI feedback
      _profile = updates;
      notifyListeners();
      
      // Save to Firestore in the background
      try {
        await StorageService.saveUserProfile(updates);
        _setupReminders(); // Re-setup reminders in case they changed
      } catch (error) {
        print("Failed to save profile updates: $error");
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _scansSubscription?.call();
    _summarySubscription?.call();
    _cancelReminders();
    super.dispose();
  }
}
