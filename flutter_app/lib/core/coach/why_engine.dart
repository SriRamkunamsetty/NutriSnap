import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../models/food.dart';
import 'coach_snapshot.dart';

enum InsightKind { data, protein, calories, hydration, activity, sleep, combined, weekly }

/// A piece of advice with its reasoning laid bare:
///
/// * [facts]           - numbers read straight from the user's stored data;
/// * [inference]       - what those facts *probably* mean (never stated as fact);
/// * [recommendation]  - one practical next step.
class Insight extends Equatable {
  const Insight({
    required this.id,
    required this.kind,
    required this.title,
    required this.facts,
    this.inference,
    required this.recommendation,
    required this.priority,
    this.positive = false,
    this.suggestedFoods = const [],
  });

  final String id;
  final InsightKind kind;

  /// One line, e.g. "You're 28 g short on protein".
  final String title;
  final List<String> facts;
  final String? inference;
  final String recommendation;

  /// Higher shows first.
  final int priority;

  /// A win to celebrate rather than a gap to close.
  final bool positive;
  final List<String> suggestedFoods;

  @override
  List<Object?> get props => [id, kind, title, facts, inference, recommendation, priority, positive, suggestedFoods];
}

/// Turns a [CoachSnapshot] into explainable insights. Pure and deterministic:
/// the same data always gives the same advice, and every number comes from the
/// snapshot. The language model only *explains* these; it never invents them.
class WhyEngine {
  const WhyEngine._();

  static final _n = NumberFormat('#,###');

  /// How much of a daily target is reasonable to have reached by [hour].
  static double expectedFraction(int hour) => ((hour - 6) / 15).clamp(0.1, 1.0);

  static List<Insight> analyze(CoachSnapshot s) {
    final out = <Insight>[
      ...?_data(s),
      ..._protein(s),
      ..._calories(s),
      ..._hydration(s),
      ..._activity(s),
      ..._combined(s),
      ..._sleep(s),
      ..._weekly(s),
    ];
    out.sort((a, b) => b.priority.compareTo(a.priority));
    return out;
  }

  /// The single most valuable insight for Home (a gap beats a celebration).
  static Insight? top(CoachSnapshot s) {
    final all = analyze(s);
    return all.isEmpty ? null : all.first;
  }

  // ---------------------------------------------------------------------------

  static List<Insight>? _data(CoachSnapshot s) {
    if (s.mealsLoggedToday > 0 || s.hour < 11) return null;
    return [
      Insight(
        id: 'no-meals',
        kind: InsightKind.data,
        title: s.hour >= 14 ? 'No meals logged yet today' : 'Nothing logged yet',
        facts: ['You have logged 0 meals today and it is ${_time(s)}.'],
        inference: 'Either you have not eaten, or meals have not been logged yet.',
        recommendation: 'Log what you have eaten so far (scan it, or pick it from the Food Library) so advice can match your day.',
        priority: s.hour >= 14 ? 70 : 40,
      ),
    ];
  }

  static List<Insight> _protein(CoachSnapshot s) {
    final goal = s.proteinGoal;
    if (goal == null || s.mealsLoggedToday == 0) return const [];
    final have = s.today.totalProtein;
    final left = goal - have;

    if (have >= goal * 0.9) {
      return [
        Insight(
          id: 'protein-ok',
          kind: InsightKind.protein,
          title: left <= 0 ? 'Protein goal reached' : 'Almost at your protein goal',
          facts: ['You have had $have g of your $goal g protein goal today.'],
          recommendation: 'Nice work. Keep meals balanced for the rest of the day.',
          priority: 20,
          positive: true,
        ),
      ];
    }

    final behind = have < goal * expectedFraction(s.hour) * 0.7;
    if (left < 15 || !behind) return const [];

    final kcalLeft = s.calorieGoal == null ? null : s.calorieGoal! - s.today.totalCalories;
    final foods = _proteinPicks(s.proteinFoods, left, kcalLeft);
    final facts = <String>[
      'You are $left g below your $goal g protein target ($have g so far).',
    ];
    String? inference;
    final carbShare = _carbShare(s);
    if (carbShare != null && carbShare >= 0.55 && s.mealsLoggedToday >= 2) {
      facts.add('${(carbShare * 100).round()}% of the calories you have logged today are from carbohydrates.');
      inference = 'Your meals so far are carbohydrate-heavy, which likely explains the protein gap.';
    } else if (s.mealsLoggedToday <= 1 && s.hour >= 13) {
      inference = 'You may simply not have had a protein-rich meal yet.';
    }
    return [
      Insight(
        id: 'protein-gap',
        kind: InsightKind.protein,
        title: "You're $left g short on protein",
        facts: facts,
        inference: inference,
        recommendation: foods.isEmpty
            ? 'Add a protein source to your next meal: eggs, dal, paneer, curd or chicken.'
            : 'Add ${foods.take(3).join(', ')} to close the gap without a big meal.',
        priority: 60 + (left * 100 / goal).round().clamp(0, 30),
        suggestedFoods: foods,
      ),
    ];
  }

