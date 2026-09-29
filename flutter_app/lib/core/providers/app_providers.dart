import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/gemma_model_controller.dart';
import '../ai/gemma_service.dart';
import '../ai/nutrition_ai.dart';
import '../coach/coach_context.dart';
import '../coach/coach_snapshot.dart';
import '../coach/evidence.dart';
import '../coach/why_engine.dart';
import '../database/app_database.dart';
import '../models/chat_message.dart';
import '../models/daily_summary.dart';
import '../models/user_profile.dart';
import '../models/food.dart';
import '../models/scan_result.dart';
import '../models/activity.dart';
import '../repositories/activity_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/food_repository.dart';
import '../repositories/mess_repository.dart';
import '../models/mess.dart';
import '../repositories/profile_repository.dart';
import '../repositories/scan_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/summary_repository.dart';
import '../services/backup_service.dart';
import '../services/phone_step_service.dart';
import '../services/food_twin_service.dart';
import '../services/mess_service.dart';
import '../services/health_connect_service.dart';
import '../services/image_store.dart';
import '../services/notification_service.dart';
import '../services/retention_service.dart';
import '../utils/datetime_utils.dart';

// -----------------------------------------------------------------------------
// Bootstrap-provided singletons (overridden in main() after async start-up)
// -----------------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>(
    (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'));

final imageStoreProvider = Provider<ImageStore>(
    (ref) => throw UnimplementedError('imageStoreProvider must be overridden'));

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

// -----------------------------------------------------------------------------
// Repositories + services
// -----------------------------------------------------------------------------

final profileRepositoryProvider = Provider<ProfileRepository>((ref) =>
    ProfileRepository(ref.watch(appDatabaseProvider), ref.watch(imageStoreProvider)));

final scanRepositoryProvider = Provider<ScanRepository>((ref) =>
    ScanRepository(ref.watch(appDatabaseProvider), ref.watch(imageStoreProvider)));

final summaryRepositoryProvider = Provider<SummaryRepository>(
    (ref) => SummaryRepository(ref.watch(appDatabaseProvider)));

final chatRepositoryProvider = Provider<ChatRepository>(
    (ref) => ChatRepository(ref.watch(appDatabaseProvider)));

final activityRepositoryProvider = Provider<ActivityRepository>(
    (ref) => ActivityRepository(ref.watch(appDatabaseProvider)));

final foodRepositoryProvider =
    Provider<FoodRepository>((ref) => FoodRepository(ref.watch(appDatabaseProvider)));

final foodTwinServiceProvider = Provider<FoodTwinService>(
    (ref) => FoodTwinService(ref.watch(appDatabaseProvider), ref.watch(foodRepositoryProvider)));

final messRepositoryProvider =
    Provider<MessRepository>((ref) => MessRepository(ref.watch(appDatabaseProvider)));

final messServiceProvider = Provider<MessService>((ref) => MessService(
      foods: ref.watch(foodRepositoryProvider),
      messes: ref.watch(messRepositoryProvider),
      scans: ref.watch(scanRepositoryProvider),
    ));

final settingsRepositoryProvider = Provider<SettingsRepository>(
    (ref) => SettingsRepository(ref.watch(appDatabaseProvider)));

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
      database: ref.watch(appDatabaseProvider),
      images: ref.watch(imageStoreProvider),
      profiles: ref.watch(profileRepositoryProvider),
      scans: ref.watch(scanRepositoryProvider),
      summaries: ref.watch(summaryRepositoryProvider),
      chat: ref.watch(chatRepositoryProvider),
    ));

final retentionServiceProvider = Provider<RetentionService>((ref) => RetentionService(
      database: ref.watch(appDatabaseProvider),
      scans: ref.watch(scanRepositoryProvider),
      chat: ref.watch(chatRepositoryProvider),
      summaries: ref.watch(summaryRepositoryProvider),
      settings: ref.watch(settingsRepositoryProvider),
    ));

// -----------------------------------------------------------------------------
// On-device AI
// -----------------------------------------------------------------------------

final gemmaModelProvider =
    StateNotifierProvider<GemmaModelController, GemmaModelState>(
        (ref) => GemmaModelController());

final nutritionAiProvider = Provider<NutritionAi>((ref) {
  final service =
      GemmaService(isInstalled: () => ref.read(gemmaModelProvider).isInstalled);
  ref.onDispose(service.unload);
  return service;
});

// -----------------------------------------------------------------------------
// Reactive data
// -----------------------------------------------------------------------------

