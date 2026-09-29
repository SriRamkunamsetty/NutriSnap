import '../models/activity.dart';
import '../models/daily_summary.dart';
import '../utils/datetime_utils.dart';

/// One calendar day of everything the trends view can show. A `null` means
/// "nothing was recorded", which is different from a recorded zero.
class TrendDay {
  const TrendDay({
    required this.date,
    this.calories,
    this.protein,
    this.water,
    this.steps,
    this.activeMinutes,
    this.sleepMinutes,
    this.workouts = 0,
  });

  final String date;
  final int? calories;
  final int? protein;
  final int? water;
  final int? steps;
  final int? activeMinutes;
  final int? sleepMinutes;
  final int workouts;
}

/// "X of Y days" with the days that count as the denominator.
class Adherence {
  const Adherence(this.met, this.of);
  final int met;
  final int of;
}

class TrendGoals {
  const TrendGoals({this.calories, this.protein, this.water, this.steps});
  final int? calories;
  final int? protein;
  final int? water;
  final int? steps;
}

class TrendReport {
  const TrendReport({
    required this.days,
    required this.daysLogged,
    required this.enoughData,
    this.avgCalories,
    this.calorieBalance,
    this.avgProtein,
    this.avgWater,
    this.avgSteps,
    this.avgSleepHours,
    required this.totalWorkouts,
    required this.totalActiveMinutes,
    this.calorieAdherence,
    this.proteinAdherence,
    this.waterAdherence,
    this.stepAdherence,
    this.weightStart,
    this.weightEnd,
    this.weightPoints = const [],
  });

  /// Every day of the window, oldest first, including empty ones.
  final List<TrendDay> days;
  final int daysLogged;

  /// Averages and adherence are only shown from [minDays] logged days on.
  final bool enoughData;
  static const int minDays = 3;

  final double? avgCalories;

  /// Average daily intake minus the calorie goal (negative = under).
  final double? calorieBalance;
  final double? avgProtein;
  final double? avgWater;
  final double? avgSteps;
  final double? avgSleepHours;
  final int totalWorkouts;
  final int totalActiveMinutes;
  final Adherence? calorieAdherence;
  final Adherence? proteinAdherence;
  final Adherence? waterAdherence;
  final Adherence? stepAdherence;

  /// Weight at the start of the window (last value before it, or the first
  /// inside it) and the latest value. Null without at least two recordings.
  final double? weightStart;
  final double? weightEnd;
  final List<double> weightPoints;
  double? get weightChange => weightStart == null || weightEnd == null ? null : weightEnd! - weightStart!;

  int get daysNeeded => enoughData ? 0 : minDays - daysLogged;
}

class TrendCalculator {
  /// Builds a report for the [windowDays] days ending on [today], from data
  /// exactly as stored. Nothing is estimated or filled in.
  static TrendReport build({
    required DateTime today,
    required int windowDays,
    required List<DailySummary> summaries,
    required List<DailyActivity> activity,
    required List<SleepEntry> sleep,
    required TrendGoals goals,
    List<(String, double)> weights = const [],
    (String, double)? weightBefore,
  }) {
    final sums = {for (final s in summaries) s.date: s};
    final acts = {for (final a in activity) a.date: a};
    final sleepBy = <String, int>{};
    for (final s in sleep) {
      final k = DateTimeUtils.dayKey(s.end);
      sleepBy[k] = (sleepBy[k] ?? 0) + s.minutesAsleep;
    }

    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: windowDays - 1));
    final days = <TrendDay>[];
    for (var i = 0; i < windowDays; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      final k = DateTimeUtils.dayKey(d);
      final s = sums[k];
      final a = acts[k];
      days.add(TrendDay(
        date: k,
        calories: s != null && s.totalCalories > 0 ? s.totalCalories : null,
        protein: s != null && s.totalCalories > 0 ? s.totalProtein : null,
        water: s != null && s.totalWater > 0 ? s.totalWater : null,
        steps: a != null && a.steps > 0 ? a.steps : null,
        activeMinutes: a != null && a.activeMinutes > 0 ? a.activeMinutes : null,
        sleepMinutes: sleepBy[k],
        workouts: a?.workoutCount ?? 0,
      ));
    }

    double? avg(Iterable<int?> v) {
      final l = v.whereType<int>().toList();
      if (l.isEmpty) return null;
      return l.reduce((a, b) => a + b) / l.length;
    }

    Adherence? adh(Iterable<int?> v, int? goal, bool Function(int value, int goal) ok) {
      if (goal == null || goal <= 0) return null;
      final l = v.whereType<int>().toList();
      if (l.isEmpty) return null;
      return Adherence(l.where((x) => ok(x, goal)).length, l.length);
    }

    final logged = days.where((d) => d.calories != null).length;
    final enough = logged >= TrendReport.minDays;
    final avgCal = avg(days.map((d) => d.calories));
    final sleepAvg = avg(days.map((d) => d.sleepMinutes));

    // Weight: one point per recorded day (latest that day), anchored on the
    // last reading before the window when there is one.
    final byDay = <String, double>{for (final w in weights) w.$1: w.$2};
    final wDays = byDay.keys.toList()..sort();
    double? wStart;
    double? wEnd;
    final wPoints = [for (final k in wDays) byDay[k]!];
    if (wPoints.isNotEmpty) {
      wEnd = wPoints.last;
      wStart = weightBefore?.$2 ?? (wPoints.length >= 2 ? wPoints.first : null);
    }
    if (wStart == null) wEnd = null;

    return TrendReport(
      days: days,
      daysLogged: logged,
      enoughData: enough,
      avgCalories: enough ? avgCal : null,
      calorieBalance: enough && avgCal != null && goals.calories != null ? avgCal - goals.calories! : null,
      avgProtein: enough ? avg(days.map((d) => d.protein)) : null,
      avgWater: avg(days.map((d) => d.water)),
      avgSteps: avg(days.map((d) => d.steps)),
      avgSleepHours: sleepAvg == null ? null : sleepAvg / 60,
      totalWorkouts: days.fold(0, (a, d) => a + d.workouts),
      totalActiveMinutes: days.fold(0, (a, d) => a + (d.activeMinutes ?? 0)),
      // On or under the calorie goal, but only on days that were logged.
      calorieAdherence: enough ? adh(days.map((d) => d.calories), goals.calories, (v, g) => v <= g * 1.05) : null,
      proteinAdherence: enough ? adh(days.map((d) => d.protein), goals.protein, (v, g) => v >= g * 0.9) : null,
      waterAdherence: adh(days.map((d) => d.water), goals.water, (v, g) => v >= g * 0.9),
      stepAdherence: adh(days.map((d) => d.steps), goals.steps, (v, g) => v >= g),
      weightStart: wStart,
      weightEnd: wEnd,
      weightPoints: wEnd == null ? const [] : wPoints,
    );
  }
}
