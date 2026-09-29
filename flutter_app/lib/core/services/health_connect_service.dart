import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:uuid/uuid.dart';

import '../models/activity.dart';
import '../repositories/activity_repository.dart';
import '../repositories/settings_repository.dart';
import '../utils/datetime_utils.dart';
import 'activity_math.dart';

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

enum HcAvailability { available, needsUpdate, unavailable, unsupportedPlatform }

/// Permission groups. Only the ones the user turns on are ever requested.
enum HcGroup { activity, sleep, heartRate }

/// A record from the health platform reduced to what NutriSnap needs.
class RawHealthRecord extends Equatable {
  const RawHealthRecord({
    required this.kind,
    required this.from,
    required this.to,
    this.value = 0,
    this.uuid,
    this.origin,
    this.workoutType,
    this.energyKcal,
    this.distanceMeters,
  });

  /// `steps`, `distance`, `energy`, `workout`, `sleep_session`, `sleep_stage`, `heart_rate`.
  final String kind;
  final DateTime from;
  final DateTime to;

  /// steps: count, distance: metres, energy: kcal, heart_rate: bpm.
  final double value;
  final String? uuid;
  final String? origin;
  final String? workoutType;
  final double? energyKcal;
  final double? distanceMeters;

  @override
  List<Object?> get props =>
      [kind, from, to, value, uuid, origin, workoutType, energyKcal, distanceMeters];
}

/// Abstraction over the platform so the logic below is testable without a phone.
abstract class HealthDataSource {
  Future<HcAvailability> availability();
  Future<bool> hasPermissions(Set<HcGroup> groups);
  Future<bool> requestPermissions(Set<HcGroup> groups);
  Future<List<RawHealthRecord>> read(Set<HcGroup> groups, DateTime from, DateTime to);
  Future<void> revoke();
  Future<void> openInstall();
}

// -----------------------------------------------------------------------------
// Normalisation (pure)
// -----------------------------------------------------------------------------

class NormalizedHealth {
  const NormalizedHealth({this.entries = const [], this.workouts = const [], this.sleep = const []});
  final List<ActivityEntry> entries;
  final List<Workout> workouts;
  final List<SleepEntry> sleep;
}

class HealthNormalizer {
  const HealthNormalizer._();
  static const _uuid = Uuid();

