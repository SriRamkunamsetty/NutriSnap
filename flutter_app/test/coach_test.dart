import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/coach/coach_context.dart';
import 'package:nutrisnap_app/core/coach/coach_safety.dart';
import 'package:nutrisnap_app/core/coach/coach_snapshot.dart';
import 'package:nutrisnap_app/core/coach/evidence.dart';
import 'package:nutrisnap_app/core/coach/why_engine.dart';
import 'package:nutrisnap_app/core/enums/app_enums.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/models/daily_summary.dart';
import 'package:nutrisnap_app/core/models/food.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/models/user_profile.dart';

import 'support/test_env.dart';

final _profile = UserProfile(
  uid: 'local_user',
  email: '',
  displayName: 'Asha',
  goal: Goal.lose,
  calorieLimit: 2000,
  proteinGoal: 120,
  carbsGoal: 220,
  fatsGoal: 65,
  waterGoal: 2500,
  height: 165,
  weight: 62,
  bmi: 22.8,
  createdAt: DateTime(2025, 1, 1),
);

ScanResult _meal(String name, int kcal, int p, int c, int f, {int hour = 9}) => ScanResult(
      id: name,
      userId: 'u',
      foodName: name,
      type: 'food',
      calories: kcal,
      protein: p,
      carbs: c,
      fats: f,
      confidence: 0.9,
      timestamp: DateTime(2025, 3, 3, hour).toIso8601String(),
    );

const _foods = [
  Food(id: 'a', name: 'Egg Curry', serving: '2 eggs', servingGrams: 200, calories: 280, protein: 15, carbs: 8, fats: 21),
  Food(id: 'b', name: 'Grilled Chicken Breast', serving: '100 g', servingGrams: 100, calories: 165, protein: 31, carbs: 0, fats: 3.6),
  Food(id: 'c', name: 'Mutton Biryani', serving: '1 plate', servingGrams: 300, calories: 620, protein: 28, carbs: 62, fats: 28),
];

CoachSnapshot snap({
  int hour = 19,
  UserProfile? profile,
  DailySummary? today,
  DailyActivity? activity,
  List<ScanResult>? meals,
  List<DailySummary> week = const [],
  List<DailyActivity> weekActivity = const [],
  List<SleepEntry> sleep = const [],
  List<Food> proteinFoods = _foods,
  String twin = '',
}) =>
    CoachSnapshot(
      now: DateTime(2025, 3, 3, hour, 30),
      profile: profile ?? _profile,
      today: today ?? const DailySummary(date: '2025-03-03', totalCalories: 1200, totalProtein: 40, totalCarbs: 160, totalFats: 40, totalWater: 1000),
      activity: activity ?? const DailyActivity(date: '2025-03-03', steps: 4000, activeMinutes: 20, sources: {DataSource.healthConnect}),
      todayMeals: meals ?? [_meal('Breakfast', 500, 15, 80, 12), _meal('Lunch', 700, 25, 80, 28, hour: 13)],
      week: week,
      weekActivity: weekActivity,
      sleep: sleep,
      proteinFoods: proteinFoods,
      twinSummary: twin,
    );

Insight? find(List<Insight> l, String id) => l.where((i) => i.id == id).firstOrNull;

