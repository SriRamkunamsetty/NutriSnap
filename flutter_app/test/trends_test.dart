import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/coach/trends.dart';
import 'package:nutrisnap_app/core/models/activity.dart';
import 'package:nutrisnap_app/core/models/daily_summary.dart';
import 'package:nutrisnap_app/features/home/screens/history_screen.dart';

DailySummary day(String d, int kcal, int p, int water) =>
    DailySummary(date: d, totalCalories: kcal, totalProtein: p, totalCarbs: 0, totalFats: 0, totalWater: water);

final today = DateTime(2025, 3, 10, 20);

TrendReport report({
  List<DailySummary> s = const [],
  List<DailyActivity> a = const [],
  List<SleepEntry> sl = const [],
  int window = 7,
  TrendGoals goals = const TrendGoals(calories: 2000, protein: 100, water: 2500, steps: 8000),
}) =>
    TrendCalculator.build(today: today, windowDays: window, summaries: s, activity: a, sleep: sl, goals: goals);

void main() {
  group('TrendCalculator', () {
    test('covers every day of the window, oldest first, ending today', () {
      final r = report(window: 7);
      expect(r.days.length, 7);
      expect(r.days.first.date, '2025-03-04');
      expect(r.days.last.date, '2025-03-10');
      expect(report(window: 30).days.length, 30);
    });

    test('nothing recorded means nothing shown, not zeros', () {
      final r = report();
      expect(r.daysLogged, 0);
      expect(r.enoughData, isFalse);
      expect(r.avgCalories, isNull);
      expect(r.avgSteps, isNull);
      expect(r.avgSleepHours, isNull);
      expect(r.calorieAdherence, isNull);
      expect(r.days.every((d) => d.calories == null && d.steps == null), isTrue);
    });

    test('needs three logged days before averaging, and says how many more', () {
      final two = report(s: [day('2025-03-09', 2000, 90, 0), day('2025-03-10', 1800, 90, 0)]);
      expect(two.enoughData, isFalse);
      expect(two.daysNeeded, 1);
      expect(two.avgCalories, isNull);
      expect(two.calorieBalance, isNull);
    });

    test('averages only logged days; unlogged days do not drag the mean to zero', () {
      final r = report(s: [day('2025-03-08', 2200, 80, 0), day('2025-03-09', 1800, 120, 0), day('2025-03-10', 2000, 100, 0)]);
      expect(r.enoughData, isTrue);
      expect(r.daysLogged, 3);
      expect(r.avgCalories, 2000);
      expect(r.calorieBalance, 0);
      expect(r.avgProtein, 100);
    });

    test('calorie balance is average minus goal, and adherence counts days at or near goal', () {
      final r = report(s: [day('2025-03-08', 2400, 50, 0), day('2025-03-09', 1500, 100, 0), day('2025-03-10', 1600, 95, 0)]);
      expect(r.calorieBalance, closeTo(5500 / 3 - 2000, 0.001));
      expect(r.calorieAdherence!.met, 2); // 1500 and 1600
      expect(r.calorieAdherence!.of, 3);
      expect(r.proteinAdherence!.met, 2); // >= 90 g: 100 and 95
    });

    test('a day with only water does not count as a logged meal day', () {
      final r = report(s: [day('2025-03-10', 0, 0, 1200)]);
      expect(r.daysLogged, 0);
      expect(r.avgWater, 1200);
      expect(r.days.last.calories, isNull);
    });

    test('hydration and steps report independently of meal logging', () {
      final r = report(
        s: [day('2025-03-09', 0, 0, 2600), day('2025-03-10', 0, 0, 1000)],
        a: [
          const DailyActivity(date: '2025-03-09', steps: 9000, activeMinutes: 40, workoutCount: 1),
          const DailyActivity(date: '2025-03-10', steps: 3000, activeMinutes: 10),
        ],
      );
      expect(r.avgWater, 1800);
      expect(r.waterAdherence!.met, 1);
      expect(r.avgSteps, 6000);
      expect(r.stepAdherence!.met, 1);
      expect(r.totalWorkouts, 1);
      expect(r.totalActiveMinutes, 50);
    });

    test('sleep is attributed to the day the person woke up', () {
      final r = report(sl: [
        SleepEntry(id: 'a', start: DateTime(2025, 3, 9, 23), end: DateTime(2025, 3, 10, 6), minutesAsleep: 420),
        SleepEntry(id: 'b', start: DateTime(2025, 3, 8, 23), end: DateTime(2025, 3, 9, 5), minutesAsleep: 360),
      ]);
      expect(r.days.last.sleepMinutes, 420);
      expect(r.avgSleepHours, closeTo(6.5, 0.001));
    });

    test('data outside the window is ignored', () {
      final r = report(s: [day('2025-02-01', 3000, 10, 0)], window: 7);
      expect(r.daysLogged, 0);
    });

    test('without goals there is no balance or adherence to invent', () {
      final r = report(
        s: [day('2025-03-08', 2000, 80, 0), day('2025-03-09', 2000, 80, 0), day('2025-03-10', 2000, 80, 0)],
        goals: const TrendGoals(),
      );
      expect(r.avgCalories, 2000);
      expect(r.calorieBalance, isNull);
      expect(r.calorieAdherence, isNull);
      expect(r.proteinAdherence, isNull);
    });
  });

  group('History meal times', () {
    test('are derived from the time the meal was logged', () {
      expect(mealPeriodOf(DateTime(2025, 1, 1, 8)), 'breakfast');
      expect(mealPeriodOf(DateTime(2025, 1, 1, 13)), 'lunch');
      expect(mealPeriodOf(DateTime(2025, 1, 1, 16)), 'snack');
      expect(mealPeriodOf(DateTime(2025, 1, 1, 20)), 'dinner');
    });
  });
}
