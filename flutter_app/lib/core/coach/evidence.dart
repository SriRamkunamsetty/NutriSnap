import 'package:equatable/equatable.dart';

import '../models/scan_result.dart';
import '../repositories/activity_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/scan_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/summary_repository.dart';
import '../services/food_twin_service.dart';
import '../utils/datetime_utils.dart';

enum EvidenceType { meal, nutrition, hydration, activity, workout, sleep, goal, foodCorrection }

/// One normalised fact about the user, from any part of the app. This common
/// shape is what the Coach and the Why Engine reason over, so they never need
/// to know how meals, steps or sleep are stored.
class EvidenceEvent extends Equatable {
  const EvidenceEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.source,
    required this.value,
    required this.unit,
    this.metadata = const {},
    this.confidence = 1,
  });

  final String id;
  final EvidenceType type;
  final DateTime timestamp;

  /// Where it came from: `ai`, `manual`, `library`, `health_connect`, `profile`.
  final String source;
  final double value;
  final String unit;
  final Map<String, Object?> metadata;

  /// 0-1: how much to trust the value (photo estimates < typed-in numbers).
  final double confidence;

  @override
  List<Object?> get props => [id, type, timestamp, source, value, unit, metadata, confidence];
}

/// Builds the evidence stream for a time window from the local database.
/// Nothing is stored twice: events are derived on demand.
class EvidenceGraph {
  EvidenceGraph({
    required ScanRepository scans,
    required SummaryRepository summaries,
    required ActivityRepository activity,
    required ProfileRepository profiles,
    required SettingsRepository settings,
    required FoodTwinService twin,
  })  : _scans = scans,
        _summaries = summaries,
        _activity = activity,
        _profiles = profiles,
        _settings = settings,
        _twin = twin;

  final ScanRepository _scans;
  final SummaryRepository _summaries;
  final ActivityRepository _activity;
  final ProfileRepository _profiles;
  final SettingsRepository _settings;
  final FoodTwinService _twin;

  Future<List<EvidenceEvent>> build({required DateTime from, required DateTime to}) async {
    final events = <EvidenceEvent>[];
    final fromKey = DateTimeUtils.dayKey(from);
    final toKey = DateTimeUtils.dayKey(to);

    // Meals
    for (final s in await _scans.all()) {
      final at = DateTime.tryParse(s.timestamp);
      if (at == null || at.isBefore(from) || at.isAfter(to) || !s.isFood) continue;
      events.add(EvidenceEvent(
        id: 'meal:${s.id}',
        type: EvidenceType.meal,
        timestamp: at,
        source: s.analysisStatus == AnalysisStatus.manual ? 'manual' : 'ai',
        value: s.calories.toDouble(),
        unit: 'kcal',
        confidence: s.confidence,
        metadata: {
          'name': s.foodName,
          'protein': s.protein,
          'carbs': s.carbs,
          'fats': s.fats,
          'items': s.items.map((i) => i.name).toList(),
        },
      ));
    }

    // Daily nutrition + hydration
    for (final d in await _summaries.range(fromKey, toKey)) {
      final at = DateTime.parse(d.date).add(const Duration(hours: 23, minutes: 59));
      if (d.totalCalories > 0) {
        events.add(EvidenceEvent(
          id: 'nutrition:${d.date}',
          type: EvidenceType.nutrition,
          timestamp: at,
          source: 'derived',
          value: d.totalCalories.toDouble(),
          unit: 'kcal',
          metadata: {'protein': d.totalProtein, 'carbs': d.totalCarbs, 'fats': d.totalFats},
        ));
      }
      if (d.totalWater > 0) {
        events.add(EvidenceEvent(
          id: 'hydration:${d.date}',
          type: EvidenceType.hydration,
          timestamp: at,
          source: 'manual',
          value: d.totalWater.toDouble(),
          unit: 'ml',
        ));
      }
    }

    // Activity, workouts, sleep
    for (final d in await _activity.range(fromKey, toKey)) {
      if (d.steps > 0) {
        events.add(EvidenceEvent(
          id: 'activity:${d.date}',
          type: EvidenceType.activity,
          timestamp: DateTime.parse(d.date).add(const Duration(hours: 23, minutes: 59)),
          source: d.sources.length == 1 ? d.sources.first : 'mixed',
          value: d.steps.toDouble(),
          unit: 'steps',
          metadata: {
            'distanceKm': d.distanceKm,
            'activeKcal': d.activeCalories,
            'activeMinutes': d.activeMinutes,
          },
        ));
      }
    }
    for (final w in await _activity.workoutsBetween(fromKey, toKey)) {
      events.add(EvidenceEvent(
        id: 'workout:${w.id}',
        type: EvidenceType.workout,
        timestamp: w.start,
        source: w.source,
        value: w.durationMinutes.toDouble(),
        unit: 'min',
        confidence: w.caloriesEstimated ? 0.6 : 1,
        metadata: {'type': w.type, 'kcal': w.calories, 'estimated': w.caloriesEstimated},
      ));
    }
    for (final s in await _activity.sleepBetween(fromKey, toKey)) {
      events.add(EvidenceEvent(
        id: 'sleep:${s.id}',
        type: EvidenceType.sleep,
        timestamp: s.end,
        source: s.source,
        value: s.minutesAsleep.toDouble(),
        unit: 'min',
      ));
    }

    // Goals (as they stand now)
    final profile = await _profiles.get();
    final goals = await _settings.activityGoals();
    void goal(String key, num? v, String unit) {
      if (v == null || v <= 0) return;
      events.add(EvidenceEvent(
        id: 'goal:$key',
        type: EvidenceType.goal,
        timestamp: to,
        source: 'profile',
        value: v.toDouble(),
        unit: unit,
        metadata: {'goal': key},
      ));
    }

    goal('calories', profile?.calorieLimit, 'kcal');
    goal('protein', profile?.proteinGoal, 'g');
    goal('carbs', profile?.carbsGoal, 'g');
    goal('fats', profile?.fatsGoal, 'g');
    goal('water', profile?.waterGoal, 'ml');
    goal('steps', goals.dailySteps, 'steps');
    goal('activeMinutes', goals.dailyActiveMinutes, 'min');

    // Food Twin corrections
    for (final c in (await _twin.profile()).correctionHistory) {
      if (c.at.isBefore(from) || c.at.isAfter(to)) continue;
      events.add(EvidenceEvent(
        id: 'correction:${c.id}',
        type: EvidenceType.foodCorrection,
        timestamp: c.at,
        source: 'user',
        value: c.correctedKcal - c.originalKcal,
        unit: 'kcal',
        metadata: {'from': c.originalName, 'to': c.correctedName},
      ));
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  /// How many events of each type, for the "what the coach can see" view.
  static Map<EvidenceType, int> counts(List<EvidenceEvent> events) {
    final out = <EvidenceType, int>{};
    for (final e in events) {
      out[e.type] = (out[e.type] ?? 0) + 1;
    }
    return out;
  }
}
