import 'package:intl/intl.dart';

import '../models/scan_result.dart';
import 'coach_snapshot.dart';
import 'why_engine.dart';

/// Builds the small, structured briefing the model receives instead of the
/// whole database. Only today's totals, goals, a few recent meals and the
/// Why Engine's observations go in. That keeps prompts short and fast, and it
/// means you can show the user *exactly* what the coach is told.
class CoachContext {
  const CoachContext._();

  static final _n = NumberFormat('#,###');

  /// Rough character budget (~4 chars per token) so the prompt never crowds
  /// out the model's own answer in the 4k-token window.
  static const int maxChars = 3200;

  static String build(CoachSnapshot s, {List<Insight>? insights}) {
    final b = StringBuffer();
    final p = s.profile;
    final obs = insights ?? WhyEngine.analyze(s);

    b.writeln('NOW: ${DateFormat('EEEE, d MMM, h:mm a').format(s.now)}');

    // Goals
    final goals = <String>[
      if (s.calorieGoal != null) '${_n.format(s.calorieGoal)} kcal',
      if (s.proteinGoal != null) 'protein ${s.proteinGoal} g',
      if (s.carbsGoal != null) 'carbs ${s.carbsGoal} g',
      if (s.fatsGoal != null) 'fat ${s.fatsGoal} g',
      if (s.waterGoal != null) 'water ${_n.format(s.waterGoal)} ml',
      '${_n.format(s.stepGoal)} steps',
    ];
    b.writeln('GOALS: ${goals.join(', ')}. Goal: ${p?.goal?.name ?? 'maintain'} weight.');
    if (p?.height != null && p?.weight != null) {
      b.writeln('BODY: ${p!.height!.round()} cm, ${p.weight!.round()} kg'
          '${p.bmi == null ? '' : ', BMI ${p.bmi!.toStringAsFixed(1)}'}.');
    }

    // Today - nutrition
    final t = s.today;
    b.writeln('TODAY EATEN: ${_n.format(t.totalCalories)} kcal'
        '${s.calorieGoal == null ? '' : ' (${_n.format(s.calorieGoal! - t.totalCalories)} left)'}, '
        'protein ${t.totalProtein} g'
        '${s.proteinGoal == null ? '' : ' (${s.proteinGoal! - t.totalProtein} g left)'}, '
        'carbs ${t.totalCarbs} g, fat ${t.totalFats} g.');
    b.writeln('WATER: ${_n.format(t.totalWater)} ml'
        '${s.waterGoal == null ? '' : ' of ${_n.format(s.waterGoal)} ml'}.');

    // Today - activity
    if (s.hasActivityData) {
      final a = s.activity;
      b.writeln('ACTIVITY: ${_n.format(a.steps)} steps, ${a.distanceKm.toStringAsFixed(1)} km, '
          '${a.activeCalories.round()} active kcal, ${a.activeMinutes} active min'
          '${a.workoutCount > 0 ? ', ${a.workoutCount} workout(s)' : ''} (source: ${a.sourceLabel}).');
    } else {
      b.writeln('ACTIVITY: no activity data recorded today.');
    }

    // Sleep
    if (s.sleep.isNotEmpty) {
      final last = s.sleep.last;
      if (s.now.difference(last.end).inHours <= 36) {
        b.writeln('SLEEP: last night ${(last.minutesAsleep / 60).toStringAsFixed(1)} h.');
      }
    }

    // Meals
    if (s.todayMeals.isEmpty) {
      b.writeln('MEALS TODAY: none logged.');
    } else {
      b.writeln('MEALS TODAY:');
      for (final m in s.todayMeals.take(6)) {
        b.writeln('- ${_time(m)} ${m.foodName}: ${m.calories} kcal, P${m.protein} C${m.carbs} F${m.fats}');
      }
    }

    if (s.twinSummary.isNotEmpty) b.writeln('USER HABITS: ${s.twinSummary.replaceAll('\n', ' ')}');
    if (s.proteinFoods.isNotEmpty) {
      b.writeln('PROTEIN OPTIONS THEY LIKELY EAT: ${s.proteinFoods.take(6).map((f) => f.name).join(', ')}.');
    }

    // The engine's computed observations - the only "facts" beyond the numbers above.
    if (obs.isNotEmpty) {
      b.writeln('OBSERVATIONS (computed from their data):');
      for (final i in obs.take(4)) {
        b.writeln('- ${i.title}. ${i.facts.join(' ')}${i.inference == null ? '' : ' [inference] ${i.inference}'}');
      }
    }

    final text = b.toString().trim();
    return text.length <= maxChars ? text : '${text.substring(0, maxChars - 1)}…';
  }

  static String _time(ScanResult m) {
    final t = DateTime.tryParse(m.timestamp);
    return t == null ? '' : DateFormat('h:mm a').format(t);
  }
}
