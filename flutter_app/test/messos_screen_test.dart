import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/mess.dart';
import 'package:nutrisnap_app/core/providers/app_providers.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';
import 'package:nutrisnap_app/features/messos/screens/messos_screen.dart';

import 'support/fake_health.dart';
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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(env.db),
        imageStoreProvider.overrideWithValue(env.images),
        healthDataSourceProvider.overrideWithValue(FakeHealth()),
      ],
      child: const MaterialApp(home: MessOsScreen()),
    ));
    await pumpIo(tester);
  }

  testWidgets('first run asks where you eat and shows no invented menu', (tester) async {
    await open(tester);
    expect(find.text('Set up your mess'), findsOneWidget);
    expect(find.text('Add my mess'), findsOneWidget);
    expect(find.text('Breakfast'), findsNothing);
  });

  testWidgets('college -> hostel -> mess setup creates and selects the mess', (tester) async {
    await open(tester);
    await tester.tap(find.text('Add my mess'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add mess')); // empty form is rejected
    await tester.pump();
    expect(find.text('Enter your college and hostel.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'College'), 'JNTU Hyderabad');
    await tester.enterText(find.widgetWithText(TextField, 'Hostel'), 'Block A');
    await tester.tap(find.text('Add mess'));
    await pumpIo(tester, rounds: 10);
    await tester.pumpAndSettle();

    final mess = (await tester.runAsync(() => env.messes.active()))!;
    expect(mess.college, 'JNTU Hyderabad');
    expect(mess.label, 'Block A Mess'); // sensible default name
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text("Add today's menu"), findsNWidgets(4));
  });

  testWidgets('pasting a menu fills the meals with library nutrition; logging is one tap', (tester) async {
    await tester.runAsync(() => env.messes.createMess(college: 'JNTU', hostel: 'Block A', name: 'Main Mess'));
    await open(tester);

    await tester.tap(find.text('Paste menu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Breakfast: Idli, Sambar\nLunch: Steamed Rice, Dal Tadka, Curd');
    await tester.tap(find.text('Read menu'));
    await pumpIo(tester, rounds: 12);
    await tester.pumpAndSettle();

    expect(find.text('Idli'), findsOneWidget);
    expect(find.text('Sambar'), findsOneWidget);
    expect(find.text('215'), findsOneWidget); // 130 + 85 kcal breakfast total
    expect(find.text('Log meal'), findsNWidgets(2));

    await tester.tap(find.text('Log meal').first);
    await pumpIo(tester, rounds: 12);
    await tester.pumpAndSettle();

    final diary = (await tester.runAsync(() => env.scans.all()))!;
    expect(diary.length, 1);
    expect(diary.single.calories, 215);
    expect(diary.single.items.map((i) => i.name), ['Idli', 'Sambar']);
    expect(find.text('Logged'), findsOneWidget);
    expect(find.text('Undo log'), findsOneWidget);

    await tester.tap(find.text('Undo log'));
    await pumpIo(tester, rounds: 12);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => env.scans.all()), isEmpty);
    expect(find.text('Undo log'), findsNothing);
  });

  testWidgets('a dish with no nutrition is flagged, not silently counted', (tester) async {
    final mess = (await tester.runAsync(() => env.messes.createMess(college: 'C', hostel: 'H', name: 'M')))!;
    await tester.runAsync(() async {
      final dishes = await env.mess.match(['Idli', 'Mystery Sabzi']);
      await env.messes.saveMeal(messId: mess.id, date: DateTimeUtils.today(), mealType: MealType.dinner, dishes: dishes);
    });
    await open(tester);

    expect(find.text('needs estimate'), findsOneWidget);
    expect(find.text('1 dish not counted yet'), findsOneWidget);

    await tester.tap(find.text('Log meal'));
    await tester.pumpAndSettle();
    expect(find.text('Some dishes have no nutrition'), findsOneWidget);
    await tester.tap(find.text('Edit menu')); // do not log
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => env.scans.all()), isEmpty);
  });

  testWidgets('yesterday\'s and other saved menus are one tap away', (tester) async {
    final mess = (await tester.runAsync(() => env.messes.createMess(college: 'C', hostel: 'H', name: 'M')))!;
    await tester.runAsync(() async {
      final d = await env.mess.match(['Idli']);
      await env.messes.saveMeal(messId: mess.id, date: '2025-02-01', mealType: MealType.breakfast, dishes: d);
    });
    await open(tester);
    expect(find.text('Menu history'), findsOneWidget);
    expect(find.text('Sat 1 Feb'), findsOneWidget);
  });
}
