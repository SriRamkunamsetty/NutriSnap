import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/activity.dart';

/// App-level preferences persisted in the `kv` table.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _retentionKey = 'retention_days';
  static const _lastRetentionRunKey = 'last_retention_run';
  static const _foreverToken = 'forever';

  /// Days of history to keep; `null` keeps everything.
  Future<int?> retentionDays() async {
    final v = await _db.getKv(_retentionKey);
    if (v == null) return AppConfig.defaultRetentionDays;
    if (v == _foreverToken) return null;
    return int.tryParse(v) ?? AppConfig.defaultRetentionDays;
  }

  Future<void> setRetentionDays(int? days) =>
      _db.setKv(_retentionKey, days == null ? _foreverToken : '$days');

  Future<DateTime?> lastRetentionRun() async {
    final v = await _db.getKv(_lastRetentionRunKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> markRetentionRun(DateTime at) =>
      _db.setKv(_lastRetentionRunKey, at.toIso8601String());

  Future<void> clear() async {
    await _db.db.delete(Tables.kv);
    _db.notify(Tables.kv);
  }

  // ---------------------------------------------------------------------------
  // Activity goals
  // ---------------------------------------------------------------------------

  static const _gSteps = 'goal_daily_steps';
  static const _gMinutes = 'goal_daily_active_minutes';
  static const _gWeekMinutes = 'goal_weekly_active_minutes';
  static const _gWorkouts = 'goal_weekly_workouts';

  Future<ActivityGoals> activityGoals() async {
    Future<int?> i(String k) async => int.tryParse(await _db.getKv(k) ?? '');
    const d = ActivityGoals();
    return ActivityGoals(
      dailySteps: await i(_gSteps) ?? d.dailySteps,
      dailyActiveMinutes: await i(_gMinutes) ?? d.dailyActiveMinutes,
      weeklyActiveMinutes: await i(_gWeekMinutes) ?? d.weeklyActiveMinutes,
      weeklyWorkouts: await i(_gWorkouts) ?? d.weeklyWorkouts,
    );
  }

  Stream<ActivityGoals> watchActivityGoals() => _db.watch({Tables.kv}, activityGoals);

  Future<void> setActivityGoals(ActivityGoals g) async {
    await _db.setKv(_gSteps, '${g.dailySteps}');
    await _db.setKv(_gMinutes, '${g.dailyActiveMinutes}');
    await _db.setKv(_gWeekMinutes, '${g.weeklyActiveMinutes}');
    await _db.setKv(_gWorkouts, '${g.weeklyWorkouts}');
  }

  // ---------------------------------------------------------------------------
  // Health Connect connection state (never the health data itself)
  // ---------------------------------------------------------------------------

  static const _hcActivity = 'hc_activity_enabled';
  static const _hcSleep = 'hc_sleep_enabled';
  static const _hcHeart = 'hc_heart_enabled';
  static const _hcLastSync = 'hc_last_sync';

  Future<HealthConnectPrefs> healthConnectPrefs() async => HealthConnectPrefs(
        activity: await _db.getKv(_hcActivity) == '1',
        sleep: await _db.getKv(_hcSleep) == '1',
        heartRate: await _db.getKv(_hcHeart) == '1',
        lastSync: DateTime.tryParse(await _db.getKv(_hcLastSync) ?? ''),
      );

  Future<void> setHealthConnectPrefs({bool? activity, bool? sleep, bool? heartRate}) async {
    if (activity != null) await _db.setKv(_hcActivity, activity ? '1' : '0');
    if (sleep != null) await _db.setKv(_hcSleep, sleep ? '1' : '0');
    if (heartRate != null) await _db.setKv(_hcHeart, heartRate ? '1' : '0');
  }

  Future<void> markHealthConnectSync(DateTime at) => _db.setKv(_hcLastSync, at.toIso8601String());

  Future<void> clearHealthConnectPrefs() async {
    for (final k in [_hcActivity, _hcSleep, _hcHeart, _hcLastSync]) {
      await _db.setKv(k, null);
    }
  }
}

/// Which Health Connect groups the user turned on, and when we last synced.
class HealthConnectPrefs {
  const HealthConnectPrefs({
    this.activity = false,
    this.sleep = false,
    this.heartRate = false,
    this.lastSync,
  });

  final bool activity;
  final bool sleep;
  final bool heartRate;
  final DateTime? lastSync;

  bool get anyEnabled => activity || sleep || heartRate;
}
