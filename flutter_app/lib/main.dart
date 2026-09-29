import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/providers/app_providers.dart';
import 'core/repositories/food_repository.dart';
import 'core/services/image_store.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  // Everything runs in one guarded zone so no error is ever silently lost.
  await runZonedGuarded(_bootstrap, (error, stack) {
    debugPrint('[Uncaught] $error\n$stack');
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformError] $error\n$stack');
    return true;
  };

  // NutriSnap is 100% on-device: local SQLite + a private image folder. The
  // only network use is the one-time download of the Gemma model weights.
  final database = await AppDatabase.open();
  final images = await ImageStore.open();

  // Load (or refresh) the built-in regional food library; instant when current.
  try {
    await FoodRepository(database).ensureSeeded(await rootBundle.loadString('assets/data/foods_in.json'));
  } catch (e) {
    debugPrint('[Bootstrap] food library unavailable: $e');
  }

  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
    huggingFaceToken: AppConfig.huggingFaceToken.isEmpty
        ? null
        : AppConfig.huggingFaceToken,
    maxDownloadRetries: 5,
  );

  final notifications = NotificationService();
  try {
    await notifications.initialize();
  } catch (e) {
    debugPrint('[Bootstrap] notifications unavailable: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        imageStoreProvider.overrideWithValue(images),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const NutriSnapApp(),
    ),
  );
}
