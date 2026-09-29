import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/user_provider.dart';
import '../models/reminder.dart';
import '../providers/app_providers.dart';
import '../utils/ui_feedback.dart';

/// Default meal reminders for Breakfast, Lunch, and Dinner.
List<Reminder> get defaultMealReminders => const [
      Reminder(
        id: 'breakfast',
        type: 'breakfast',
        label: 'Breakfast',
        time: '08:30',
        enabled: true,
        message: 'Time to fuel up! Log your breakfast to kickstart your metabolism.',
      ),
      Reminder(
        id: 'lunch',
        type: 'lunch',
        label: 'Lunch',
        time: '13:00',
        enabled: true,
        message: 'Midday nutrition check! Log your lunch to keep your energy high.',
      ),
      Reminder(
        id: 'dinner',
        type: 'dinner',
        label: 'Dinner',
        time: '19:30',
        enabled: true,
        message: 'Evening wrap-up! Log your dinner to complete your daily macro goals.',
      ),
    ];

/// Merges the user's saved reminders over the three built-in meals.
List<Reminder> mergeWithDefaults(List<Reminder>? saved) {
  if (saved == null || saved.isEmpty) return defaultMealReminders;
  return [
    for (final def in defaultMealReminders)
      () {
        final match =
            saved.where((r) => r.id == def.id || r.type == def.type).firstOrNull;
        return match == null
            ? def
            : match.copyWith(
                label: match.label ?? def.label,
                message: match.message ?? def.message,
              );
      }(),
  ];
}

/// Reminder settings + OS scheduling. State lives in the profile; the actual
/// alarms are scheduled with the OS so they fire while the app is closed.
class ReminderService {
  ReminderService(this._ref);

  final Ref _ref;

  List<Reminder> getCurrentReminders() =>
      mergeWithDefaults(_ref.read(userNotifierProvider).profile?.reminders);

  Future<void> toggleReminder(String id, bool enabled) async {
    if (enabled) {
      // Ask for permission at the moment the user opts in.
      final granted = await _ref.read(notificationServiceProvider).requestPermission();
      if (!granted) UIFeedback.light();
    }
    await _save([
      for (final r in getCurrentReminders())
        r.id == id ? r.copyWith(enabled: enabled) : r,
    ]);
  }

  Future<void> updateReminderTime(String id, String time) => _save([
        for (final r in getCurrentReminders())
          r.id == id ? r.copyWith(time: time) : r,
      ]);

  /// Re-applies the saved schedule to the OS (call at app start).
  Future<void> syncSchedule() =>
      _ref.read(notificationServiceProvider).syncReminders(getCurrentReminders());

  Future<void> _save(List<Reminder> reminders) async {
    final profile = _ref.read(userNotifierProvider).profile;
    if (profile == null) return;
    await _ref
        .read(userNotifierProvider.notifier)
        .updateProfile(profile.copyWith(reminders: reminders));
    await _ref.read(notificationServiceProvider).syncReminders(reminders);
  }

  /// Fires a real notification now so the user can verify permissions work.
  Future<void> sendTestNotification(BuildContext context, Reminder reminder) async {
    UIFeedback.medium();
    final svc = _ref.read(notificationServiceProvider);
    final granted = await svc.requestPermission();
    if (!context.mounted) return;
    if (granted) {
      await svc.showNow(reminder);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Notifications are turned off. Enable them in system settings.'),
      ));
    }
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) => ReminderService(ref));

final mealRemindersProvider = Provider<List<Reminder>>((ref) =>
    mergeWithDefaults(ref.watch(userNotifierProvider).profile?.reminders));
