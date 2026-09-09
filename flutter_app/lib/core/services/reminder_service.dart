import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../services/storage_service.dart';
import '../utils/ui_feedback.dart';
import '../../features/auth/providers/user_provider.dart';

/// Default meal reminders for Breakfast, Lunch, and Dinner
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

class ReminderService {
  final Ref _ref;
  Timer? _pollingTimer;
  final Set<String> _notifiedToday = {};

  ReminderService(this._ref) {
    _startReminderScheduler();
  }

  void _startReminderScheduler() {
    _pollingTimer?.cancel();
    // Check every 60 seconds if a reminder is due
    _pollingTimer = Timer.periodic(const Duration(minutes: 1), (_) => checkDueReminders());
  }

  void dispose() {
    _pollingTimer?.cancel();
  }

  List<Reminder> getCurrentReminders() {
    final profile = _ref.read(userNotifierProvider).profile;
    if (profile?.reminders == null || profile!.reminders!.isEmpty) {
      return defaultMealReminders;
    }

    // Ensure all 3 meal types exist
    final existing = profile.reminders!;
    final List<Reminder> merged = [];

    for (final def in defaultMealReminders) {
      final match = existing.where((r) => r.id == def.id || r.type == def.type).firstOrNull;
      if (match != null) {
        merged.add(match.copyWith(
          label: match.label ?? def.label,
          message: match.message ?? def.message,
        ));
      } else {
        merged.add(def);
      }
    }

    return merged;
  }

  Future<void> toggleReminder(String id, bool enabled) async {
    final current = getCurrentReminders();
    final updated = current.map((r) {
      if (r.id == id) {
        return r.copyWith(enabled: enabled);
      }
      return r;
    }).toList();

    await _saveRemindersToProfile(updated);
  }

  Future<void> updateReminderTime(String id, String time) async {
    final current = getCurrentReminders();
    final updated = current.map((r) {
      if (r.id == id) {
        return r.copyWith(time: time);
      }
      return r;
    }).toList();

    await _saveRemindersToProfile(updated);
  }

  Future<void> _saveRemindersToProfile(List<Reminder> reminders) async {
    final userState = _ref.read(userNotifierProvider);
    final profile = userState.profile;
    if (profile == null) return;

    final updatedProfile = profile.copyWith(reminders: reminders);
    final storage = _ref.read(storageServiceProvider);

    try {
      await storage.saveUserProfile(updatedProfile);
      await _ref.read(userNotifierProvider.notifier).refreshProfile();
    } catch (e) {
      debugPrint('Failed to save reminders: $e');
    }
  }

  void checkDueReminders({BuildContext? context}) {
    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final todayKey = '${now.year}-${now.month}-${now.day}';

    final reminders = getCurrentReminders();
    for (final reminder in reminders) {
      if (!reminder.enabled) continue;

      final key = '$todayKey-${reminder.id}-$nowTime';
      if (reminder.time == nowTime && !_notifiedToday.contains(key)) {
        _notifiedToday.add(key);
        _triggerNotification(reminder, context: context);
      }
    }
  }

  void _triggerNotification(Reminder reminder, {BuildContext? context}) {
    UiFeedback.light();

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF16A34A),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reminder.label ?? "Meal"} Reminder (${reminder.time})',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                    ),
                    Text(
                      reminder.message ?? 'Don\'t forget to log your meal in NutriSnap AI!',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void sendTestNotification(BuildContext context, Reminder reminder) {
    UiFeedback.medium();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF10B981),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            const Icon(Icons.alarm_on, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${reminder.label ?? "Meal"} Reminder Scheduled (${reminder.time})',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  ),
                  Text(
                    reminder.message ?? 'Recurring daily reminder is active.',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

final mealRemindersProvider = Provider<List<Reminder>>((ref) {
  final userState = ref.watch(userNotifierProvider);
  final reminders = userState.profile?.reminders;
  if (reminders == null || reminders.isEmpty) {
    return defaultMealReminders;
  }

  // Ensure default breakfast, lunch, dinner are covered
  final List<Reminder> merged = [];
  for (final def in defaultMealReminders) {
    final match = reminders.where((r) => r.id == def.id || r.type == def.type).firstOrNull;
    if (match != null) {
      merged.add(match.copyWith(
        label: match.label ?? def.label,
        message: match.message ?? def.message,
      ));
    } else {
      merged.add(def);
    }
  }
  return merged;
});
