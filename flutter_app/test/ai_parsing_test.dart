import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/ai/ai_models.dart';
import 'package:nutrisnap_app/core/ai/ai_parsing.dart';
import 'package:nutrisnap_app/core/enums/app_enums.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';

void main() {
  group('extractJsonObject', () {
    test('plain JSON', () {
      expect(AiParsing.extractJsonObject('{"a": 1}'), {'a': 1});
    });

    test('strips code fences and surrounding prose', () {
      const raw = 'Sure! Here you go:\n```json\n{"foodName": "Dosa", "calories": 300}\n```\nEnjoy.';
      expect(AiParsing.extractJsonObject(raw)?['foodName'], 'Dosa');
    });

    test('braces inside strings do not confuse the matcher', () {
      final m = AiParsing.extractJsonObject('{"description": "a } b { c", "x": 2}');
      expect(m?['x'], 2);
    });

    test('returns null for garbage or truncated JSON', () {
      expect(AiParsing.extractJsonObject('no json here'), isNull);
      expect(AiParsing.extractJsonObject('{"a": 1'), isNull);
    });
  });

  group('parseMeal', () {
    const plate = '''
{"type":"food","description":"A thali","confidence":0.82,"items":[
 {"name":"Chicken Curry","category":"curry","weightGrams":180,"servingUnit":"g","calories":320,"protein":28,"carbs":8,"fats":20,"confidence":0.85},
 {"name":"Steamed Rice","category":"rice","weightGrams":200,"servingUnit":"g","calories":260,"protein":5,"carbs":57,"fats":0.5,"confidence":0.9},
 {"name":"Onion Salad","category":"salad","weightGrams":60,"servingUnit":"g","calories":25,"protein":1,"carbs":6,"fats":0,"confidence":0.7},
 {"name":"Curd","category":"dairy","weightGrams":100,"servingUnit":"g","calories":60,"protein":3.5,"carbs":4.7,"fats":3.3,"confidence":0.8}
]}''';

    test('detects several foods in one photo and sums them', () {
      final m = AiParsing.parseMeal(plate);
      expect(m.detectedItems.map((i) => i.name), ['Chicken Curry', 'Steamed Rice', 'Onion Salad', 'Curd']);
      expect(m.estimatedTotalCalories, 665);
      expect(m.estimatedProtein, 38); // 28+5+1+3.5 = 37.5 -> 38
      expect(m.title, 'Chicken Curry, Steamed Rice + 2 more');
      expect(m.isFood, isTrue);
      expect(m.analysisStatus, 'pending'); // a proposal, never auto-saved
      expect(m.mealId, startsWith('meal_'));
    });

    test('every item remembers what the AI originally said (for later learning)', () {
      final m = AiParsing.parseMeal(plate);
      expect(m.detectedItems.first.originalName, 'Chicken Curry');
      expect(m.detectedItems.first.originalCalories, 320);
      expect(m.detectedItems.first.wasCorrected, isFalse);
      expect(m.detectedItems.first.copyWith(calories: 250).wasCorrected, isTrue);
    });

    test('overall confidence is calorie-weighted and within 0..1', () {
      final m = AiParsing.parseMeal(plate);
      expect(m.confidence, inInclusiveRange(0.0, 1.0));
      expect(m.confidence, greaterThan(0.7));
    });

    test('still understands the older single-food answer', () {
      final m = AiParsing.parseMeal(
          '{"foodName":"Paneer Butter Masala","type":"food","calories":520,"protein":24,"carbs":30,"fats":34,"confidence":0.82}');
      expect(m.detectedItems.single.name, 'Paneer Butter Masala');
      expect(m.estimatedTotalCalories, 520);
    });

    test('numbers given as strings and percentage confidence are normalised', () {
      final m = AiParsing.parseMeal(
          '{"type":"food","items":[{"name":"Apple","weightGrams":"150 g","calories":"95 kcal","protein":"0.5","carbs":"25","fats":"0.3","confidence":90}]}');
      final i = m.detectedItems.single;
      expect(i.estimatedWeight, 150);
      expect(i.calories, 95);
      expect(i.confidence, 0.9);
    });

    test('non-food yields no items and zero nutrition', () {
      final m = AiParsing.parseMeal('{"type":"animal","description":"A dog","items":[]}');
      expect(m.isFood, isFalse);
      expect(m.detectedItems, isEmpty);
      expect(m.estimatedTotalCalories, 0);
    });

    test('calories that contradict the macros are repaired and confidence drops', () {
      final m = AiParsing.parseMeal(
          '{"type":"food","items":[{"name":"Snack","weightGrams":50,"calories":900,"protein":10,"carbs":10,"fats":10,"confidence":0.9}]}');
      expect(m.detectedItems.single.calories, 170); // 10*4 + 10*4 + 10*9
      expect(m.detectedItems.single.confidence, lessThan(0.9));
    });

    test('a missing portion is defaulted honestly and confidence is reduced', () {
      final m = AiParsing.parseMeal(
          '{"type":"food","items":[{"name":"Soup","calories":100,"protein":5,"carbs":10,"fats":4,"confidence":0.8}]}');
      expect(m.detectedItems.single.estimatedWeight, 100);
      expect(m.detectedItems.single.confidence, lessThan(0.8));
    });

    test('absurd values are clamped and negatives become zero', () {
      final m = AiParsing.parseMeal(
          '{"type":"food","items":[{"name":"Wat","weightGrams":99999999,"calories":9999999,"protein":99999,"carbs":-4,"fats":99999,"confidence":1}]}');
      final i = m.detectedItems.single;
      expect(i.calories, lessThanOrEqualTo(3000));
      expect(i.protein, lessThanOrEqualTo(300));
      expect(i.carbs, 0);
      expect(i.estimatedWeight, lessThanOrEqualTo(5000));
    });

    test('unnamed items are dropped; a plate of nothing is an error', () {
      final m = AiParsing.parseMeal(
          '{"type":"food","items":[{"name":"  ","calories":50},{"name":"Tea","weightGrams":200,"servingUnit":"ml","calories":40,"protein":1,"carbs":6,"fats":1,"confidence":0.8}]}');
      expect(m.detectedItems.single.name, 'Tea');
      expect(m.detectedItems.single.servingUnit, 'ml');
      expect(() => AiParsing.parseMeal('{"type":"food","items":[]}'), throwsA(isA<AiException>()));
      expect(() => AiParsing.parseMeal('I cannot help'), throwsA(isA<AiException>()));
    });

    test('the number of items is capped', () {
      final items = List.generate(30, (i) => '{"name":"Food $i","weightGrams":10,"calories":10,"protein":1,"carbs":1,"fats":0}').join(',');
      expect(AiParsing.parseMeal('{"type":"food","items":[$items]}').detectedItems.length, AiParsing.maxItems);
    });

    test('low confidence flags the result for review', () {
      final sure = AiParsing.parseMeal(plate);
      expect(sure.needsReview, isFalse);
      final unsure = AiParsing.parseMeal(
          '{"type":"food","confidence":0.4,"items":[{"name":"Mystery stew","weightGrams":200,"calories":300,"protein":15,"carbs":30,"fats":12,"confidence":0.35}]}');
      expect(unsure.needsReview, isTrue);
    });

    test('unknown serving units fall back to grams; synonyms are understood', () {
      expect(ServingUnit.normalize('grams'), 'g');
      expect(ServingUnit.normalize('pcs'), 'piece');
      expect(ServingUnit.normalize('bananas'), 'g');
      expect(ServingUnit.normalize(null), 'g');
    });
  });

  group('parseBody', () {
    test('valid', () {
      final b = AiParsing.parseBody('{"bodyType":"lean","fatEstimate":14.26,"observations":"Athletic build"}');
      expect(b.bodyType, BodyType.lean);
      expect(b.fatEstimate, 14.3);
    });

    test('body fat is clamped to a sane range', () {
      expect(AiParsing.parseBody('{"bodyType":"normal","fatEstimate":95}').fatEstimate, 60.0);
      expect(AiParsing.parseBody('{"bodyType":"normal","fatEstimate":0.5}').fatEstimate, 3.0);
    });

    test('missing estimate is an error', () {
      expect(() => AiParsing.parseBody('{"bodyType":"lean"}'), throwsA(isA<AiException>()));
    });
  });

  group('coach reply', () {
    test('splits answer and suggestions', () {
      const raw = 'Eat more protein.\n\nSUGGESTIONS: What is a high protein snack? | Plan my dinner | How much water?';
      final r = AiParsing.parseCoachReply(raw);
      expect(r.text, 'Eat more protein.');
      expect(r.suggestions, ['What is a high protein snack?', 'Plan my dinner', 'How much water?']);
    });

    test('no marker means no suggestions', () {
      final r = AiParsing.parseCoachReply('Just an answer');
      expect(r.text, 'Just an answer');
      expect(r.suggestions, isEmpty);
    });

    test('a half-streamed marker is hidden from the visible text', () {
      expect(AiParsing.visibleCoachText('Answer\nSUGGESTIONS: a | b'), 'Answer');
    });

    test('at most three suggestions', () {
      final r = AiParsing.parseCoachReply('x\nSUGGESTIONS: a | b | c | d | e');
      expect(r.suggestions.length, 3);
    });

    test('markdown is stripped for plain-text display', () {
      expect(AiParsing.stripMarkdown('## Title\n**bold** and `code`\n* item'),
          'Title\nbold and code\n• item');
    });
  });
}
