import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// Real OS-scheduled local notifications. They fire even when the app is
/// closed, and never leave the device.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channelId = 'meal_reminders';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Meal reminders',
      channelDescription: 'Daily reminders to log your meals',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> initialize() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      debugPrint('[Notifications] timezone setup failed, using UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested explicitly, at a moment the user understands.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks the OS for permission. Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  /// Replaces every scheduled reminder with [reminders] (enabled ones only).
  /// Idempotent: call it whenever reminders change and once at start-up.
  Future<void> syncReminders(List<Reminder> reminders) async {
    await initialize();
    await _plugin.cancelAllPendingNotifications();
    for (final r in reminders.where((r) => r.enabled)) {
      final parts = r.time.split(':');
      final hour = int.tryParse(parts.first);
      final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (hour == null || minute == null) continue;

      try {
        await _plugin.zonedSchedule(
          id: _idFor(r),
          title: '${r.label ?? 'Meal'} time',
          body: r.message ?? "Don't forget to log your meal in NutriSnap.",
          scheduledDate: _nextInstance(hour, minute),
          notificationDetails: _details,
          // Inexact is enough for a meal nudge and needs no special permission.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        debugPrint('[Notifications] could not schedule ${r.id}: $e');
      }
    }
  }

  Future<void> showNow(Reminder r) async {
    await initialize();
    await _plugin.show(
      id: _idFor(r) + 1000,
      title: '${r.label ?? 'Meal'} reminder',
      body: r.message ?? "Don't forget to log your meal in NutriSnap.",
      notificationDetails: _details,
    );
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAllPendingNotifications();
  }

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  /// Stable, positive 31-bit id derived from the reminder id.
  int _idFor(Reminder r) {
    var h = 0;
    for (final c in r.id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % 100000;
  }
}