  static NormalizedHealth normalize(List<RawHealthRecord> raw) {
    ActivityEntry entry(RawHealthRecord r, {int steps = 0, double meters = 0, double kcal = 0}) => ActivityEntry(
          id: 'hc_${_uuid.v4()}',
          start: r.from,
          end: r.to.isAfter(r.from) ? r.to : r.from.add(const Duration(minutes: 1)),
          steps: steps,
          distanceMeters: meters,
          activeCalories: kcal,
          source: DataSource.healthConnect,
          origin: r.origin,
          externalId: r.uuid ?? '${r.kind}:${r.origin}:${r.from.millisecondsSinceEpoch}',
        );

    final stepRows = <ActivityEntry>[];
    final distanceRows = <ActivityEntry>[];
    final energyRows = <ActivityEntry>[];
    final workouts = <Workout>[];
    final sessions = <RawHealthRecord>[];
    final stages = <RawHealthRecord>[];
    final heart = <RawHealthRecord>[];

    for (final r in raw) {
      switch (r.kind) {
        case 'steps':
          if (r.value > 0) stepRows.add(entry(r, steps: r.value.round()));
        case 'distance':
          if (r.value > 0) distanceRows.add(entry(r, meters: r.value));
        case 'energy':
          if (r.value > 0) energyRows.add(entry(r, kcal: r.value));
        case 'workout':
          workouts.add(Workout(
            id: 'hcw_${_uuid.v4()}',
            type: mapWorkoutType(r.workoutType),
            start: r.from,
            end: r.to.isAfter(r.from) ? r.to : r.from.add(const Duration(minutes: 1)),
            calories: (r.energyKcal ?? 0) > 0 ? r.energyKcal : null,
            distanceMeters: (r.distanceMeters ?? 0) > 0 ? r.distanceMeters : null,
            source: DataSource.healthConnect,
            origin: r.origin,
            externalId: r.uuid ?? 'workout:${r.origin}:${r.from.millisecondsSinceEpoch}',
          ));
        case 'sleep_session':
          sessions.add(r);
        case 'sleep_stage':
          stages.add(r);
        case 'heart_rate':
          heart.add(r);
      }
    }

    // Each metric is de-duplicated on its own: whichever app reports the most
    // wins the day and others only fill gaps (see ActivityMath).
    final entries = [
      ...ActivityMath.dedupeOverlaps(stepRows, DateTimeUtils.dayKey),
      ...ActivityMath.dedupeOverlaps(distanceRows, DateTimeUtils.dayKey, score: (e) => e.distanceMeters),
      ...ActivityMath.dedupeOverlaps(energyRows, DateTimeUtils.dayKey, score: (e) => e.activeCalories),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // Average heart rate over each workout, when heart-rate data exists.
    final withHr = <Workout>[];
    for (final w in workouts) {
      final inside = heart.where((h) => !h.from.isBefore(w.start) && !h.from.isAfter(w.end)).toList();
      if (inside.isEmpty) {
        withHr.add(w);
      } else {
        final avg = inside.fold<double>(0, (a, h) => a + h.value) / inside.length;
        withHr.add(Workout(
          id: w.id, type: w.type, start: w.start, end: w.end, calories: w.calories,
          distanceMeters: w.distanceMeters, avgHeartRate: avg.round(), source: w.source,
          origin: w.origin, externalId: w.externalId,
        ));
      }
    }

    return NormalizedHealth(entries: entries, workouts: withHr, sleep: _sleep(sessions, stages));
  }

  /// Sleep: prefer the time actually asleep (sum of asleep stages inside a
  /// session); fall back to the session length when no stages were recorded.
  static List<SleepEntry> _sleep(List<RawHealthRecord> sessions, List<RawHealthRecord> stages) {
    final out = <SleepEntry>[];
    for (final s in sessions) {
      final total = s.to.difference(s.from).inMinutes;
      if (total < 20) continue; // ignore naps/blips shorter than 20 minutes
      var asleep = 0;
      for (final st in stages) {
        final a = st.from.isAfter(s.from) ? st.from : s.from;
        final b = st.to.isBefore(s.to) ? st.to : s.to;
        if (b.isAfter(a)) asleep += b.difference(a).inMinutes;
      }
      out.add(SleepEntry(
        id: 'hcs_${_uuid.v4()}',
        start: s.from,
        end: s.to,
        minutesAsleep: asleep > 0 ? asleep.clamp(0, total) : total,
        origin: s.origin,
        externalId: s.uuid ?? 'sleep:${s.origin}:${s.from.millisecondsSinceEpoch}',
      ));
    }
    return out;
  }

  static String mapWorkoutType(String? t) {
    final n = (t ?? '').toUpperCase();
    if (n.contains('WALK') || n == 'HIKING') return ActivityType.walking;
    if (n.contains('RUN') || n == 'JOGGING') return ActivityType.running;
    if (n.contains('BIK') || n.contains('CYCL')) return ActivityType.cycling;
    if (n.isEmpty || n == 'OTHER') return ActivityType.other;
    return ActivityType.workout;
  }
}

// -----------------------------------------------------------------------------
// The real Health Connect adapter
// -----------------------------------------------------------------------------

class PluginHealthDataSource implements HealthDataSource {
  PluginHealthDataSource([Health? health]) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static List<HealthDataType> typesFor(Set<HcGroup> groups) => [
        if (groups.contains(HcGroup.activity)) ...[
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.WORKOUT,
        ],
        if (groups.contains(HcGroup.sleep)) ...[
          HealthDataType.SLEEP_SESSION,
          HealthDataType.SLEEP_ASLEEP,
        ],
        if (groups.contains(HcGroup.heartRate)) HealthDataType.HEART_RATE,
      ];

  @override
  Future<HcAvailability> availability() async {
    if (!Platform.isAndroid) return HcAvailability.unsupportedPlatform;
    try {
      await _configure();
      return switch (await _health.getHealthConnectSdkStatus()) {
        HealthConnectSdkStatus.sdkAvailable => HcAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HcAvailability.needsUpdate,
        _ => HcAvailability.unavailable,
      };
    } catch (e) {
      debugPrint('[HealthConnect] availability check failed: $e');
      return HcAvailability.unavailable;
    }
  }