  static List<Insight> _calories(CoachSnapshot s) {
    final goal = s.calorieGoal;
    if (goal == null || s.mealsLoggedToday == 0) return const [];
    final eaten = s.today.totalCalories;
    final left = goal - eaten;

    if (eaten > goal * 1.05) {
      final over = eaten - goal;
      final walk = s.hasActivityData && s.activity.steps < s.stepGoal;
      return [
        Insight(
          id: 'calories-over',
          kind: InsightKind.calories,
          title: 'You are ${_n.format(over)} kcal over your goal',
          facts: [
            'You have logged ${_n.format(eaten)} kcal against a ${_n.format(goal)} kcal goal.',
            if (s.hasActivityData) 'You have taken ${_n.format(s.activity.steps)} steps today.',
          ],
          inference: 'One day over rarely matters; the weekly pattern matters more.',
          recommendation: walk
              ? 'Keep your next meal light and add a 20-minute walk to close some of the gap.'
              : 'Keep your next meal light and drink water. No need to skip meals to compensate.',
          priority: 65,
        ),
      ];
    }

    if (s.hour >= 19 && eaten < goal * 0.6) {
      return [
        Insight(
          id: 'calories-low',
          kind: InsightKind.calories,
          title: 'You are well under your calorie goal',
          facts: ['You have logged ${_n.format(eaten)} of ${_n.format(goal)} kcal (${((eaten / goal) * 100).round()}%) and it is ${_time(s)}.'],
          inference: 'Meals may be missing from your log, or you have eaten very little today.',
          recommendation: 'Check for meals you forgot to log. If you really have eaten this little, have a balanced dinner rather than skipping it.',
          priority: 55,
        ),
      ];
    }

    if (left > 0 && s.hour >= 16) {
      return [
        Insight(
          id: 'calories-left',
          kind: InsightKind.calories,
          title: '${_n.format(left)} kcal left today',
          facts: ['You have logged ${_n.format(eaten)} of your ${_n.format(goal)} kcal goal.'],
          recommendation: left >= 500
              ? 'That is room for a proper dinner plus a snack.'
              : 'A light dinner will land you right on target.',
          priority: 30,
          positive: true,
        ),
      ];
    }
    return const [];
  }

  static List<Insight> _hydration(CoachSnapshot s) {
    final goal = s.waterGoal;
    if (goal == null) return const [];
    final have = s.today.totalWater;
    if (have >= goal) {
      return [
        Insight(
          id: 'water-ok',
          kind: InsightKind.hydration,
          title: 'Hydration goal reached',
          facts: ['You have logged ${_n.format(have)} of ${_n.format(goal)} ml of water.'],
          recommendation: 'Great job. Sip as you need for the rest of the day.',
          priority: 15,
          positive: true,
        ),
      ];
    }
    if (s.hour >= 14 && have < goal * expectedFraction(s.hour) * 0.6) {
      final left = goal - have;
      return [
        Insight(
          id: 'water-low',
          kind: InsightKind.hydration,
          title: '${_n.format(left)} ml of water to go',
          facts: ['You have logged ${_n.format(have)} of ${_n.format(goal)} ml, and it is ${_time(s)}.'],
          recommendation: 'Have a glass (250 ml) now and another with each remaining meal.',
          priority: 45 + (left * 20 / goal).round(),
        ),
      ];
    }
    return const [];
  }

  static List<Insight> _activity(CoachSnapshot s) {
    if (!s.hasActivityData) return const [];
    final steps = s.activity.steps;
    final goal = s.stepGoal;
    if (steps >= goal) {
      return [
        Insight(
          id: 'steps-ok',
          kind: InsightKind.activity,
          title: 'Step goal reached',
          facts: ['You have taken ${_n.format(steps)} steps against a ${_n.format(goal)} goal.'],
          recommendation: 'Great. A short stretch in the evening keeps you loose.',
          priority: 18,
          positive: true,
        ),
      ];
    }
    if (s.hour >= 17 && steps < goal * 0.6 && s.hour < 22) {
      final left = goal - steps;
      return [
        Insight(
          id: 'steps-low',
          kind: InsightKind.activity,
          title: '${_n.format(left)} steps to your goal',
          facts: ['You have taken ${_n.format(steps)} of ${_n.format(goal)} steps (${s.activity.activeMinutes} active minutes).'],
          recommendation: 'A brisk 20-30 minute walk covers about ${_n.format((left).clamp(0, 3500))} steps.',
          priority: 50,
        ),
      ];
    }
    return const [];
  }

