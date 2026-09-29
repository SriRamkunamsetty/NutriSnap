import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/ai/ai_models.dart';
import 'package:nutrisnap_app/core/database/app_database.dart';
import 'package:nutrisnap_app/core/models/food.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';

import 'support/test_env.dart';

final String kDataset = File('assets/data/foods_in.json').readAsStringSync();

MealItem ai(String name, double kcal, {double w = 100, String id = ''}) => MealItem(
      id: id.isEmpty ? 'i_${name}_$kcal' : id,
      name: name,
      estimatedWeight: w,
      calories: kcal,
      protein: kcal / 20,
      carbs: kcal / 8,
      fats: kcal / 30,
      confidence: 0.8,
      originalName: name,
      originalCalories: kcal,
    );

ScanResult meal(List<MealItem> items, {DateTime? at}) => ScanResult(
      id: '',
      userId: '',
      foodName: MealAnalysisResult.titleOf(items),
      type: 'food',
      calories: 0,
      protein: 0,
      carbs: 0,
      fats: 0,
      confidence: 0.8,
      timestamp: (at ?? DateTime.now()).toIso8601String(),
      items: items,
      modelVersion: 'gemma-4-E2B-it',
    );

MealAnalysisResult analysis(List<MealItem> items) => MealAnalysisResult(
      mealId: 'm',
      detectedItems: items,
      confidence: 0.8,
      timestamp: DateTime.now(),
    );