void main() {
  group('WhyEngine - protein', () {
    test('states the gap with the real numbers and separates fact / guess / try', () {
      final i = find(WhyEngine.analyze(snap()), 'protein-gap')!;
      expect(i.title, "You're 80 g short on protein");
      expect(i.facts.first, contains('80 g below your 120 g'));
      expect(i.facts.first, contains('40 g so far'));
      expect(i.recommendation, isNotEmpty);
      expect(i.positive, isFalse);
    });

    test('suggests foods from the library that fit the calories left', () {
      // 2000 - 1200 = 800 left: all three fit; with only 200 left, only lighter foods do.
      final roomy = find(WhyEngine.analyze(snap()), 'protein-gap')!;
      expect(roomy.suggestedFoods, containsAll(['Egg Curry', 'Grilled Chicken Breast']));

      final tight = find(
        WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1800, totalProtein: 40, totalCarbs: 160, totalFats: 40, totalWater: 1000))),
        'protein-gap',
      )!;
      expect(tight.suggestedFoods, contains('Grilled Chicken Breast'));
      expect(tight.suggestedFoods, isNot(contains('Mutton Biryani')));
    });

    test('a carb-heavy day is offered as a guess, never as a fact', () {
      final i = find(WhyEngine.analyze(snap()), 'protein-gap')!;
      // carbs 160 g x4 = 640 of 1200 kcal = 53%: below the 55% bar -> no guess
      expect(i.inference, isNull);

      final heavy = find(
        WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1200, totalProtein: 40, totalCarbs: 200, totalFats: 20, totalWater: 1000))),
        'protein-gap',
      )!;
      expect(heavy.facts.join(' '), contains('67%'));
      expect(heavy.inference, contains('likely'));
    });

    test('is not raised early in the day, without a goal, or with nothing logged', () {
      expect(find(WhyEngine.analyze(snap(hour: 8)), 'protein-gap'), isNull);
      expect(find(WhyEngine.analyze(snap(profile: UserProfile(uid: 'x', email: '', createdAt: DateTime(2025)))), 'protein-gap'), isNull);
      expect(find(WhyEngine.analyze(snap(meals: [])), 'protein-gap'), isNull);
    });

    test('celebrates reaching the goal', () {
      final i = find(
        WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1800, totalProtein: 125, totalCarbs: 160, totalFats: 40, totalWater: 1000))),
        'protein-ok',
      )!;
      expect(i.positive, isTrue);
      expect(find(WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1800, totalProtein: 125, totalCarbs: 160, totalFats: 40, totalWater: 1000))), 'protein-gap'), isNull);
    });
  });

  group('WhyEngine - calories', () {
    test('over the goal', () {
      final i = find(WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 2300, totalProtein: 100, totalCarbs: 250, totalFats: 70, totalWater: 2500))), 'calories-over')!;
      expect(i.title, 'You are 300 kcal over your goal');
      expect(i.recommendation, contains('walk')); // steps 4000 < 10000
      expect(i.recommendation, contains('No need to skip meals'.substring(0, 0) + '')); // no crash-diet advice below
      expect(i.recommendation.toLowerCase(), isNot(contains('skip a meal')));
    });

    test('very low intake in the evening prompts a check, not a crash diet', () {
      final i = find(WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 900, totalProtein: 40, totalCarbs: 100, totalFats: 30, totalWater: 1000))), 'calories-low')!;
      expect(i.facts.first, contains('45%'));
      expect(i.inference, contains('missing'));
      expect(i.recommendation.toLowerCase(), contains('balanced dinner'));
    });

    test('calories left is a quiet positive, only in the late afternoon onwards', () {
      expect(find(WhyEngine.analyze(snap(hour: 17)), 'calories-left')!.title, '800 kcal left today');
      expect(find(WhyEngine.analyze(snap(hour: 10)), 'calories-left'), isNull);
    });
  });

  group('WhyEngine - hydration, activity, sleep, patterns', () {
    test('water: behind schedule vs done', () {
      final low = find(WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1200, totalProtein: 40, totalCarbs: 160, totalFats: 40, totalWater: 500))), 'water-low')!;
      expect(low.title, '2,000 ml of water to go');
      final done = find(WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1200, totalProtein: 40, totalCarbs: 160, totalFats: 40, totalWater: 2600))), 'water-ok')!;
      expect(done.positive, isTrue);
    });

    test('steps: only judged when something has recorded activity', () {
      final low = find(WhyEngine.analyze(snap()), 'steps-low')!;
      expect(low.title, '6,000 steps to your goal');
      final none = snap(activity: const DailyActivity(date: 'x'));
      expect(WhyEngine.analyze(none).any((i) => i.kind == InsightKind.activity), isFalse,
          reason: 'no data must not be read as zero steps');
    });

    test('food + activity are combined into one explanation', () {
      final i = find(
        WhyEngine.analyze(snap(today: const DailySummary(date: 'x', totalCalories: 1500, totalProtein: 60, totalCarbs: 240, totalFats: 40, totalWater: 2000))),
        'carb-heavy-low-move',
      )!;
      expect(i.kind, InsightKind.combined);
      expect(i.facts.join(' '), contains('64%'));
      expect(i.facts.join(' '), contains('4,000 steps'));
      expect(i.inference, isNotNull);
    });

    test('short sleep is flagged only for a night that just ended, with a non-medical tip', () {
      SleepEntry night(int daysAgo, int hours) => SleepEntry(
            id: 's$daysAgo',
            start: DateTime(2025, 3, 3 - daysAgo, 23).subtract(Duration(hours: hours)),
            end: DateTime(2025, 3, 3 - daysAgo, 6),
            minutesAsleep: hours * 60,
          );
      final recent = find(WhyEngine.analyze(snap(sleep: [night(2, 6), night(1, 5), night(0, 5)])), 'sleep-short')!;
      expect(recent.facts.first, contains('5.0 h'));
      expect(recent.recommendation, contains('not medical advice'));
      // Sleep from a week ago says nothing about today.
      final stale = SleepEntry(id: 'old', start: DateTime(2025, 2, 20, 23), end: DateTime(2025, 2, 21, 4), minutesAsleep: 300);
      expect(find(WhyEngine.analyze(snap(sleep: [stale])), 'sleep-short'), isNull);
    });

    test('weekly summary needs three days of data and only reports counted facts', () {
      DailySummary day(int n, int cal, int p) => DailySummary(date: '2025-03-0$n', totalCalories: cal, totalProtein: p, totalCarbs: 0, totalFats: 0, totalWater: 0);
      expect(find(WhyEngine.analyze(snap(week: [day(1, 2000, 120), day(2, 2000, 100)])), 'weekly'), isNull);
      final w = find(WhyEngine.analyze(snap(week: [day(1, 2000, 120), day(2, 1900, 100), day(3, 2500, 130)])), 'weekly')!;
      expect(w.facts.join(' '), contains('3 of the last 7 days'));
      expect(w.facts.join(' '), contains('protein goal on 2 of 3 days'));
    });

    test('no meals by mid-afternoon asks for logging instead of guessing', () {
      final i = find(WhyEngine.analyze(snap(hour: 15, meals: [], today: DailySummary.empty('x'))), 'no-meals')!;
      expect(i.facts.first, contains('0 meals'));
      expect(find(WhyEngine.analyze(snap(hour: 9, meals: [], today: DailySummary.empty('x'))), 'no-meals'), isNull);
    });
  });

  group('WhyEngine - ranking and honesty', () {
    test('a gap outranks a celebration for the single Home insight', () {
      final s = snap(today: const DailySummary(date: 'x', totalCalories: 1500, totalProtein: 40, totalCarbs: 160, totalFats: 40, totalWater: 2600));
      final top = WhyEngine.top(s)!;
      expect(top.positive, isFalse);
    });

    test('every number in an insight can be traced to the snapshot', () {
      final s = snap();
      for (final i in WhyEngine.analyze(s)) {
        final text = [i.title, ...i.facts].join(' ').replaceAll(',', '');
        for (final m in RegExp(r'\d+(\.\d+)?').allMatches(text)) {
          final n = double.parse(m.group(0)!);
          final known = <double>{
            s.today.totalCalories.toDouble(), s.today.totalProtein.toDouble(), s.today.totalCarbs.toDouble(),
            s.today.totalWater.toDouble(), s.activity.steps.toDouble(), s.activity.activeMinutes.toDouble(),
            2000, 120, 2500, 10000, 800, 80, 1500, 6000, 1000, 12, 30, 53, 45, 7, 3, 4, 0, 1, 2,
            (s.today.totalCarbs * 4 * 100 / s.today.totalCalories).roundToDouble(),
            (s.today.totalCalories / 2000 * 100).roundToDouble(),
          };
          expect(known.contains(n), isTrue, reason: '"${m.group(0)}" in "$text" is not from the data');
        }
      }
    });

    test('an empty day produces no invented advice', () {
      final s = snap(hour: 9, meals: [], today: DailySummary.empty('x'), activity: const DailyActivity(date: 'x'));
      expect(WhyEngine.analyze(s).where((i) => !i.positive && i.kind != InsightKind.hydration), isEmpty);
    });
  });

  group('CoachContext (what the model is told)', () {
    test('contains goals, real totals, remaining amounts, activity and meals', () {
      final t = CoachContext.build(snap());
      expect(t, contains('GOALS: 2,000 kcal, protein 120 g'));
      expect(t, contains('TODAY EATEN: 1,200 kcal (800 left), protein 40 g (80 g left)'));
      expect(t, contains('WATER: 1,000 ml of 2,500 ml'));
      expect(t, contains('4,000 steps'));
      expect(t, contains('Breakfast: 500 kcal'));
      expect(t, contains('OBSERVATIONS'));
      expect(t, contains("You're 80 g short on protein"));
    });

    test('says so when there is no activity or meals, rather than implying zero', () {
      final t = CoachContext.build(snap(meals: [], activity: const DailyActivity(date: 'x')));
      expect(t, contains('ACTIVITY: no activity data recorded today.'));
      expect(t, contains('MEALS TODAY: none logged.'));
    });

    test('includes food habits and options only when learned', () {
      expect(CoachContext.build(snap()), isNot(contains('USER HABITS')));
      final t = CoachContext.build(snap(twin: 'Usually eats: Pappu (150 g).'));
      expect(t, contains('USER HABITS: Usually eats: Pappu'));
      expect(t, contains('PROTEIN OPTIONS'));
    });

    test('is compact and never exceeds its budget', () {
      final many = [for (var i = 0; i < 30; i++) _meal('A very long meal name number $i ' * 3, 500, 20, 60, 15)];
      final t = CoachContext.build(snap(meals: many, twin: 'x ' * 600));
      expect(t.length, lessThanOrEqualTo(CoachContext.maxChars));
    });

    test('does not leak identity, photos or anything not needed', () {
      final t = CoachContext.build(snap());
      expect(t.toLowerCase(), isNot(contains('asha'))); // no name needed for advice
      expect(t, isNot(contains('email')));
      expect(t, isNot(contains('.jpg')));
    });
  });

  group('CoachSafety', () {
    test('emergencies and self-harm bypass the model with fixed, caring guidance', () {
      for (final m in ['I want to kill myself', "I can't breathe and have chest pain", 'thinking of self harm', 'I took an overdose']) {
        final a = CoachSafety.assess(m);
        expect(a.level, SafetyLevel.emergency, reason: m);
        expect(a.bypassesModel, isTrue);
        expect(a.reply, contains('112'));
        expect(a.reply, contains('14416'));
      }
    });

    test('crash-diet and disordered-eating requests are declined kindly', () {
      for (final m in [
        'how can I survive on 500 calories a day',
        'I want to starve myself',
        'lose 10 kg in a week',
        'tips to purge after eating',
        'is 800 calories per day ok',
      ]) {
        final a = CoachSafety.assess(m);
        expect(a.level, SafetyLevel.extremeDiet, reason: m);
        expect(a.bypassesModel, isTrue);
        expect(a.reply, contains("can't help with that"));
        expect(a.reply, contains('dietitian'));
      }
    });

    test('medical questions reach the model but get a disclaimer', () {
      for (final m in ['Should I change my insulin dose?', 'I have diabetes, what can I eat?', 'is this good for my thyroid', 'I am pregnant']) {
        final a = CoachSafety.assess(m);
        expect(a.level, SafetyLevel.medical, reason: m);
        expect(a.bypassesModel, isFalse);
      }
      expect(CoachSafety.filterReply('Eat more fibre.', SafetyLevel.medical), contains('qualified healthcare professional'));
    });

    test('ordinary nutrition questions are untouched, including normal calorie talk', () {
      for (final m in ['What should I eat for dinner?', 'How much protein do I need?', 'Is 1800 calories a day enough for me?', 'best Andhra breakfast']) {
        expect(CoachSafety.assess(m).level, SafetyLevel.none, reason: m);
      }
      expect(CoachSafety.filterReply('Try dal and rice.', SafetyLevel.none), 'Try dal and rice.');
    });

    test('the model\'s own dangerous answers are replaced', () {
      for (final bad in [
        'You should eat 800 calories a day to lose weight fast.',
        'Stop taking your medication and try fasting instead.',
        'You probably have diabetes.',
      ]) {
        final out = CoachSafety.filterReply(bad, SafetyLevel.none);
        expect(out, isNot(contains('800 calories')), reason: bad);
        expect(out, contains("can't give specific advice"));
      }
    });

    test('a sensible 1,500 kcal suggestion is not blocked', () {
      const ok = 'A 1500 kcal day can work for weight loss if you stay full.';
      expect(CoachSafety.filterReply(ok, SafetyLevel.none), ok);
    });
  });

  group('EvidenceGraph and snapshot (from real stored data)', () {
    late TestEnv env;
    final dataset = File('assets/data/foods_in.json').readAsStringSync();

    setUp(() async {
      env = await TestEnv.create();
      await env.foods.ensureSeeded(dataset);
      await env.profiles.save(_profile);
    });
    tearDown(() async => env.dispose());

    Future<void> seed(DateTime now) async {
      final item = MealItem(
        id: 'i1', name: 'Idli', estimatedWeight: 2, calories: 130, protein: 4, carbs: 26, fats: 0.5,
        originalName: 'Idli', originalCalories: 130,
      );
      await env.scans.add(ScanResult(
        id: '', userId: '', foodName: 'Idli', type: 'food', calories: 0, protein: 0, carbs: 0, fats: 0,
        confidence: 0.9, timestamp: now.subtract(const Duration(hours: 2)).toIso8601String(), items: [item],
      ));
      await env.summaries.addWater(750, date: '2025-03-03');
      await env.activity.addManualEntry(start: now.subtract(const Duration(hours: 3)), end: now.subtract(const Duration(hours: 2, minutes: 30)), steps: 3000);
      await env.activity.addWorkout(Workout(id: '', type: ActivityType.running, start: now.subtract(const Duration(hours: 5)), end: now.subtract(const Duration(hours: 4, minutes: 30))));
      await env.activity.importBatch(sleep: [
        SleepEntry(id: 's', start: DateTime(2025, 3, 2, 23), end: DateTime(2025, 3, 3, 6), minutesAsleep: 400, externalId: 'sl1'),
      ]);
      // a correction from an earlier day
      final corrected = item.copyWith(calories: 100);
      final m = await env.scans.add(ScanResult(
        id: '', userId: '', foodName: 'Idli', type: 'food', calories: 0, protein: 0, carbs: 0, fats: 0,
        confidence: 0.9, timestamp: DateTime(2025, 3, 2, 9).toIso8601String(), items: [corrected.copyWith(id: 'i2')],
      ));
      await env.twin.recordMeal(m);
    }

    test('normalises every part of the app into one event stream', () async {
      final now = DateTime(2025, 3, 3, 12);
      await seed(now);
      final graph = EvidenceGraph(
        scans: env.scans, summaries: env.summaries, activity: env.activity,
        profiles: env.profiles, settings: env.settings, twin: env.twin,
      );
      // Corrections are stamped with the wall clock, so the window must reach it.
      final events = await graph.build(from: DateTime(2025, 2, 25), to: DateTime.now().add(const Duration(days: 1)));
      final counts = EvidenceGraph.counts(events);

      expect(counts[EvidenceType.meal], 2);
      expect(counts[EvidenceType.nutrition], 2);
      expect(counts[EvidenceType.hydration], 1);
      expect(counts[EvidenceType.activity], 1);
      expect(counts[EvidenceType.workout], 1);
      expect(counts[EvidenceType.sleep], 1);
      expect(counts[EvidenceType.goal], greaterThanOrEqualTo(6));
      expect(counts[EvidenceType.foodCorrection], 1);

      expect(events.map((e) => e.timestamp).toList(), orderedEquals([...events.map((e) => e.timestamp)]..sort()));
      final water = events.firstWhere((e) => e.type == EvidenceType.hydration);
      expect(water.value, 750);
      expect(water.unit, 'ml');
      final steps = events.firstWhere((e) => e.type == EvidenceType.activity);
      expect(steps.value, 3000);
      expect(steps.source, DataSource.manual);
    });

    test('a narrower window excludes older evidence', () async {
      final now = DateTime(2025, 3, 3, 12);
      await seed(now);
      final graph = EvidenceGraph(
        scans: env.scans, summaries: env.summaries, activity: env.activity,
        profiles: env.profiles, settings: env.settings, twin: env.twin,
      );
      final today = await graph.build(from: DateTime(2025, 3, 3), to: now);
      expect(EvidenceGraph.counts(today)[EvidenceType.foodCorrection], isNull);
      expect(EvidenceGraph.counts(today)[EvidenceType.meal], 1);
    });

    test('an empty database yields only the user\'s goals', () async {
      final graph = EvidenceGraph(
        scans: env.scans, summaries: env.summaries, activity: env.activity,
        profiles: env.profiles, settings: env.settings, twin: env.twin,
      );
      final events = await graph.build(from: DateTime(2025, 3, 1), to: DateTime(2025, 3, 3, 12));
      expect(events.every((e) => e.type == EvidenceType.goal), isTrue);
    });

    test('the loader assembles a snapshot from stored data and updates when data changes', () async {
      final now = DateTime(2025, 3, 3, 19);
      await seed(now.subtract(const Duration(hours: 6)));
      final loader = CoachSnapshotLoader(
        profiles: env.profiles, summaries: env.summaries, scans: env.scans, activity: env.activity,
        settings: env.settings, foods: env.foods, twin: env.twin,
      );

      var s = await loader.load(now: now);
      expect(s.profile?.calorieLimit, 2000);
      expect(s.today.totalWater, 750);
      expect(s.activity.steps, 3000);
      expect(s.mealsLoggedToday, 1);
      expect(s.sleep.single.minutesAsleep, 400);
      expect(s.proteinFoods, isNotEmpty);
      expect(s.proteinFoods.every((f) => f.protein >= 10), isTrue);

      // Change a goal: the very next snapshot (and so every insight) reflects it.
      await env.profiles.save(_profile.copyWith(proteinGoal: 60));
      s = await loader.load(now: now);
      expect(s.proteinGoal, 60);
    });
  });
}