  @override
  Future<bool> hasPermissions(Set<HcGroup> groups) async {
    final types = typesFor(groups);
    if (types.isEmpty) return false;
    try {
      await _configure();
      return await _health.hasPermissions(types, permissions: List.filled(types.length, HealthDataAccess.READ)) ??
          false;
    } catch (e) {
      debugPrint('[HealthConnect] permission check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions(Set<HcGroup> groups) async {
    final types = typesFor(groups);
    if (types.isEmpty) return false;
    try {
      await _configure();
      return await _health.requestAuthorization(types,
          permissions: List.filled(types.length, HealthDataAccess.READ));
    } catch (e) {
      debugPrint('[HealthConnect] permission request failed: $e');
      return false;
    }
  }

  @override
  Future<List<RawHealthRecord>> read(Set<HcGroup> groups, DateTime from, DateTime to) async {
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: typesFor(groups),
      startTime: from,
      endTime: to,
    );
    final out = <RawHealthRecord>[];
    for (final p in points) {
      final v = p.value;
      final num? n = v is NumericHealthValue ? v.numericValue : null;
      switch (p.type) {
        case HealthDataType.STEPS:
          out.add(RawHealthRecord(kind: 'steps', from: p.dateFrom, to: p.dateTo, value: n?.toDouble() ?? 0, uuid: p.uuid, origin: p.sourceId));
        case HealthDataType.DISTANCE_DELTA:
          out.add(RawHealthRecord(kind: 'distance', from: p.dateFrom, to: p.dateTo, value: n?.toDouble() ?? 0, uuid: p.uuid, origin: p.sourceId));
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          out.add(RawHealthRecord(kind: 'energy', from: p.dateFrom, to: p.dateTo, value: n?.toDouble() ?? 0, uuid: p.uuid, origin: p.sourceId));
        case HealthDataType.WORKOUT:
          if (v is WorkoutHealthValue) {
            out.add(RawHealthRecord(
              kind: 'workout',
              from: p.dateFrom,
              to: p.dateTo,
              uuid: p.uuid,
              origin: p.sourceId,
              workoutType: v.workoutActivityType.name,
              energyKcal: v.totalEnergyBurned?.toDouble(),
              distanceMeters: v.totalDistance?.toDouble(),
            ));
          }
        case HealthDataType.SLEEP_SESSION:
          out.add(RawHealthRecord(kind: 'sleep_session', from: p.dateFrom, to: p.dateTo, uuid: p.uuid, origin: p.sourceId));
        case HealthDataType.SLEEP_ASLEEP:
          out.add(RawHealthRecord(kind: 'sleep_stage', from: p.dateFrom, to: p.dateTo, uuid: p.uuid, origin: p.sourceId));
        case HealthDataType.HEART_RATE:
          out.add(RawHealthRecord(kind: 'heart_rate', from: p.dateFrom, to: p.dateTo, value: n?.toDouble() ?? 0, uuid: p.uuid, origin: p.sourceId));
        default:
          break;
      }
    }
    return out;
  }

  @override
  Future<void> revoke() async {
    try {
      await _configure();
      await _health.revokePermissions();
    } catch (e) {
      debugPrint('[HealthConnect] revoke failed: $e');
    }
  }

  @override
  Future<void> openInstall() async {
    try {
      await _configure();
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('[HealthConnect] install prompt failed: $e');
    }
  }
}

// -----------------------------------------------------------------------------
// State + controller
// -----------------------------------------------------------------------------

class HcState extends Equatable {
  const HcState({
    this.loading = true,
    this.availability = HcAvailability.unavailable,
    this.prefs = const HealthConnectPrefs(),
    this.syncing = false,
    this.permissionDenied = false,
    this.error,
  });

  final bool loading;
  final HcAvailability availability;
  final HealthConnectPrefs prefs;
  final bool syncing;

  /// The user (or the OS) declined; show the "Connect Health Data" call to action.
  final bool permissionDenied;
  final String? error;

  bool get connected => prefs.anyEnabled && availability == HcAvailability.available && !permissionDenied;

  HcState copyWith({
    bool? loading,
    HcAvailability? availability,
    HealthConnectPrefs? prefs,
    bool? syncing,
    bool? permissionDenied,
    String? error,
    bool clearError = false,
  }) =>
      HcState(
        loading: loading ?? this.loading,
        availability: availability ?? this.availability,
        prefs: prefs ?? this.prefs,
        syncing: syncing ?? this.syncing,
        permissionDenied: permissionDenied ?? this.permissionDenied,
        error: clearError ? null : error ?? this.error,
      );