/// The current local day key. Ticks over at midnight and on app resume so
/// "today" views never show yesterday's totals.
class TodayKeyNotifier extends StateNotifier<String> with WidgetsBindingObserver {
  TodayKeyNotifier() : super(DateTimeUtils.today()) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  Timer? _timer;

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
    _timer = Timer(next.difference(now), _refresh);
  }

  void _refresh() {
    final key = DateTimeUtils.today();
    if (key != state) state = key;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final todayKeyProvider =
    StateNotifierProvider<TodayKeyNotifier, String>((ref) => TodayKeyNotifier());

final scanHistoryStreamProvider = StreamProvider.autoDispose<List<ScanResult>>(
    (ref) => ref.watch(scanRepositoryProvider).watchAll());

final chatHistoryStreamProvider = StreamProvider.autoDispose<List<ChatMessage>>(
    (ref) => ref.watch(chatRepositoryProvider).watchAll());

final dailySummaryStreamProvider = StreamProvider.autoDispose<DailySummary>((ref) {
  final day = ref.watch(todayKeyProvider);
  return ref.watch(summaryRepositoryProvider).watchDate(day);
});

/// Per-day totals for the last [days] days (for charts).
final summariesInRangeProvider =
    StreamProvider.autoDispose.family<List<DailySummary>, int>((ref, days) {
  final today = ref.watch(todayKeyProvider);
  final end = DateTime.parse(today);
  final start = DateTime(end.year, end.month, end.day - (days - 1));
  return ref
      .watch(summaryRepositoryProvider)
      .watchRange(DateTimeUtils.dayKey(start), today);
});

// -----------------------------------------------------------------------------
// Activity
// -----------------------------------------------------------------------------

final activityGoalsProvider = StreamProvider.autoDispose<ActivityGoals>(
    (ref) => ref.watch(settingsRepositoryProvider).watchActivityGoals());

/// Today's activity summary (rolls over at midnight like the nutrition views).
final todayActivityProvider = StreamProvider.autoDispose<DailyActivity>((ref) {
  final day = ref.watch(todayKeyProvider);
  return ref.watch(activityRepositoryProvider).watchDaily(day);
});

final todayTimelineProvider = StreamProvider.autoDispose<List<ActivityEntry>>((ref) {
  final day = ref.watch(todayKeyProvider);
  return ref.watch(activityRepositoryProvider).watchTimeline(day);
});

final todayWorkoutsProvider = StreamProvider.autoDispose<List<Workout>>((ref) {
  final day = ref.watch(todayKeyProvider);
  return ref.watch(activityRepositoryProvider).watchWorkouts(day);
});

/// Per-day activity for the last [days] days.
final activityRangeProvider = StreamProvider.autoDispose.family<List<DailyActivity>, int>((ref, days) {
  final today = ref.watch(todayKeyProvider);
  final end = DateTime.parse(today);
  final start = DateTime(end.year, end.month, end.day - (days - 1));
  return ref.watch(activityRepositoryProvider).watchRange(DateTimeUtils.dayKey(start), today);
});

final recentSleepProvider = StreamProvider.autoDispose<List<SleepEntry>>((ref) {
  final today = ref.watch(todayKeyProvider);
  final end = DateTime.parse(today);
  final start = DateTime(end.year, end.month, end.day - 13);
  return ref.watch(activityRepositoryProvider).watchSleep(DateTimeUtils.dayKey(start), today);
});

// -----------------------------------------------------------------------------
// Health Connect
// -----------------------------------------------------------------------------

final healthDataSourceProvider = Provider<HealthDataSource>((ref) => PluginHealthDataSource());

final healthConnectProvider = StateNotifierProvider<HealthConnectController, HcState>(
  (ref) => HealthConnectController(
    source: ref.watch(healthDataSourceProvider),
    activity: ref.watch(activityRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

// -----------------------------------------------------------------------------
// Food intelligence
// -----------------------------------------------------------------------------

final foodTwinProfileProvider = StreamProvider.autoDispose<FoodTwinProfile>(
    (ref) => ref.watch(foodTwinServiceProvider).watchProfile());

final customFoodsProvider =
    StreamProvider.autoDispose<List<Food>>((ref) => ref.watch(foodRepositoryProvider).watchCustom());

final recentFoodsProvider =
    StreamProvider.autoDispose<List<Food>>((ref) => ref.watch(foodRepositoryProvider).watchRecent());

final frequentFoodsProvider =
    StreamProvider.autoDispose<List<Food>>((ref) => ref.watch(foodRepositoryProvider).watchFrequent());

// -----------------------------------------------------------------------------
// MessOS
// -----------------------------------------------------------------------------

final messesProvider =
    StreamProvider.autoDispose<List<Mess>>((ref) => ref.watch(messRepositoryProvider).watchMesses());

final activeMessProvider =
    StreamProvider.autoDispose<Mess?>((ref) => ref.watch(messRepositoryProvider).watchActive());

/// The active mess's menu for a `yyyy-MM-dd` date (null when none saved).
final messMenuProvider = StreamProvider.autoDispose.family<MessMenu?, ({String messId, String date})>(
    (ref, key) => ref.watch(messRepositoryProvider).watchMenu(key.messId, key.date));

final messMenuDatesProvider = StreamProvider.autoDispose.family<List<String>, String>(
    (ref, messId) => ref.watch(messRepositoryProvider).watchMenuDates(messId));

// -----------------------------------------------------------------------------
// Coach: snapshot -> insights / briefing (all recomputed when data changes)
// -----------------------------------------------------------------------------

final profileStreamProvider = StreamProvider.autoDispose<UserProfile?>(
    (ref) => ref.watch(profileRepositoryProvider).watch());

/// Re-evaluates time-of-day dependent advice every 10 minutes.
final _coachTickProvider =
    StreamProvider.autoDispose<int>((ref) => Stream.periodic(const Duration(minutes: 10), (i) => i));

final coachSnapshotProvider = FutureProvider.autoDispose<CoachSnapshot>((ref) async {
  // Depending on these makes the coach, Home insight and Insights tab update
  // automatically when a meal, water, activity, sleep, goal or profile changes.
  ref.watch(dailySummaryStreamProvider);
  ref.watch(scanHistoryStreamProvider);
  ref.watch(todayActivityProvider);
  ref.watch(activityGoalsProvider);
  ref.watch(recentSleepProvider);
  ref.watch(profileStreamProvider);
  ref.watch(foodTwinProfileProvider);
  ref.watch(_coachTickProvider);
  final connected = ref.watch(healthConnectProvider.select((s) => s.connected));

  return CoachSnapshotLoader(
    profiles: ref.read(profileRepositoryProvider),
    summaries: ref.read(summaryRepositoryProvider),
    scans: ref.read(scanRepositoryProvider),
    activity: ref.read(activityRepositoryProvider),
    settings: ref.read(settingsRepositoryProvider),
    foods: ref.read(foodRepositoryProvider),
    twin: ref.read(foodTwinServiceProvider),
  ).load(healthDataConnected: connected);
});

final insightsProvider = Provider.autoDispose<List<Insight>>((ref) {
  final snap = ref.watch(coachSnapshotProvider).valueOrNull;
  return snap == null ? const [] : WhyEngine.analyze(snap);
});

final topInsightProvider = Provider.autoDispose<Insight?>((ref) {
  final all = ref.watch(insightsProvider);
  return all.isEmpty ? null : all.first;
});

/// Exactly what the model is told about the user (shown in the app for transparency).
final coachBriefingProvider = Provider.autoDispose<String?>((ref) {
  final snap = ref.watch(coachSnapshotProvider).valueOrNull;
  return snap == null ? null : CoachContext.build(snap, insights: ref.watch(insightsProvider));
});

final evidenceGraphProvider = Provider<EvidenceGraph>((ref) => EvidenceGraph(
      scans: ref.watch(scanRepositoryProvider),
      summaries: ref.watch(summaryRepositoryProvider),
      activity: ref.watch(activityRepositoryProvider),
      profiles: ref.watch(profileRepositoryProvider),
      settings: ref.watch(settingsRepositoryProvider),
      twin: ref.watch(foodTwinServiceProvider),
    ));

/// How many pieces of evidence of each kind the coach can draw on (last 7 days).
final evidenceCountsProvider = FutureProvider.autoDispose<Map<EvidenceType, int>>((ref) async {
  ref.watch(coachSnapshotProvider); // refresh together with the snapshot
  final now = DateTime.now();
  final events = await ref
      .read(evidenceGraphProvider)
      .build(from: DateTime(now.year, now.month, now.day - 6), to: now);
  return EvidenceGraph.counts(events);
});

final allWorkoutsProvider = StreamProvider.autoDispose<List<Workout>>(
    (ref) => ref.watch(activityRepositoryProvider).watchAllWorkouts());

// -----------------------------------------------------------------------------
// Phone step sensor (for people not using Health Connect)
// -----------------------------------------------------------------------------

final stepCounterSourceProvider = Provider<StepCounterSource>((ref) => PluginStepCounterSource());

final phoneStepServiceProvider = Provider<PhoneStepService>((ref) => PhoneStepService(
      ref.watch(appDatabaseProvider),
      ref.watch(activityRepositoryProvider),
      ref.watch(stepCounterSourceProvider),
    ));

final phoneStepsEnabledProvider = StateProvider.autoDispose<bool?>((ref) => null);
