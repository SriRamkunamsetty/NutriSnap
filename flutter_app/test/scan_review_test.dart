import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nutrisnap_app/core/ai/ai_models.dart';
import 'package:nutrisnap_app/core/ai/nutrition_ai.dart';
import 'package:nutrisnap_app/core/models/chat_message.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/models/user_profile.dart';
import 'package:nutrisnap_app/core/providers/app_providers.dart';
import 'package:nutrisnap_app/features/scan/screens/scan_review_screen.dart';

import 'support/test_env.dart';

/// 1x1 transparent PNG.
final Uint8List kPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59, 0xE7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeAi implements NutritionAi {
  MealAnalysisResult? next;
  int calls = 0;

  @override
  Future<MealAnalysisResult> analyzeMeal(Uint8List image) async {
    calls++;
    return next!;
  }

  @override
  Future<BodyAnalysis> analyzeBody(Uint8List image, {UserProfile? profile}) => throw UnimplementedError();

  @override
  Future<List<DishEstimate>> estimateDishes(List<String> dishNames) async => const [];

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

MealItem food(String name, double kcal, {double conf = 0.9, double w = 100}) => MealItem(
      id: 'item_$name',
      name: name,
      estimatedWeight: w,
      calories: kcal,
      protein: 10,
      carbs: 20,
      fats: 5,
      confidence: conf,
      originalName: name,
      originalCalories: kcal,
    );

MealAnalysisResult analysis(List<MealItem> items, {double confidence = 0.9, String type = 'food'}) =>
    MealAnalysisResult(
      mealId: 'meal_1',
      detectedItems: items,
      type: type,
      description: type == 'food' ? '' : 'A golden retriever',
      confidence: confidence,
      timestamp: DateTime(2025, 3, 1, 13),
      modelVersion: 'gemma-4-E2B-it',
    );

void main() {
  late TestEnv env;
  late FakeAi ai;

  setUp(() async {
    env = await TestEnv.create();
    ai = FakeAi();
  });
  tearDown(() async => env.dispose());

  Future<void> open(WidgetTester tester, MealAnalysisResult result) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (c, s) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => c.push<String>('/review',
                    extra: ScanReviewArgs.newMeal(analysis: result, imageBytes: kPng)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/review',
          builder: (c, s) => ScanReviewScreen(args: s.extra as ScanReviewArgs),
        ),
        GoRoute(path: '/result/:id', builder: (c, s) => const Scaffold(body: Text('RESULT PAGE'))),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(env.db),
        imageStoreProvider.overrideWithValue(env.images),
        nutritionAiProvider.overrideWithValue(ai),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Lets real async work (SQLite, file IO) finish, then rebuilds.
  Future<void> settleIo(WidgetTester tester) async {
    // Real I/O (SQLite, files) only progresses inside runAsync; its
    // continuations then need frames to run. Alternate until the work is done.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows every detected food and the combined nutrition', (tester) async {
    await open(tester, analysis([food('Chicken Curry', 320), food('Rice', 260), food('Curd', 60)]));

    expect(find.text('Chicken Curry'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Curd'), findsOneWidget);
    expect(find.text('640'), findsOneWidget); // total kcal
    expect(find.text('Confirm & Log'), findsOneWidget);
    expect(find.text('Looks good'), findsOneWidget);
    // Nothing is saved just by looking.
    expect(await tester.runAsync(() => env.scans.all()), isEmpty);
  });

  testWidgets('removing a food updates the total and can be undone', (tester) async {
    await open(tester, analysis([food('Rice', 260), food('Curd', 60)]));
    expect(find.text('320'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Curd'));
    await tester.pumpAndSettle();
    expect(find.text('260'), findsOneWidget);
    expect(find.text('Curd'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('320'), findsOneWidget);
    expect(find.text('Curd'), findsOneWidget);
  });

  testWidgets('increasing a portion scales calories and macros', (tester) async {
    await open(tester, analysis([food('Rice', 200, w: 200)]));
    expect(find.text('200 g'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase amount of Rice'));
    await tester.pumpAndSettle();

    expect(find.text('210 g'), findsOneWidget);
    expect(find.text('210'), findsOneWidget); // 200 kcal * 210/200
  });

  testWidgets('an uncertain result is never saved silently', (tester) async {
    await open(tester, analysis([food('Mystery stew', 300, conf: 0.3)], confidence: 0.35));
    expect(find.text('Please check this result'), findsOneWidget);
    expect(find.text('Low confidence'), findsOneWidget);

    await tester.tap(find.text('Confirm & Log'));
    await tester.pumpAndSettle();
    expect(find.text("The AI wasn't sure"), findsOneWidget);

    // "Review" keeps the user here and saves nothing.
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('RESULT PAGE'), findsNothing);
    expect(await tester.runAsync(() => env.scans.all()), isEmpty);
  });

  testWidgets('confirming saves the meal with its foods and marks it confirmed', (tester) async {
    await open(tester, analysis([food('Idli', 120), food('Sambar', 90)]));

    await tester.tap(find.text('Confirm & Log'));
    await settleIo(tester);

    final saved = (await tester.runAsync(() => env.scans.all()))!;
    expect(saved.length, 1);
    expect(saved.single.items.map((i) => i.name), ['Idli', 'Sambar']);
    expect(saved.single.calories, 210);
    expect(saved.single.analysisStatus, AnalysisStatus.confirmed);
    expect(saved.single.modelVersion, 'gemma-4-E2B-it');
    expect(saved.single.imageUrl, isNotNull); // photo stored privately
    expect(find.text('RESULT PAGE'), findsOneWidget);
  });

  testWidgets('a corrected result is saved as edited', (tester) async {
    await open(tester, analysis([food('Rice', 200, w: 200)]));
    await tester.tap(find.byTooltip('Decrease amount of Rice'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm & Log'));
    await settleIo(tester);

    final saved = (await tester.runAsync(() => env.scans.all()))!.single;
    expect(saved.analysisStatus, AnalysisStatus.edited);
    expect(saved.calories, 190); // 200 * 190/200
  });

  testWidgets('an empty meal cannot be logged', (tester) async {
    await open(tester, analysis([food('Rice', 200)]));
    await tester.tap(find.byTooltip('Remove Rice'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm & Log'));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one food to log this meal.'), findsOneWidget);
    expect(await tester.runAsync(() => env.scans.all()), isEmpty);
  });

  testWidgets('non-food photos offer another try instead of a log', (tester) async {
    await open(tester, analysis(const [], type: 'animal'));
    expect(find.text("That doesn't look like food"), findsOneWidget);
    expect(find.text('Confirm & Log'), findsNothing);
    expect(find.text('A golden retriever'), findsOneWidget);
  });

  testWidgets('cancelling asks first and discards without saving', (tester) async {
    await open(tester, analysis([food('Rice', 200)]));
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this meal?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget); // back where we started
    expect(await tester.runAsync(() => env.scans.all()), isEmpty);
  });

  testWidgets('analyse again replaces the result with a fresh analysis', (tester) async {
    ai.next = analysis([food('Dosa', 300)]);
    await open(tester, analysis([food('Rice', 200)]));

    await tester.tap(find.byTooltip('Analyse again'));
    await settleIo(tester);

    expect(ai.calls, 1);
    expect(find.text('Dosa'), findsOneWidget);
    expect(find.text('Rice'), findsNothing);
  });
}
