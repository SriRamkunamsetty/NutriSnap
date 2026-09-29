import 'package:equatable/equatable.dart';

import '../models/activity.dart';
import '../models/daily_summary.dart';
import '../models/food.dart';
import '../models/scan_result.dart';
import '../models/user_profile.dart';
import '../repositories/activity_repository.dart';
import '../repositories/food_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/scan_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/summary_repository.dart';
import '../services/food_twin_service.dart';
import '../utils/datetime_utils.dart';

/// Everything the Coach and the Why Engine need to know about "now", gathered
/// once from the local database into plain data. Both consumers are pure
/// functions of this object, so they are easy to test and can never disagree.
class CoachSnapshot extends Equatable {
  const CoachSnapshot({
    required this.now,
    this.profile,
    required this.today,
    required this.activity,
    this.activityGoals = const ActivityGoals(),
    this.todayMeals = const [],
    this.week = const [],
    this.weekActivity = const [],
    this.weekWorkouts = const [],
    this.sleep = const [],
    this.twinSummary = '',
    this.proteinFoods = const [],
    this.healthDataConnected = false,
  });

  final DateTime now;
  final UserProfile? profile;
  final DailySummary today;
  final DailyActivity activity;
  final ActivityGoals activityGoals;

  /// Food meals logged today, oldest first.
  final List<ScanResult> todayMeals;

  /// Per-day nutrition for the last 7 days, oldest first (days with data only).
  final List<DailySummary> week;
  final List<DailyActivity> weekActivity;
  final List<Workout> weekWorkouts;

  /// Recent nights (oldest first).
  final List<SleepEntry> sleep;

  /// Short description of learned eating habits (empty if nothing learned).
  final String twinSummary;

  /// High-protein foods that suit the user's usual food style.
  final List<Food> proteinFoods;
  final bool healthDataConnected;

  // Goals (null when the user hasn't set one)
  int? get calorieGoal => _pos(profile?.calorieLimit);
  int? get proteinGoal => _pos(profile?.proteinGoal);
  int? get carbsGoal => _pos(profile?.carbsGoal);
  int? get fatsGoal => _pos(profile?.fatsGoal);
  int? get waterGoal => _pos(profile?.waterGoal);
  int get stepGoal => activityGoals.dailySteps;

  static int? _pos(int? v) => (v != null && v > 0) ? v : null;

  int get mealsLoggedToday => todayMeals.length;
  int get hour => now.hour;

  /// Steps are only "known" if something has recorded activity today.
  bool get hasActivityData => activity.hasData;

  @override
  List<Object?> get props => [
        now, profile, today, activity, activityGoals, todayMeals, week, weekActivity,
        weekWorkouts, sleep, twinSummary, proteinFoods, healthDataConnected,
      ];
}

class CoachSnapshotLoader {
  CoachSnapshotLoader({
    required ProfileRepository profiles,
    required SummaryRepository summaries,
    required ScanRepository scans,
    required ActivityRepository activity,
    required SettingsRepository settings,
    required FoodRepository foods,
    required FoodTwinService twin,
  })  : _profiles = profiles,
        _summaries = summaries,
        _scans = scans,
        _activity = activity,
        _settings = settings,
        _foods = foods,
        _twin = twin;

  final ProfileRepository _profiles;
  final SummaryRepository _summaries;
  final ScanRepository _scans;
  final ActivityRepository _activity;
  final SettingsRepository _settings;
  final FoodRepository _foods;
  final FoodTwinService _twin;

  Future<CoachSnapshot> load({DateTime? now, bool healthDataConnected = false}) async {
    final clock = now ?? DateTime.now();
    final today = DateTimeUtils.dayKey(clock);
    final weekStart = DateTimeUtils.dayKey(DateTime(clock.year, clock.month, clock.day - 6));
    final sleepStart = DateTimeUtils.dayKey(DateTime(clock.year, clock.month, clock.day - 13));

    final profile = await _profiles.get();
    final twinProfile = await _twin.profile();

    final startOfDay = DateTime(clock.year, clock.month, clock.day);
    final meals = (await _scans.recent(limit: 60)).where((m) {
      final at = DateTime.tryParse(m.timestamp);
      return m.isFood && at != null && !at.isBefore(startOfDay) && !at.isAfter(clock.add(const Duration(minutes: 1)));
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return CoachSnapshot(
      now: clock,
      profile: profile,
      today: await _summaries.forDate(today),
      activity: await _activity.daily(today),
      activityGoals: await _settings.activityGoals(),
      todayMeals: meals,
      week: await _summaries.range(weekStart, today),
      weekActivity: await _activity.range(weekStart, today),
      weekWorkouts: await _activity.workoutsBetween(weekStart, today),
      sleep: await _activity.sleepBetween(sleepStart, today),
      twinSummary: await _twin.promptSummary(),
      proteinFoods: await _proteinFoods(twinProfile),
      healthDataConnected: healthDataConnected,
    );
  }

  /// Protein-dense foods, preferring the regions the user actually eats.
  Future<List<Food>> _proteinFoods(FoodTwinProfile twin) async {
    final all = await _foods.search('', limit: 400);
    final dense = all.where((f) => f.protein >= 10 && f.calories > 0 && f.protein / f.calories >= 0.07).toList();
    final topRegions = (twin.regionalPreferences.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(2)
        .map((e) => e.key)
        .toSet();
    int score(Food f) => (f.regions.any(topRegions.contains) ? 2 : 0) + (f.hasTag('Home Food') ? 1 : 0);
    dense.sort((a, b) {
      final s = score(b).compareTo(score(a));
      return s != 0 ? s : b.protein.compareTo(a.protein);
    });
    return dense.take(10).toList();
  }
}
