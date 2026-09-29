import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/meal_item.dart';
import 'package:nutrisnap_app/core/providers/app_providers.dart';
import 'package:nutrisnap_app/features/food/screens/food_library_screen.dart';
import 'package:nutrisnap_app/features/food/screens/food_twin_screen.dart';

import 'support/test_env.dart';

void main() {
  late TestEnv env;
  final dataset = File('assets/data/foods_in.json').readAsStringSync();

  setUp(() async {
    env = await TestEnv.create();
    await env.foods.ensureSeeded(dataset);
  });
  tearDown(() async => env.dispose());

  Future<void> pumpIo(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, Widget screen, {double width = 1080}) async {
    tester.view.physicalSize = Size(width, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(env.db),
        imageStoreProvider.overrideWithValue(env.images),
      ],
      child: MaterialApp(home: screen),
    ));
    await pumpIo(tester);
  }

  testWidgets('library lists real foods and works offline', (tester) async {
    await open(tester, const FoodLibraryScreen());
    expect(find.text('Food Library'), findsOneWidget);
    expect(find.textContaining('FOODS · WORKS OFFLINE'), findsOneWidget);
    expect(find.text('All foods'), findsOneWidget);
    expect(find.text('Your foods'), findsOneWidget);
    expect(find.text('Foods you create appear here.'), findsOneWidget);
  });

  testWidgets('searching by a regional alias finds the right food', (tester) async {
    await open(tester, const FoodLibraryScreen());
    await tester.enterText(find.byType(TextField), 'perugu annam');
    await pumpIo(tester, rounds: 10);
    expect(find.text('Curd Rice'), findsOneWidget);
    expect(find.text('Idli'), findsNothing);
  });

  testWidgets('a region filter narrows the list', (tester) async {
    await open(tester, const FoodLibraryScreen(), width: 4200); // wide: every chip is built
    await tester.tap(find.widgetWithText(FilterChip, 'Telangana'));
    await pumpIo(tester);
    expect(find.text('Bagara Baingan'), findsOneWidget); // Telangana
    expect(find.text('Idli'), findsNothing); // not tagged Telangana
  });

  testWidgets('no match offers to add the food', (tester) async {
    await open(tester, const FoodLibraryScreen());
    await tester.enterText(find.byType(TextField), 'zzzzqqq');
    await pumpIo(tester, rounds: 10);
    expect(find.text('No foods found'), findsOneWidget);
    expect(find.text('Add a food'), findsOneWidget);
  });

  testWidgets('logging a food records one library-sourced meal', (tester) async {
    await open(tester, const FoodLibraryScreen());
    await tester.enterText(find.byType(TextField), 'sambar');
    await pumpIo(tester, rounds: 10);

    await tester.tap(find.widgetWithText(FilledButton, 'Log').first);
    await tester.pumpAndSettle();
    expect(find.text('Log meal'), findsOneWidget);

    await tester.tap(find.byTooltip('More servings'));
    await tester.pump();
    expect(find.text('1.5'), findsOneWidget);

    await tester.tap(find.text('Log meal'));
    await pumpIo(tester, rounds: 10);
    await tester.pumpAndSettle();

    final meals = (await tester.runAsync(() => env.scans.all()))!;
    expect(meals.length, 1);
    expect(meals.single.items.single.name, 'Sambar');
    expect(meals.single.items.single.source, ItemSource.library);
    expect(meals.single.calories, 128); // 85 kcal x 1.5
    // Usage is remembered, so it now shows under Frequently used.
    final sambar = (await tester.runAsync(() => env.foods.findByName('Sambar')))!;
    expect(sambar.useCount, 1);
  });

  testWidgets('Food Twin shows an honest empty state, never invented statistics', (tester) async {
    await open(tester, const FoodTwinScreen());
    expect(find.text('Food Twin'), findsOneWidget);
    expect(find.text('Nothing learned yet'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // accuracy unknown
    expect(find.text('Needs 5 scanned foods'), findsOneWidget);
    expect(find.textContaining('never uploaded'), findsOneWidget);
  });
}