  /// Food + activity together: the "why" behind a day that feels off.
  static List<Insight> _combined(CoachSnapshot s) {
    if (s.mealsLoggedToday < 2 || !s.hasActivityData) return const [];
    final carbShare = _carbShare(s);
    if (carbShare == null || carbShare < 0.55) return const [];
    final steps = s.activity.steps;
    if (steps >= s.stepGoal * 0.6) return const [];
    return [
      Insight(
        id: 'carb-heavy-low-move',
        kind: InsightKind.combined,
        title: 'A carb-heavy, low-movement day',
        facts: [
          '${(carbShare * 100).round()}% of today\'s logged calories are carbohydrates.',
          'You have taken ${_n.format(steps)} steps (goal ${_n.format(s.stepGoal)}).',
        ],
        inference: 'This combination often leaves you feeling sluggish and hungry again sooner.',
        recommendation: 'Swap one starchy portion for protein or vegetables at your next meal, and take a 15-minute walk after eating.',
        priority: 52,
      ),
    ];
  }

  static List<Insight> _sleep(CoachSnapshot s) {
    if (s.sleep.isEmpty) return const [];
    final last = s.sleep.last;
    // Only speak about a night that just ended (within 36 h).
    if (s.now.difference(last.end).inHours > 36) return const [];
    final hours = last.minutesAsleep / 60;
    final recent = s.sleep.length > 3 ? s.sleep.sublist(s.sleep.length - 3) : s.sleep;
    final avg = recent.fold<int>(0, (a, e) => a + e.minutesAsleep) / recent.length / 60;

    if (hours < 6 && avg < 6.5) {
      return [
        Insight(
          id: 'sleep-short',
          kind: InsightKind.sleep,
          title: 'Short sleep lately',
          facts: [
            'Last night you slept ${hours.toStringAsFixed(1)} h.',
            'Your last ${recent.length} nights average ${avg.toStringAsFixed(1)} h.',
          ],
          inference: 'Short sleep can make hunger and cravings harder to manage.',
          recommendation: 'Try to be in bed 30-60 minutes earlier tonight, and go easy on caffeine after mid-afternoon. (General wellness tip, not medical advice.)',
          priority: 42,
        ),
      ];
    }
    return const [];
  }

  static List<Insight> _weekly(CoachSnapshot s) {
    if (s.week.length < 3) return const [];
    final proteinGoal = s.proteinGoal;
    final calGoal = s.calorieGoal;
    final facts = <String>[
      'You logged food on ${s.week.length} of the last 7 days.',
    ];
    if (calGoal != null) {
      final within = s.week.where((d) => d.totalCalories >= calGoal * 0.85 && d.totalCalories <= calGoal * 1.1).length;
      facts.add('$within of those days were within about 10-15% of your calorie goal.');
    }
    if (proteinGoal != null) {
      final hit = s.week.where((d) => d.totalProtein >= proteinGoal * 0.9).length;
      facts.add('You reached your protein goal on $hit of ${s.week.length} days.');
    }
    if (s.weekActivity.isNotEmpty) {
      final hit = s.weekActivity.where((d) => d.steps >= s.stepGoal).length;
      facts.add('You hit your step goal on $hit of ${s.weekActivity.length} recorded days.');
    }
    final workouts = s.weekWorkouts.length;
    if (workouts > 0) facts.add('You logged $workouts workout${workouts == 1 ? '' : 's'} this week.');
    return [
      Insight(
        id: 'weekly',
        kind: InsightKind.weekly,
        title: 'Your week so far',
        facts: facts,
        recommendation: 'Pick the one habit that slipped most and make it easy tomorrow.',
        priority: 10,
      ),
    ];
  }

  // ---------------------------------------------------------------------------

  static double? _carbShare(CoachSnapshot s) {
    final kcal = s.today.totalCalories;
    if (kcal < 300) return null; // too little data to judge a pattern
    return (s.today.totalCarbs * 4) / kcal;
  }

  /// Names of protein-dense foods that fit inside the remaining calories.
  static List<String> _proteinPicks(List<Food> foods, int proteinLeft, int? kcalLeft) {
    final fitting = foods.where((f) => kcalLeft == null || kcalLeft <= 0 || f.calories <= kcalLeft + 50).toList();
    return [for (final f in (fitting.isEmpty ? foods : fitting).take(4)) f.name];
  }

  static String _time(CoachSnapshot s) => DateFormat('h:mm a').format(s.now);
}
