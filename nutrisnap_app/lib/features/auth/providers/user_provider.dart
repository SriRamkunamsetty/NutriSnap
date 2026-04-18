import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/utils/firebase_exception_handler.dart';
import '../../../core/enums/app_enums.dart';
import 'user_state.dart';

// Provides the auth stream status natively from Firebase
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseServiceProvider).auth.authStateChanges();
});

// Primary UserNotifier equivalent to the React UserProvider context
final userNotifierProvider = StateNotifierProvider<UserNotifier, UserState>((ref) {
  return UserNotifier(ref);
});

class UserNotifier extends StateNotifier<UserState> {
  final Ref _ref;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  
  UserNotifier(this._ref) : super(const UserState(isLoading: true)) {
    _init();
  }

  void _init() {
    // 1. Subscription Lifecycle Handling
    _ref.onDispose(() {
      _authSubscription?.cancel();
      _profileSubscription?.cancel();
    });

    _authSubscription = _ref.watch(firebaseServiceProvider).auth.authStateChanges().listen(
      (User? user) {
        if (user != null) {
          state = state.copyWith(authUser: user, isLoading: true);
          _listenOrCreateProfile(user);
        } else {
          _profileSubscription?.cancel();
          state = state.copyWith(
            clearAuthUser: true,
            clearProfile: true,
            isLoading: false,
          );
        }
      },
      onError: (e) {
        state = state.copyWith(
          isLoading: false, 
          errorMessage: FirebaseExceptionHandler.handleException(e, 'AuthStream')
        );
      }
    );
  }

  // 4. Real-Time Profile Sync
  Future<void> _listenOrCreateProfile(User currentUser) async {
    final db = _ref.read(firebaseServiceProvider).db;
    final docRef = db.collection('users').doc(currentUser.uid);
    
    _profileSubscription?.cancel();
    _profileSubscription = docRef.snapshots().listen(
      (docSnap) async {
        if (docSnap.exists) {
          final rawMap = docSnap.data()!;
          final loadedProfile = UserProfile.fromMap(rawMap);
          
          final patchedProfile = loadedProfile.copyWith(
            height: loadedProfile.height ?? 175,
            weight: loadedProfile.weight ?? 70,
            calorieLimit: loadedProfile.calorieLimit ?? 2000,
            waterGoal: loadedProfile.waterGoal ?? 2500,
            proteinGoal: loadedProfile.proteinGoal ?? 150,
            carbsGoal: loadedProfile.carbsGoal ?? 200,
            fatsGoal: loadedProfile.fatsGoal ?? 67,
          );

          state = state.copyWith(profile: patchedProfile, isLoading: false, clearError: true);
        } else {
          try {
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
            await _saveProfileRaw(initialProfile);
          } catch (e) {
            state = state.copyWith(
              isLoading: false,
              errorMessage: FirebaseExceptionHandler.handleException(e, 'CreateProfile')
            );
          }
        }
      },
      onError: (e) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: FirebaseExceptionHandler.handleException(e, 'ProfileSync')
        );
      }
    );
  }

  // Explicit refresh exposed to UI (real-time sync + manual fetch and auth reload)
  Future<UserProfile?> refreshProfile() async {
    final user = _ref.read(firebaseServiceProvider).auth.currentUser;
    if (user != null) {
      await user.reload();
      final freshUser = _ref.read(firebaseServiceProvider).auth.currentUser;
      state = state.copyWith(authUser: freshUser);
      
      final db = _ref.read(firebaseServiceProvider).db;
      final snap = await db.collection('users').doc(user.uid).get();
      if (snap.exists) {
        state = state.copyWith(profile: UserProfile.fromMap(snap.data()!));
      }
    }
    return state.profile;
  }

  Future<void> signOut() async {
    await _ref.read(firebaseServiceProvider).auth.signOut();
  }

  Future<void> sendEmailVerification() async {
    final user = _ref.read(firebaseServiceProvider).auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> updateProfile(UserProfile updatedProfile) async {
    // 5. Safeguard Optimistic Updates (Stored securely before mutation)
    final cachedPreviousState = state;
    state = state.copyWith(profile: updatedProfile, clearError: true);

    try {
      await _saveProfileRaw(updatedProfile);
    } catch (e) {
      // 5. Rollback on failure utilizing the cached previous state directly
      state = cachedPreviousState.copyWith(
        errorMessage: FirebaseExceptionHandler.handleException(e, 'UpdateProfile')
      );
    }
  }

  Future<void> _saveProfileRaw(UserProfile profile) async {
    final db = _ref.read(firebaseServiceProvider).db;
    final map = profile.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await db.collection('users').doc(profile.uid).set(map, SetOptions(merge: true));
  }
}