void main() {
  group('built-in dataset (integrity)', () {
    final data = jsonDecode(kDataset) as Map<String, dynamic>;
    final foods = [for (final j in data['foods'] as List) Food.fromJson(j as Map<String, dynamic>)];

    test('is substantial, uniquely identified, and labelled as approximate', () {
      expect(foods.length, greaterThanOrEqualTo(150));
      expect(foods.map((f) => f.id).toSet().length, foods.length);
      expect(data['source'], contains('approximate'));
      expect(foods.every((f) => f.source == Food.builtInSource), isTrue);
    });

    test('every entry has sane, self-consistent nutrition', () {
      for (final f in foods) {
        expect(f.name.trim(), isNotEmpty);
        expect(f.serving.trim(), isNotEmpty);
        expect(f.servingGrams, greaterThan(0), reason: f.name);
        expect(f.calories, inInclusiveRange(0, 1500), reason: f.name);
        for (final v in [f.protein, f.carbs, f.fats]) {
          expect(v, inInclusiveRange(0, 200), reason: f.name);
        }
        // Calories must roughly agree with 4/4/9 kcal per gram.
        final est = f.protein * 4 + f.carbs * 4 + f.fats * 9;
        if (est > 0) expect((f.calories - est).abs() / est, lessThan(0.35), reason: f.name);
      }
    });

    test('covers the regions the product promises', () {
      for (final tag in ['Andhra', 'Telangana', 'South Indian', 'North Indian', 'Hostel', 'Home Food', 'Snacks', 'Breakfast', 'Lunch', 'Dinner']) {
        expect(foods.any((f) => f.hasTag(tag)), isTrue, reason: 'no $tag foods');
      }
      const mustHave = ['Pappu', 'Pulihora', 'Gongura Pachadi', 'Sambar', 'Rasam', 'Curd Rice', 'Idli', 'Plain Dosa', 'Upma', 'Medu Vada', 'Chicken Curry', 'Potato Fry', 'Andhra Meals (veg)', 'Hyderabadi Dum Biryani'];
      for (final n in mustHave) {
        expect(foods.any((f) => f.name == n), isTrue, reason: 'missing $n');
      }
    });
  });

  group('FoodRepository', () {
    late TestEnv env;
    setUp(() async {
      env = await TestEnv.create();
      await env.foods.ensureSeeded(kDataset);
    });
    tearDown(() async => env.dispose());

    test('seeding is idempotent and preserves usage and custom foods', () async {
      final n = await env.foods.count();
      final idli = (await env.foods.search('idli')).first;
      await env.foods.markUsed(idli.id);
      await env.foods.saveCustom(const Food(
        id: '', name: 'Amma\'s Sambar', serving: '1 bowl', servingGrams: 200,
        calories: 110, protein: 5, carbs: 15, fats: 3,
      ));

      // Re-seed with a newer dataset version.
      final newer = jsonDecode(kDataset) as Map<String, dynamic>..['version'] = 2;
      await env.foods.ensureSeeded(jsonEncode(newer));

      expect(await env.foods.count(), n + 1);
      expect((await env.foods.byId(idli.id))!.useCount, 1);
      expect((await env.foods.custom()).single.name, "Amma's Sambar");
    });

    test('finds foods by name, by alias, and by regional word', () async {
      expect((await env.foods.search('perugu annam')).first.name, 'Curd Rice');
      expect((await env.foods.search('gongura')).first.name, 'Gongura Pachadi');
      expect((await env.foods.search('  IDLY ')).first.name, 'Idli');
      expect(await env.foods.search('zzzzzz'), isEmpty);
    });

    test('exact and prefix matches rank before loose ones', () async {
      final r = await env.foods.search('rice');
      expect(r.first.name.toLowerCase(), contains('rice'));
      final idli = await env.foods.search('idli');
      expect(idli.first.name, 'Idli');
    });

    test('tag filters narrow results and combine with text', () async {
      final andhra = await env.foods.search('', tags: {'Andhra'}, limit: 200);
      expect(andhra, isNotEmpty);
      expect(andhra.every((f) => f.hasTag('Andhra')), isTrue);

      final both = await env.foods.search('', tags: {'Andhra', 'Breakfast'}, limit: 200);
      expect(both.every((f) => f.hasTag('Andhra') && f.hasTag('Breakfast')), isTrue);
      expect(both.length, lessThan(andhra.length));

      final curry = await env.foods.search('curry', tags: {'Telangana'});
      expect(curry.every((f) => f.hasTag('Telangana')), isTrue);
    });

    test('results can be paged', () async {
      final page1 = await env.foods.search('', limit: 20);
      final page2 = await env.foods.search('', limit: 20, offset: 20);
      expect(page1.length, 20);
      expect(page1.map((f) => f.id).toSet().intersection(page2.map((f) => f.id).toSet()), isEmpty);
    });

    test('custom foods: create, edit, appear in search, delete', () async {
      final saved = await env.foods.saveCustom(const Food(
        id: '', name: 'Hostel Egg Fry', aliases: ['mess egg'], tags: ['Hostel'],
        serving: '2 eggs', servingGrams: 120, calories: 230, protein: 14, carbs: 2, fats: 18,
      ));
      expect(saved.isCustom, isTrue);
      expect(saved.id, startsWith('custom_'));
      expect(saved.confidence, 1.0);
      expect((await env.foods.search('mess egg')).first.id, saved.id);

      await env.foods.saveCustom(saved.copyWith(calories: 250));
      expect((await env.foods.byId(saved.id))!.calories, 250);
      expect((await env.foods.custom()).length, 1);

      expect(await env.foods.deleteCustom(saved.id), isTrue);
      expect(await env.foods.byId(saved.id), isNull);
    });

    test('built-in foods cannot be deleted', () async {
      final idli = (await env.foods.search('idli')).first;
      expect(await env.foods.deleteCustom(idli.id), isFalse);
      expect(await env.foods.byId(idli.id), isNotNull);
    });

    test('recent and frequent reflect usage', () async {
      final a = (await env.foods.search('idli')).first;
      final b = (await env.foods.search('sambar')).first;
      await env.foods.markUsed(a.id);
      await env.foods.markUsed(b.id);
      await env.foods.markUsed(b.id);
      expect((await env.foods.frequent()).first.id, b.id);
      expect((await env.foods.recent()).first.id, b.id);
    });

    test('findByName matches exact names and aliases only', () async {
      expect((await env.foods.findByName('Curd Rice'))?.name, 'Curd Rice');
      expect((await env.foods.findByName('thayir sadam'))?.name, 'Curd Rice');
      expect(await env.foods.findByName('rice'), isNull, reason: '"rice" alone is not an exact food name here');
    });
  });

  group('Food Twin', () {
    late TestEnv env;
    setUp(() async {
      env = await TestEnv.create();
      await env.foods.ensureSeeded(kDataset);
    });
    tearDown(() async => env.dispose());

    /// Logs a meal in which the user changed the AI's estimate.
    Future<ScanResult> correctedMeal({required double aiKcal, required double userKcal, String name = 'Chicken Biryani', String? renamedTo}) async {
      final item = ai(name, aiKcal).copyWith(calories: userKcal, name: renamedTo ?? name, id: 'i${DateTime.now().microsecondsSinceEpoch}');
      final saved = await env.scans.add(meal([item]));
      await env.twin.recordMeal(saved);
      return saved;
    }

    test('a fresh Food Twin has learned nothing and invents no accuracy', () async {
      final p = await env.twin.profile();
      expect(p.hasLearned, isFalse);
      expect(p.foodsLearned, 0);
      expect(p.personalAccuracy, isNull);
      expect(p.correctionHistory, isEmpty);
    });

    test('foods learned and frequent foods come from real meals', () async {
      for (var i = 0; i < 3; i++) {
        await env.scans.add(meal([ai('Idli', 130, w: 2), ai('Sambar', 85, w: 150)]));
      }
      await env.scans.add(meal([ai('Pulihora', 300, w: 180)]));
      final p = await env.twin.profile();
      expect(p.foodsLearned, 3);
      expect(p.frequentlyUsedFoods.first.count, 3);
      expect(p.frequentlyUsedFoods.map((f) => f.name), containsAll(['Idli', 'Sambar']));
      expect(p.preferredPortions['Idli'], '2 g'); // typical amount + unit
    });

    test('personal accuracy needs 5+ AI foods, then reflects unchanged ones', () async {
      for (var i = 0; i < 4; i++) {
        await env.scans.add(meal([ai('Dosa$i', 130)]));
      }
      expect((await env.twin.profile()).personalAccuracy, isNull);

      await env.scans.add(meal([ai('Dosa4', 130)]));
      expect((await env.twin.profile()).personalAccuracy, 1.0);

      // The user changes one of the six AI foods.
      final changed = ai('Upma', 230).copyWith(calories: 300);
      await env.scans.add(meal([changed]));
      final p = await env.twin.profile();
      expect(p.aiItemsCount, 6);
      expect(p.personalAccuracy, closeTo(5 / 6, 0.001));
    });

    test('a correction is recorded once, even if the meal is saved again', () async {
      final saved = await correctedMeal(aiKcal: 650, userKcal: 500);
      await env.twin.recordMeal(saved);
      await env.twin.recordMeal(saved);
      final c = (await env.twin.profile()).correctionHistory;
      expect(c.length, 1);
      expect(c.single.originalKcal, 650);
      expect(c.single.correctedKcal, 500);
    });

    test('one correction is not enough to change future predictions', () async {
      await correctedMeal(aiKcal: 650, userKcal: 500);
      final out = await env.twin.personalize(analysis([ai('Chicken Biryani', 650)]));
      expect(out.detectedItems.single.calories, 650);
      expect(out.detectedItems.single.note, isNull);
    });

    test('repeated consistent corrections adjust the next estimate and explain why', () async {
      await correctedMeal(aiKcal: 650, userKcal: 500);
      await correctedMeal(aiKcal: 640, userKcal: 500);
      final out = await env.twin.personalize(analysis([ai('Chicken Biryani', 650)]));
      final item = out.detectedItems.single;
      expect(item.calories, lessThan(600));
      expect(item.calories, greaterThan(480));
      expect(item.note, contains('2 of your earlier corrections'));
      // The adjusted number is the new baseline: accepting it is NOT a correction.
      expect(item.wasCorrected, isFalse);
    });

    test('inconsistent corrections are ignored', () async {
      await correctedMeal(aiKcal: 650, userKcal: 300);
      await correctedMeal(aiKcal: 650, userKcal: 900);
      final out = await env.twin.personalize(analysis([ai('Chicken Biryani', 650)]));
      expect(out.detectedItems.single.calories, 650);
    });

    test('a repeated rename becomes the default name (personal alias)', () async {
      await correctedMeal(aiKcal: 550, userKcal: 550, renamedTo: 'Hyderabadi Dum Biryani');
      await correctedMeal(aiKcal: 550, userKcal: 550, renamedTo: 'Hyderabadi Dum Biryani');
      final out = await env.twin.personalize(analysis([ai('Chicken Biryani', 550)]));
      expect(out.detectedItems.single.name, 'Hyderabadi Dum Biryani');
      expect(out.detectedItems.single.note, contains('you usually call it this'));
      expect((await env.twin.profile()).aliases['Chicken Biryani'], 'Hyderabadi Dum Biryani');
    });

    test('unrelated foods are left alone', () async {
      await correctedMeal(aiKcal: 650, userKcal: 500);
      await correctedMeal(aiKcal: 640, userKcal: 500);
      final out = await env.twin.personalize(analysis([ai('Idli', 130)]));
      expect(out.detectedItems.single.calories, 130);
    });

    test('non-food results are never touched', () async {
      final a = MealAnalysisResult(mealId: 'm', detectedItems: const [], type: 'animal', confidence: 0.9, timestamp: DateTime.now());
      expect(await env.twin.personalize(a), a);
    });

    test('deleting a meal removes its corrections and its statistics', () async {
      final saved = await correctedMeal(aiKcal: 650, userKcal: 500);
      expect((await env.twin.profile()).correctionHistory.length, 1);
      await env.scans.delete(saved.id);
      final p = await env.twin.profile();
      expect(p.correctionHistory, isEmpty);
      expect(p.foodsLearned, 0);
    });

    test('editing a meal replaces its earlier corrections instead of adding to them', () async {
      final saved = await correctedMeal(aiKcal: 650, userKcal: 500);
      final restored = saved.copyWith(items: [saved.items.first.copyWith(calories: 650)]); // user undid the change
      await env.twin.recordMeal(restored);
      expect((await env.twin.profile()).correctionHistory, isEmpty);
    });

    test('regional preferences come from foods the library recognises', () async {
      await env.scans.add(meal([ai('Pappu', 150, w: 150), ai('Gongura Pachadi', 45, w: 20)]));
      await env.scans.add(meal([ai('Pappu', 150, w: 150)]));
      final p = await env.twin.profile();
      expect(p.regionalPreferences['Andhra'], 3);
      expect(p.regionalPreferences['Telangana'], 3);
      expect(p.regionalPreferences.containsKey('North Indian'), isFalse);
    });

    test('custom foods are part of the profile', () async {
      await env.foods.saveCustom(const Food(id: '', name: 'Amma Pulusu', serving: '1 bowl', servingGrams: 200, calories: 120, protein: 4, carbs: 15, fats: 4));
      expect((await env.twin.profile()).customFoods.single.name, 'Amma Pulusu');
    });

    test('reset forgets corrections and usage but keeps meals and built-in foods', () async {
      final idli = (await env.foods.search('idli')).first;
      await env.foods.markUsed(idli.id);
      await env.foods.saveCustom(const Food(id: '', name: 'X', serving: '1', servingGrams: 100, calories: 100, protein: 1, carbs: 10, fats: 1));
      await correctedMeal(aiKcal: 650, userKcal: 500);

      await env.twin.reset();

      final p = await env.twin.profile();
      expect(p.correctionHistory, isEmpty);
      expect(p.customFoods, isEmpty);
      expect((await env.foods.byId(idli.id))!.useCount, 0);
      expect((await env.scans.all()).length, 1, reason: 'meals are not part of the Food Twin');
      expect(await env.foods.count(), greaterThan(150));
    });

    test('the coach summary is empty until something is learned, then factual', () async {
      expect(await env.twin.promptSummary(), '');
      for (var i = 0; i < 2; i++) {
        await env.scans.add(meal([ai('Pappu', 150, w: 150)]));
      }
      final s = await env.twin.promptSummary();
      expect(s, contains('Pappu'));
      expect(s, contains('Andhra'));
    });
  });

  group('migration v4', () {
    test('a fresh database has the food tables', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final tables = (await env.db.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
      expect(tables, containsAll([Tables.foods, Tables.foodCorrections]));
      expect(AppDatabase.schemaVersion, greaterThanOrEqualTo(4));
    });
  });
}
