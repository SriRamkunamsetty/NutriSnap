import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/ai/ai_models.dart';
import 'package:nutrisnap_app/core/ai/ai_parsing.dart';
import 'package:nutrisnap_app/core/ai/nutrition_ai.dart';
import 'package:nutrisnap_app/core/models/chat_message.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/models/mess.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/models/user_profile.dart';
import 'package:nutrisnap_app/core/services/mess_service.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';

import 'support/test_env.dart';

class FakeAi implements NutritionAi {
  List<DishEstimate> estimates = [];
  bool fail = false;
  List<String> asked = [];

  @override
  Future<List<DishEstimate>> estimateDishes(List<String> dishNames) async {
    asked = dishNames;
    if (fail) throw AiException('boom');
    return estimates;
  }

  @override
  Future<MealAnalysisResult> analyzeMeal(Uint8List image) => throw UnimplementedError();
  @override
  Future<BodyAnalysis> analyzeBody(Uint8List image, {UserProfile? profile}) => throw UnimplementedError();
  @override
  CoachStream coach({
    required String message,
    required List<ChatMessage> history,
    required String briefing,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> unload() async {}
}

final kDataset = File('assets/data/foods_in.json').readAsStringSync();

void main() {
  group('MessMenuParser', () {
    test('splits dishes on commas, plus, ampersand, "and", slashes and bullets', () {
      expect(MessMenuParser.splitDishes('Idli, Sambar + Chutney & Vada and Pongal'),
          ['Idli', 'Sambar', 'Chutney', 'Vada', 'Pongal']);
      expect(MessMenuParser.splitDishes('• Rice\n• dal fry\n2. curd'), ['Rice', 'Dal fry', 'Curd']);
    });

    test('drops empties, over-long junk and duplicates', () {
      expect(MessMenuParser.splitDishes('idli,, IDLI ,  ,${'x' * 80}'), ['Idli']);
    });

    test('reads a pasted full-day menu with mixed header styles', () {
      final m = MessMenuParser.parse('''
Breakfast: Idli, Sambar, Chutney
Lunch - Rice, Dal, Chicken Curry, Curd
Snacks: Samosa + Tea
Dinner
Chapati
Paneer Curry
''');
      expect(m.meals[MealType.breakfast], ['Idli', 'Sambar', 'Chutney']);
      expect(m.meals[MealType.lunch], ['Rice', 'Dal', 'Chicken Curry', 'Curd']);
      expect(m.meals[MealType.snacks], ['Samosa', 'Tea']);
      expect(m.meals[MealType.dinner], ['Chapati', 'Paneer Curry']);
      expect(m.unassigned, isEmpty);
    });

    test('understands tiffin / supper / evening synonyms and case', () {
      final m = MessMenuParser.parse('TIFFIN: upma\nEvening snacks: bajji\nSUPPER: khichdi');
      expect(m.meals[MealType.breakfast], ['Upma']);
      expect(m.meals[MealType.snacks], ['Bajji']);
      expect(m.meals[MealType.dinner], ['Khichdi']);
    });

    test('text before any header is kept aside, not guessed', () {
      final m = MessMenuParser.parse('Idli, Vada\nLunch: Rice');
      expect(m.unassigned, ['Idli', 'Vada']);
      expect(m.meals[MealType.lunch], ['Rice']);
    });

    test('garbage and empty input parse to nothing', () {
      expect(MessMenuParser.parse('').isEmpty, isTrue);
      expect(MessMenuParser.parse('   \n \n').isEmpty, isTrue);
    });
  });

  group('AI dish estimate parsing', () {
    test('maps results back to the requested names and caps confidence', () {
      final out = AiParsing.parseDishEstimates(
          '{"items":[{"name":"Egg Fry","serving":"2 eggs","calories":230,"protein":14,"carbs":2,"fats":18,"confidence":0.95}]}',
          ['Egg Fry']);
      expect(out.single.name, 'Egg Fry');
      expect(out.single.confidence, lessThanOrEqualTo(0.7), reason: 'a text-only guess is never confident');
    });

    test('repairs contradictory calories and drops empty estimates', () {
      final out = AiParsing.parseDishEstimates(
          '{"items":[{"name":"A","calories":900,"protein":10,"carbs":10,"fats":10},{"name":"B","calories":0,"protein":0,"carbs":0,"fats":0}]}',
          ['A', 'B']);
      expect(out.length, 1);
      expect(out.single.calories, 170);
    });

    test('a dish the model skipped is simply absent', () {
      final out = AiParsing.parseDishEstimates(
          '{"items":[{"name":"Pongal","calories":280,"protein":7,"carbs":38,"fats":9}]}', ['Pongal', 'Mystery']);
      expect(out.map((e) => e.name), ['Pongal']);
    });

    test('unreadable output is an error', () {
      expect(() => AiParsing.parseDishEstimates('nope', ['A']), throwsA(isA<AiException>()));
    });
  });

  group('MessNutritionEstimate', () {
    test('sums known dishes, ignores unknown ones, and says so', () {
      final e = MessNutritionEstimate.of(const [
        MessDish(name: 'Rice', servings: 1.5, calories: 200, protein: 4, carbs: 45, fats: 0.5, source: DishSource.library, confidence: 0.8),
        MessDish(name: 'Mystery'),
      ]);
      expect(e.calories, 300);
      expect(e.protein, 6);
      expect(e.knownCount, 1);
      expect(e.unknownDishes, ['Mystery']);
      expect(e.isComplete, isFalse);
      expect(e.confidence, closeTo(0.4, 0.001), reason: 'discounted for the dish we know nothing about');
    });

    test('an empty meal is empty, not zero-calorie', () {
      expect(MessNutritionEstimate.of(const []).isEmpty, isTrue);
    });
  });

  group('MessService', () {
    late TestEnv env;
    late FakeAi ai;
    late Mess mess;
    setUp(() async {
      env = await TestEnv.create();
      await env.foods.ensureSeeded(kDataset);
      ai = FakeAi();
      mess = await env.messes.createMess(college: 'JNTU', hostel: 'Block A', name: 'Main Mess');
    });
    tearDown(() async => env.dispose());

    test('matches library foods by name, alias and close name; unknowns stay unknown', () async {
      final dishes = await env.mess.match(['Idli', 'Perugu Annam', 'Rice', 'Zorba the Greek']);
      expect(dishes[0].source, DishSource.library);
      expect(dishes[0].calories, 130);
      expect(dishes[1].name, 'Perugu Annam'); // keeps the menu's wording
      expect(dishes[1].calories, 250); // = Curd Rice
      expect(dishes[2].source, DishSource.library); // "Rice" ~ "Steamed Rice"
      expect(dishes[2].confidence, lessThan(dishes[0].confidence), reason: 'a fuzzy match is trusted less');
      expect(dishes[3].needsEstimate, isTrue);
      expect(dishes[3].calories, 0);
    });

    test('never overwrites a dish the user or AI already settled', () async {
      final settled = MessDish(name: 'Idli', calories: 999, source: DishSource.manual, confidence: 1);
      final out = await env.mess.match(['Idli', 'Sambar'], keep: [settled]);
      expect(out[0].calories, 999);
      expect(out[1].source, DishSource.library);
    });

    test('on-device AI fills only the unknown dishes', () async {
      final dishes = await env.mess.match(['Idli', 'Hostel Egg Fry']);
      ai.estimates = const [
        DishEstimate(name: 'Hostel Egg Fry', serving: '2 eggs', calories: 230, protein: 14, carbs: 2, fats: 18, confidence: 0.5),
      ];
      final filled = await env.mess.fillWithAi(dishes, ai);
      expect(ai.asked, ['Hostel Egg Fry']);
      expect(filled[0].source, DishSource.library);
      expect(filled[1].source, DishSource.ai);
      expect(filled[1].calories, 230);
      expect(filled[1].confidence, 0.5);
    });

    test('when the AI has nothing to say, dishes stay unknown (nothing invented)', () async {
      final dishes = await env.mess.match(['Hostel Egg Fry']);
      final filled = await env.mess.fillWithAi(dishes, ai..estimates = []);
      expect(filled.single.needsEstimate, isTrue);
    });

    test('a failing AI is surfaced to the caller instead of being swallowed', () async {
      final dishes = await env.mess.match(['Hostel Egg Fry']);
      await expectLater(env.mess.fillWithAi(dishes, ai..fail = true), throwsA(isA<AiException>()));
    });

    test('does not call the AI when every dish is known', () async {
      final dishes = await env.mess.match(['Idli', 'Sambar']);
      await env.mess.fillWithAi(dishes, ai);
      expect(ai.asked, isEmpty);
    });

    Future<MessMeal> lunch(List<String> names, {String? date}) async {
      final d = date ?? DateTimeUtils.today();
      final dishes = await env.mess.match(names);
      return (await env.messes.saveMeal(messId: mess.id, date: d, mealType: MealType.lunch, dishes: dishes))!;
    }

    test('one-tap logging adds a real diary entry and marks the meal logged', () async {
      final meal = await lunch(['Steamed Rice', 'Dal Tadka', 'Curd']);
      final saved = await env.mess.logMeal(meal, mess, menuDate: DateTimeUtils.today());

      expect(saved.items.map((i) => i.name), ['Steamed Rice', 'Dal Tadka', 'Curd']);
      expect(saved.calories, 208 + 160 + 60);
      expect(saved.foodName, 'Lunch · Main Mess');
      expect(saved.analysisStatus, AnalysisStatus.manual);
      expect(saved.items.every((i) => i.source == ItemSource.library), isTrue);
      expect((await env.summaries.forDate(DateTimeUtils.today())).totalCalories, 428);

      final reloaded = (await env.messes.menu(mess.id, DateTimeUtils.today()))!.meal(MealType.lunch)!;
      expect(reloaded.isLogged, isTrue);
      expect(reloaded.loggedScanId, saved.id);
      expect((await env.foods.findByName('Curd'))!.useCount, 1);
    });

    test('portion eaten scales what is logged', () async {
      final base = await env.mess.match(['Steamed Rice']);
      final meal = (await env.messes.saveMeal(
        messId: mess.id, date: DateTimeUtils.today(), mealType: MealType.lunch,
        dishes: [base.single.copyWith(servings: 2)],
      ))!;
      final saved = await env.mess.logMeal(meal, mess, menuDate: DateTimeUtils.today());
      expect(saved.calories, 416);
    });

    test('a meal cannot be logged twice, and undo makes it loggable again', () async {
      final meal = await lunch(['Idli']);
      await env.mess.logMeal(meal, mess, menuDate: DateTimeUtils.today());
      final logged = (await env.messes.menu(mess.id, DateTimeUtils.today()))!.meal(MealType.lunch)!;
      await expectLater(env.mess.logMeal(logged, mess, menuDate: DateTimeUtils.today()), throwsStateError);

      await env.mess.unlogMeal(logged);
      expect(await env.scans.all(), isEmpty);
      expect((await env.summaries.forDate(DateTimeUtils.today())).totalCalories, 0);
      final freed = (await env.messes.menu(mess.id, DateTimeUtils.today()))!.meal(MealType.lunch)!;
      expect(freed.isLogged, isFalse);
      await env.mess.logMeal(freed, mess, menuDate: DateTimeUtils.today()); // works again
    });

    test('unknown dishes are left out of the log, and nothing known means nothing logged', () async {
      final mixed = await lunch(['Idli', 'Zorba the Greek']);
      final saved = await env.mess.logMeal(mixed, mess, menuDate: DateTimeUtils.today());
      expect(saved.items.map((i) => i.name), ['Idli']);

      final none = (await env.messes.saveMeal(
        messId: mess.id, date: DateTimeUtils.today(), mealType: MealType.dinner,
        dishes: await env.mess.match(['Zorba the Greek']),
      ))!;
      await expectLater(env.mess.logMeal(none, mess, menuDate: DateTimeUtils.today()), throwsStateError);
    });

    test('logging a past day files it under that day at a sensible time', () async {
      final meal = await lunch(['Idli'], date: '2025-02-10');
      final saved = await env.mess.logMeal(meal, mess, menuDate: '2025-02-10', now: DateTime(2025, 3, 1, 9));
      final at = DateTime.parse(saved.timestamp);
      expect(DateTimeUtils.dayKey(at), '2025-02-10');
      expect(at.hour, 13);
    });

    test('deleting the diary entry elsewhere frees the mess meal (no dangling link)', () async {
      final meal = await lunch(['Idli']);
      final saved = await env.mess.logMeal(meal, mess, menuDate: DateTimeUtils.today());
      await env.scans.delete(saved.id);
      final after = (await env.messes.menu(mess.id, DateTimeUtils.today()))!.meal(MealType.lunch)!;
      expect(after.isLogged, isFalse);
    });

    test('AI-estimated mess numbers do not count as photo predictions', () async {
      final d = MessDish(name: 'Egg Fry', calories: 230, protein: 14, carbs: 2, fats: 18, source: DishSource.ai, confidence: 0.5);
      final meal = (await env.messes.saveMeal(messId: mess.id, date: DateTimeUtils.today(), mealType: MealType.dinner, dishes: [d]))!;
      final saved = await env.mess.logMeal(meal, mess, menuDate: DateTimeUtils.today());
      expect(saved.items.single.source, ItemSource.manual);
      expect((await env.twin.profile()).aiItemsCount, 0);
    });
  });

  group('MessRepository', () {
    late TestEnv env;
    late Mess mess;
    setUp(() async {
      env = await TestEnv.create();
      mess = await env.messes.createMess(college: 'JNTU', hostel: 'Block A', name: 'Main Mess');
    });
    tearDown(() async => env.dispose());

    const idli = MessDish(name: 'Idli', calories: 130, source: DishSource.library, confidence: 0.8);
    const rice = MessDish(name: 'Rice', calories: 208, source: DishSource.library, confidence: 0.8);

    test('the first mess becomes active; you can add and switch', () async {
      expect((await env.messes.active())!.id, mess.id);
      final b = await env.messes.createMess(college: 'JNTU', hostel: 'Block B', name: 'North Mess');
      expect((await env.messes.active())!.id, b.id, reason: 'a newly created mess is selected');
      await env.messes.setActive(mess.id);
      expect((await env.messes.active())!.id, mess.id);
      expect((await env.messes.messes()).length, 2);
      expect(mess.subtitle, 'JNTU · Block A');
    });

    test('menus are stored per date and per meal, in meal order', () async {
      await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.dinner, dishes: [rice]);
      await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.breakfast, dishes: [idli]);
      await env.messes.saveMeal(messId: mess.id, date: '2025-03-04', mealType: MealType.lunch, dishes: [rice]);

      final m = (await env.messes.menu(mess.id, '2025-03-03'))!;
      expect(m.meals.map((x) => x.mealType), [MealType.breakfast, MealType.dinner]);
      expect(m.meal(MealType.breakfast)!.dishes.single.name, 'Idli');
      expect(await env.messes.menu(mess.id, '2025-03-09'), isNull);
    });

    test('editing a meal keeps its logged link; an empty list clears the meal', () async {
      final meal = (await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.lunch, dishes: [rice]))!;
      final scan = await env.scans.add(const ScanResult(
        id: '', userId: '', foodName: 'x', type: 'food', calories: 100, protein: 1, carbs: 1, fats: 1,
        confidence: 1, timestamp: '2025-03-03T13:00:00.000',
      ));
      await env.messes.setLogged(meal.id, scan.id);

      final edited = (await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.lunch, dishes: [rice, idli]))!;
      expect(edited.id, meal.id);
      expect(edited.loggedScanId, scan.id);

      await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.lunch, dishes: []);
      expect((await env.messes.menu(mess.id, '2025-03-03'))!.meals, isEmpty);
    });

    test('menu history lists dates newest first', () async {
      for (final d in ['2025-03-01', '2025-03-05', '2025-03-03']) {
        await env.messes.saveMeal(messId: mess.id, date: d, mealType: MealType.lunch, dishes: [rice]);
      }
      expect(await env.messes.menuDates(mess.id), ['2025-03-05', '2025-03-03', '2025-03-01']);
    });

    test('copying a menu duplicates the dishes but not the logged state', () async {
      final meal = (await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.lunch, dishes: [rice, idli]))!;
      await env.messes.setLogged(meal.id, null);
      expect(await env.messes.copyMenu(mess.id, '2025-03-03', '2025-03-10'), 1);
      final copy = (await env.messes.menu(mess.id, '2025-03-10'))!.meal(MealType.lunch)!;
      expect(copy.dishes.map((d) => d.name), ['Rice', 'Idli']);
      expect(copy.isLogged, isFalse);
      expect(await env.messes.copyMenu(mess.id, '2025-01-01', '2025-03-11'), 0);
    });

    test('suggests the same weekday last week, else the latest earlier day', () async {
      await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.lunch, dishes: [rice]);
      await env.messes.saveMeal(messId: mess.id, date: '2025-03-05', mealType: MealType.lunch, dishes: [rice]);
      final svc = MessService(foods: env.foods, messes: env.messes, scans: env.scans);
      expect(await svc.suggestCopySource(mess.id, '2025-03-10'), '2025-03-03'); // a week earlier
      expect(await svc.suggestCopySource(mess.id, '2025-03-08'), '2025-03-05'); // latest earlier
      expect(await svc.suggestCopySource(mess.id, '2025-03-01'), isNull);
    });

    test('deleting a mess removes its menus but not the diary entries already logged', () async {
      final meal = (await env.messes.saveMeal(messId: mess.id, date: '2025-03-03', mealType: MealType.lunch, dishes: [rice]))!;
      final scan = await env.scans.add(const ScanResult(
        id: '', userId: '', foodName: 'Lunch', type: 'food', calories: 200, protein: 4, carbs: 45, fats: 1,
        confidence: 1, timestamp: '2025-03-03T13:00:00.000',
      ));
      await env.messes.setLogged(meal.id, scan.id);

      await env.messes.deleteMess(mess.id);
      expect(await env.messes.menu(mess.id, '2025-03-03'), isNull);
      expect(await env.messes.active(), isNull);
      expect((await env.scans.all()).length, 1);
    });
  });
}
