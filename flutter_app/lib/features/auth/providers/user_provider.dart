import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/data_purge.dart';
import 'user_state.dart';

// Stream of current local user
final authStateChangesProvider = StreamProvider<LocalUser?>((ref) {
  final userNotifier = ref.watch(userNotifierProvider);
  return Stream.value(userNotifier.authUser);
});

// Primary UserNotifier managing on-device user profile & state
final userNotifierProvider = StateNotifierProvider<UserNotifier, UserState>((ref) {
  return UserNotifier(ref);
});

class UserNotifier extends StateNotifier<UserState> {
  final Ref _ref;

  UserNotifier(this._ref) : super(const UserState(isLoading: true)) {
    _init();
  }

  Future<void> _init() async {
    // Initialize default local private user
    const defaultUser = LocalUser(
      uid: 'local_user_default',
      email: 'private.user@on-device.local',
      displayName: 'NutriSnap User',
      photoURL: '',
      emailVerified: true,
    );

    final storage = _ref.read(storageServiceProvider);
    storage.setCurrentUid(defaultUser.uid);

    // Run 30-day auto-purge on startup: archives and dispatches data to user's email ID before cleaning
    try {
      await DataPurgeManager.runStartupPurge(
        userEmail: defaultUser.email,
        userId: defaultUser.uid,
      );
    } catch (e) {
      // Non-blocking background error handling
    }

    var existingProfile = await storage.getUserProfile(defaultUser.uid);
    if (existingProfile == null) {
      existingProfile = UserProfile(
        uid: defaultUser.uid,
        email: defaultUser.email,
        displayName: defaultUser.displayName,
        photoURL: defaultUser.photoURL ?? '',
        height: 175,
        weight: 70,
        bmi: 22.9,
        goal: Goal.maintain,
        calorieLimit: 2000,
        waterGoal: 2500,
        proteinGoal: 150,
        carbsGoal: 200,
        fatsGoal: 67,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      await storage.saveUserProfile(existingProfile);
    }

    state = UserState(
      authUser: defaultUser,
      profile: existingProfile,
      isLoading: false,
    );
  }

  Future<UserProfile?> refreshProfile() async {
    if (state.authUser != null) {
      final storage = _ref.read(storageServiceProvider);
      final p = await storage.getUserProfile(state.authUser!.uid);
      if (p != null) {
        state = state.copyWith(profile: p);
      }
    }
    return state.profile;
  }

  Future<void> login(LocalUser user) async {
    final storage = _ref.read(storageServiceProvider);
    storage.setCurrentUid(user.uid);

    // Auto-purge items older than 30 days, emailing archive to user's login email ID before cleaning
    try {
      await DataPurgeManager.runStartupPurge(
        userEmail: user.email,
        userId: user.uid,
      );
    } catch (e) {
      // Non-blocking background error handling
    }

    var p = await storage.getUserProfile(user.uid);
    if (p == null) {
      p = UserProfile(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        photoURL: user.photoURL ?? '',
        height: 175,
        weight: 70,
        bmi: 22.9,
        goal: Goal.maintain,
        calorieLimit: 2000,
        waterGoal: 2500,
        proteinGoal: 150,
        carbsGoal: 200,
        fatsGoal: 67,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      await storage.saveUserProfile(p);
    }
    state = state.copyWith(authUser: user, profile: p, isLoading: false);
  }

  Future<void> signOut() async {
    const freshUser = LocalUser(
      uid: 'local_user_guest',
      email: 'guest@on-device.local',
      displayName: 'Guest',
      photoURL: '',
    );
    state = state.copyWith(
      authUser: freshUser,
      profile: null,
      isLoading: false,
    );
  }

  Future<void> sendEmailVerification() async {
    // Local on-device accounts are verified by default
    if (state.authUser != null) {
      final updatedUser = LocalUser(
        uid: state.authUser!.uid,
        email: state.authUser!.email,
        displayName: state.authUser!.displayName,
        photoURL: state.authUser!.photoURL,
        emailVerified: true,
      );
      state = state.copyWith(authUser: updatedUser);
    }
  }

  Future<void> updateProfile(UserProfile updatedProfile) async {
    state = state.copyWith(profile: updatedProfile, clearError: true);
    final storage = _ref.read(storageServiceProvider);
    await storage.saveUserProfile(updatedProfile);
  }
}