  @override
  List<Object?> get props => [
        loading, availability, prefs.activity, prefs.sleep, prefs.heartRate,
        prefs.lastSync, syncing, permissionDenied, error,
      ];
}

class HealthConnectController extends StateNotifier<HcState> {
  HealthConnectController({
    required HealthDataSource source,
    required ActivityRepository activity,
    required SettingsRepository settings,
    DateTime Function()? clock,
  })  : _source = source,
        _activity = activity,
        _settings = settings,
        _now = clock ?? DateTime.now,
        super(const HcState()) {
    refresh();
  }

  final HealthDataSource _source;
  final ActivityRepository _activity;
  final SettingsRepository _settings;
  final DateTime Function() _now;

  static const Duration staleAfter = Duration(minutes: 15);
  static const int firstSyncDays = 14;
  static const int routineSyncDays = 3;

  Set<HcGroup> _groups(HealthConnectPrefs p) => {
        if (p.activity) HcGroup.activity,
        if (p.sleep) HcGroup.sleep,
        if (p.heartRate) HcGroup.heartRate,
      };

  /// Re-reads availability and whether permissions are still granted (the user
  /// can revoke them in system settings at any time).
  Future<void> refresh() async {
    final availability = await _source.availability();
    final prefs = await _settings.healthConnectPrefs();
    var denied = false;
    if (availability == HcAvailability.available && prefs.anyEnabled) {
      denied = !await _source.hasPermissions(_groups(prefs));
    }
    if (mounted) {
      state = state.copyWith(
        loading: false,
        availability: availability,
        prefs: prefs,
        permissionDenied: denied,
        clearError: true,
      );
    }
  }

  /// Asks for [groups] (only what is needed) and, if granted, syncs.
  Future<bool> connect(Set<HcGroup> groups) async {
    if (state.availability == HcAvailability.needsUpdate ||
        state.availability == HcAvailability.unavailable) {
      await _source.openInstall();
      return false;
    }
    final wanted = {..._groups(state.prefs), ...groups};
    final granted = await _source.requestPermissions(wanted);
    if (!granted) {
      if (mounted) state = state.copyWith(permissionDenied: true);
      return false;
    }
    await _settings.setHealthConnectPrefs(
      activity: wanted.contains(HcGroup.activity),
      sleep: wanted.contains(HcGroup.sleep),
      heartRate: wanted.contains(HcGroup.heartRate),
    );
    await refresh();
    await sync(force: true);
    return true;
  }

  Future<void> syncIfStale() async {
    final last = state.prefs.lastSync;
    if (last == null || _now().difference(last) >= staleAfter) await sync();
  }

  /// Imports recent data. Safe to call repeatedly (idempotent).
  Future<void> sync({bool force = false}) async {
    if (state.syncing || !state.connected) return;
    final prefs = state.prefs;
    final groups = _groups(prefs);
    if (groups.isEmpty) return;

    state = state.copyWith(syncing: true, clearError: true);
    try {
      final now = _now();
      final days = prefs.lastSync == null ? firstSyncDays : routineSyncDays;
      final today = DateTime(now.year, now.month, now.day);
      final from = today.subtract(Duration(days: days));

      final raw = await _source.read(groups, from, now);
      final data = HealthNormalizer.normalize(raw);
      await _activity.importBatch(
        entries: data.entries,
        workouts: data.workouts,
        sleep: data.sleep,
        replaceSource: DataSource.healthConnect,
        windowStart: from,
        windowEnd: now.add(const Duration(days: 1)),
      );
      await _settings.markHealthConnectSync(now);
      final updated = await _settings.healthConnectPrefs();
      if (mounted) state = state.copyWith(syncing: false, prefs: updated);
    } catch (e) {
      debugPrint('[HealthConnect] sync failed: $e');
      if (mounted) {
        state = state.copyWith(
          syncing: false,
          error: 'Could not read your health data. Pull to retry.',
        );
      }
    }
  }

  /// Turns Health Connect off. Optionally deletes what was imported.
  Future<void> disconnect({required bool deleteImportedData}) async {
    await _source.revoke();
    await _settings.clearHealthConnectPrefs();
    if (deleteImportedData) await _activity.deleteBySource(DataSource.healthConnect);
    await refresh();
  }
}
