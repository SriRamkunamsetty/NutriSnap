import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/providers/app_providers.dart';
import 'user_state.dart';

/// Primary notifier for the on-device profile, backed by SQLite.
final userNotifierProvider = StateNotifierProvider<UserNotifier, UserState>(
  (ref) => UserNotifier(ref),
);

class UserNotifier extends StateNotifier<UserState> {
  UserNotifier(this._ref) : super(const UserState(isLoading: true)) {
    _init();
  }

  final Ref _ref;

  Future<void> _init() async {
    try {
      final repo = _ref.read(profileRepositoryProvider);
      var profile = await repo.get();
      // A brand-new install has no profile; onboarding creates it.
      profile ??= UserProfile(
        uid: AppConfig.localUserId,
        email: '',
        displayName: '',
        hasCompletedOnboarding: false,
        createdAt: DateTime.now(),
      );
      if (mounted) state = UserState(profile: profile);
    } catch (e, s) {
      debugPrint('[UserNotifier] failed to load profile: $e\n$s');
      if (mounted) {
        state = const UserState(
          errorMessage: 'Could not open your data. Please restart the app.',
        );
      }
    }
  }

  /// Persists and publishes [updated].
  Future<void> updateProfile(UserProfile updated) async {
    final previous = state.profile;
    state = state.copyWith(profile: updated, clearError: true);
    try {
      await _ref.read(profileRepositoryProvider).save(updated);
    } catch (e) {
      // Roll back so the UI never shows something that was not saved.
      state = state.copyWith(profile: previous);
      rethrow;
    }
  }

  Future<UserProfile?> refreshProfile() async {
    final p = await _ref.read(profileRepositoryProvider).get();
    if (p != null && mounted) state = state.copyWith(profile: p);
    return state.profile;
  }

  /// Erases everything (profile, meals, chat, photos, settings) and returns
  /// the app to a first-run state.
  Future<void> eraseEverything() async {
    await _ref.read(scanRepositoryProvider).deleteEverything();
    await _ref.read(summaryRepositoryProvider).deleteEverything();
    await _ref.read(chatRepositoryProvider).clear();
    await _ref.read(activityRepositoryProvider).deleteEverything();
    await _ref.read(messRepositoryProvider).deleteEverything();
    await _ref.read(foodRepositoryProvider).resetUserData();
    await _ref.read(profileRepositoryProvider).deleteAll();
    await _ref.read(settingsRepositoryProvider).clear();
    await _ref.read(imageStoreProvider).deleteAll();
    await _ref.read(notificationServiceProvider).cancelAll();
    if (mounted) {
      state = UserState(
        profile: UserProfile(
          uid: AppConfig.localUserId,
          email: '',
          displayName: '',
          hasCompletedOnboarding: false,
          createdAt: DateTime.now(),
        ),
      );
    }
  }
}
