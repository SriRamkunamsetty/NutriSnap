import 'package:equatable/equatable.dart';

/// Where a health metric came from (shown next to the number in the UI).
class DataSource {
  const DataSource._();
  static const manual = 'manual';
  static const healthConnect = 'health_connect';
  static const phoneSensor = 'phone_sensor';

  static String label(String source) => switch (source) {
        healthConnect => 'Health Connect',
        manual => 'Manual',
        phoneSensor => 'Phone sensor',
        _ => source,
      };
}

class ActivityType {
  const ActivityType._();
  static const walking = 'walking';
  static const running = 'running';
  static const cycling = 'cycling';
  static const workout = 'workout';
  static const other = 'other';

  static const workoutTypes = [walking, running, cycling, workout, other];

  static String label(String t) => switch (t) {
        walking => 'Walking',
        running => 'Running',
        cycling => 'Cycling',
        workout => 'Workout',
        _ => 'Other',
      };

  /// Metabolic equivalents used to *estimate* calories for manual workouts.
  static double met(String t) => switch (t) {
        walking => 3.5,
        running => 9.8,
        cycling => 7.5,
        workout => 5.0,
        _ => 4.0,
      };

  /// Estimated kcal = MET x body weight (kg) x hours. Always flagged as an
  /// estimate in the UI and in storage.
  static double estimateCalories(String type, {required int minutes, required double weightKg}) =>
      met(type) * weightKg * (minutes / 60.0);
}

/// A period of movement (usually steps) on one day.
class ActivityEntry extends Equatable {
  const ActivityEntry({
    required this.id,
    required this.start,
    required this.end,
    this.type = ActivityType.walking,
    this.steps = 0,
    this.distanceMeters = 0,
    this.activeCalories = 0,
    this.source = DataSource.manual,
    this.origin,
    this.externalId,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final String type;
  final int steps;
  final double distanceMeters;
  final double activeCalories;
  final String source;

  /// The app that wrote the record (e.g. `com.google.android.apps.fitness`).
  final String? origin;

  /// Stable id from the source system; used to avoid duplicate imports.
  final String? externalId;

  Duration get duration => end.difference(start);
  double get minutes => duration.inSeconds / 60.0;

  /// Steps per minute; 0 for zero-length records.
  double get cadence => minutes <= 0 ? 0 : steps / minutes;

  @override
  List<Object?> get props =>
      [id, start, end, type, steps, distanceMeters, activeCalories, source, origin, externalId];
}

class Workout extends Equatable {
  const Workout({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    this.calories,
    this.caloriesEstimated = false,
    this.distanceMeters,
    this.avgHeartRate,
    this.notes,
    this.source = DataSource.manual,
    this.origin,
    this.externalId,
  });

  final String id;
  final String type;
  final DateTime start;
  final DateTime end;
  final double? calories;
  final bool caloriesEstimated;
  final double? distanceMeters;
  final int? avgHeartRate;
  final String? notes;
  final String source;
  final String? origin;
  final String? externalId;

  Duration get duration => end.difference(start);
  int get durationMinutes => duration.inMinutes;

  @override
  List<Object?> get props => [
        id, type, start, end, calories, caloriesEstimated, distanceMeters,
        avgHeartRate, notes, source, origin, externalId,
      ];
}

class SleepEntry extends Equatable {
  const SleepEntry({
    required this.id,
    required this.start,
    required this.end,
    required this.minutesAsleep,
    this.source = DataSource.healthConnect,
    this.origin,
    this.externalId,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final int minutesAsleep;
  final String source;
  final String? origin;
  final String? externalId;

  @override
  List<Object?> get props => [id, start, end, minutesAsleep, source, origin, externalId];
}

/// Personal targets, stored locally.
class ActivityGoals extends Equatable {
  const ActivityGoals({
    this.dailySteps = 10000,
    this.dailyActiveMinutes = 30,
    this.weeklyActiveMinutes = 150,
    this.weeklyWorkouts = 3,
  });

  final int dailySteps;
  final int dailyActiveMinutes;
  final int weeklyActiveMinutes;
  final int weeklyWorkouts;

  ActivityGoals copyWith({
    int? dailySteps,
    int? dailyActiveMinutes,
    int? weeklyActiveMinutes,
    int? weeklyWorkouts,
  }) =>
      ActivityGoals(
        dailySteps: dailySteps ?? this.dailySteps,
        dailyActiveMinutes: dailyActiveMinutes ?? this.dailyActiveMinutes,
        weeklyActiveMinutes: weeklyActiveMinutes ?? this.weeklyActiveMinutes,
        weeklyWorkouts: weeklyWorkouts ?? this.weeklyWorkouts,
      );

  @override
  List<Object?> get props => [dailySteps, dailyActiveMinutes, weeklyActiveMinutes, weeklyWorkouts];
}

/// One day's activity, computed from entries + workouts.
class DailyActivity extends Equatable {
  const DailyActivity({
    required this.date,
    this.steps = 0,
    this.distanceMeters = 0,
    this.activeCalories = 0,
    this.activeMinutes = 0,
    this.workoutCount = 0,
    this.sources = const {},
  });

  final String date;
  final int steps;
  final double distanceMeters;
  final double activeCalories;
  final int activeMinutes;
  final int workoutCount;

  /// Which sources contributed (for the "Health Connect" / "Manual" label).
  final Set<String> sources;

  double get distanceKm => distanceMeters / 1000.0;
  bool get hasData => steps > 0 || activeCalories > 0 || activeMinutes > 0 || workoutCount > 0;

  String get sourceLabel => sources.isEmpty
      ? ''
      : (sources.toList()..sort()).map(DataSource.label).join(' + ');

  @override
  List<Object?> get props =>
      [date, steps, distanceMeters, activeCalories, activeMinutes, workoutCount, sources];
}
