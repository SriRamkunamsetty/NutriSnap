import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/activity.dart';
import '../services/activity_math.dart';
import '../utils/datetime_utils.dart';

/// Steps, movement timeline, workouts and sleep. Imports from Health Connect
/// are idempotent: a record is identified by (source, external id), so syncing
/// the same window twice never duplicates anything.
class ActivityRepository {
  ActivityRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _tables = {Tables.activityEntries, Tables.workouts};

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<ActivityEntry> addManualEntry({
    required DateTime start,
    required DateTime end,
    String type = ActivityType.walking,
    int steps = 0,
    double distanceMeters = 0,
    double activeCalories = 0,
  }) async {
    final e = ActivityEntry(
      id: 'act_${_uuid.v4()}',
      start: start,
      end: end.isAfter(start) ? end : start.add(const Duration(minutes: 1)),
      type: type,
      steps: steps,
      distanceMeters: distanceMeters,
      activeCalories: activeCalories,
    );
    await _db.db.insert(Tables.activityEntries, _entryRow(e));
    _db.notify(Tables.activityEntries);
    return e;
  }

  Future<Workout> addWorkout(Workout w) async {
    final saved = Workout(
      id: w.id.isEmpty ? 'wo_${_uuid.v4()}' : w.id,
      type: w.type,
      start: w.start,
      end: w.end,
      calories: w.calories,
      caloriesEstimated: w.caloriesEstimated,
      distanceMeters: w.distanceMeters,
      avgHeartRate: w.avgHeartRate,
      notes: w.notes,
      source: w.source,
      origin: w.origin,
      externalId: w.externalId,
    );
    await _db.db.insert(Tables.workouts, _workoutRow(saved), conflictAlgorithm: ConflictAlgorithm.replace);
    _db.notify(Tables.workouts);
    return saved;
  }

  Future<void> deleteEntry(String id) async {
    await _db.db.delete(Tables.activityEntries, where: 'id = ?', whereArgs: [id]);
    _db.notify(Tables.activityEntries);
  }

  Future<void> deleteWorkout(String id) async {
    await _db.db.delete(Tables.workouts, where: 'id = ?', whereArgs: [id]);
    _db.notify(Tables.workouts);
  }

  /// Idempotent bulk import from an external source.
  ///
  /// When [replaceSource] and a window are given, everything previously
  /// imported from that source inside the window is removed first, so records
  /// that were deleted or re-attributed at the source disappear here too.
  Future<ImportResult> importBatch({
    List<ActivityEntry> entries = const [],
    List<Workout> workouts = const [],
    List<SleepEntry> sleep = const [],
    String? replaceSource,
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    var added = 0;
    await _db.db.transaction((txn) async {
      if (replaceSource != null && windowStart != null && windowEnd != null) {
        final from = windowStart.millisecondsSinceEpoch;
        final to = windowEnd.millisecondsSinceEpoch;
        for (final t in [Tables.activityEntries, Tables.workouts, Tables.sleepEntries]) {
          await txn.delete(t,
              where: 'source = ? AND start_ms >= ? AND start_ms < ?', whereArgs: [replaceSource, from, to]);
        }
      }
      for (final e in entries) {
        added += await _upsertExternal(txn, Tables.activityEntries, _entryRow(e), e.source, e.externalId);
      }
      for (final w in workouts) {
        added += await _upsertExternal(txn, Tables.workouts, _workoutRow(w), w.source, w.externalId);
      }
      for (final s in sleep) {
        added += await _upsertExternal(txn, Tables.sleepEntries, _sleepRow(s), s.source, s.externalId);
      }
    });
    _db.notify(Tables.activityEntries);
    _db.notify(Tables.workouts);
    _db.notify(Tables.sleepEntries);
    return ImportResult(added);
  }

  /// Replaces an existing record with the same (source, external id), keeping
  /// its local id, or inserts a new one. Returns 1 when a new row was added.
  Future<int> _upsertExternal(
    DatabaseExecutor txn,
    String table,
    Map<String, Object?> row,
    String source,
    String? externalId,
  ) async {
    if (externalId == null) {
      await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      return 1;
    }
    final existing = await txn.query(table,
        columns: ['id'], where: 'source = ? AND external_id = ?', whereArgs: [source, externalId], limit: 1);
    if (existing.isEmpty) {
      await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      return 1;
    }
    final updated = Map<String, Object?>.from(row)..['id'] = existing.first['id'];
    await txn.update(table, updated, where: 'id = ?', whereArgs: [existing.first['id']]);
    return 0;
  }

  /// Removes everything imported from [source] (used when disconnecting).
  Future<void> deleteBySource(String source) async {
    for (final t in [Tables.activityEntries, Tables.workouts, Tables.sleepEntries]) {
      await _db.db.delete(t, where: 'source = ?', whereArgs: [source]);
      _db.notify(t);
    }
  }

  Future<void> deleteEverything() async {
    for (final t in [Tables.activityEntries, Tables.workouts, Tables.sleepEntries]) {
      await _db.db.delete(t);
      _db.notify(t);
    }
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<List<ActivityEntry>> timeline(String date) async {
    final rows = await _db.db.query(Tables.activityEntries,
        where: 'local_date = ?', whereArgs: [date], orderBy: 'start_ms ASC');
    return rows.map(_entryFrom).toList();
  }

  Future<List<Workout>> workoutsOn(String date) async {
    final rows = await _db.db.query(Tables.workouts,
        where: 'local_date = ?', whereArgs: [date], orderBy: 'start_ms ASC');
    return rows.map(_workoutFrom).toList();
  }

  Future<List<Workout>> workoutsBetween(String from, String to) async {
    final rows = await _db.db.query(Tables.workouts,
        where: 'local_date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'start_ms DESC');
    return rows.map(_workoutFrom).toList();
  }

  Future<DailyActivity> daily(String date) async =>
      ActivityMath.summarize(date, await timeline(date), await workoutsOn(date));

  Stream<DailyActivity> watchDaily(String date) => _db.watch(_tables, () => daily(date));

  Stream<List<ActivityEntry>> watchTimeline(String date) =>
      _db.watch({Tables.activityEntries}, () => timeline(date));

  /// Every workout, newest first (History > Activity).
  Stream<List<Workout>> watchAllWorkouts() =>
      _db.watch({Tables.workouts}, () => workoutsBetween('0000-01-01', '9999-12-31'));

  Stream<List<Workout>> watchWorkouts(String date) =>
      _db.watch({Tables.workouts}, () => workoutsOn(date));

  /// Summaries for every day in the range that has data, oldest first.
  Future<List<DailyActivity>> range(String from, String to) async {
    final entryRows = await _db.db.query(Tables.activityEntries,
        where: 'local_date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'start_ms ASC');
    final workoutRows = await _db.db.query(Tables.workouts,
        where: 'local_date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'start_ms ASC');

    final entries = <String, List<ActivityEntry>>{};
    for (final r in entryRows) {
      (entries[r['local_date'] as String] ??= []).add(_entryFrom(r));
    }
    final workouts = <String, List<Workout>>{};
    for (final r in workoutRows) {
      (workouts[r['local_date'] as String] ??= []).add(_workoutFrom(r));
    }
    final days = {...entries.keys, ...workouts.keys}.toList()..sort();
    return [for (final d in days) ActivityMath.summarize(d, entries[d] ?? const [], workouts[d] ?? const [])];
  }

  Stream<List<DailyActivity>> watchRange(String from, String to) => _db.watch(_tables, () => range(from, to));

  Future<List<SleepEntry>> sleepBetween(String from, String to) async {
    final rows = await _db.db.query(Tables.sleepEntries,
        where: 'local_date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'start_ms ASC');
    return rows.map(_sleepFrom).toList();
  }

  Stream<List<SleepEntry>> watchSleep(String from, String to) =>
      _db.watch({Tables.sleepEntries}, () => sleepBetween(from, to));

  /// Everything, for backups.
  Future<BackupActivity> exportAll() async => BackupActivity(
        entries: (await _db.db.query(Tables.activityEntries)).map(_entryFrom).toList(),
        workouts: (await _db.db.query(Tables.workouts)).map(_workoutFrom).toList(),
        sleep: (await _db.db.query(Tables.sleepEntries)).map(_sleepFrom).toList(),
      );

  Future<void> restoreInTransaction(DatabaseExecutor txn, BackupActivity data) async {
    for (final e in data.entries) {
      await txn.insert(Tables.activityEntries, _entryRow(e), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final w in data.workouts) {
      await txn.insert(Tables.workouts, _workoutRow(w), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final s in data.sleep) {
      await txn.insert(Tables.sleepEntries, _sleepRow(s), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ---------------------------------------------------------------------------
  // Rows
  // ---------------------------------------------------------------------------

  Map<String, Object?> _entryRow(ActivityEntry e) => {
        'id': e.id,
        'local_date': DateTimeUtils.dayKey(e.start),
        'start_ms': e.start.millisecondsSinceEpoch,
        'end_ms': e.end.millisecondsSinceEpoch,
        'type': e.type,
        'steps': e.steps,
        'distance_m': e.distanceMeters,
        'active_kcal': e.activeCalories,
        'source': e.source,
        'origin': e.origin,
        'external_id': e.externalId,
      };

  ActivityEntry _entryFrom(Map<String, Object?> r) => ActivityEntry(
        id: r['id'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(r['start_ms'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(r['end_ms'] as int),
        type: r['type'] as String,
        steps: r['steps'] as int,
        distanceMeters: (r['distance_m'] as num).toDouble(),
        activeCalories: (r['active_kcal'] as num).toDouble(),
        source: r['source'] as String,
        origin: r['origin'] as String?,
        externalId: r['external_id'] as String?,
      );

  Map<String, Object?> _workoutRow(Workout w) => {
        'id': w.id,
        'local_date': DateTimeUtils.dayKey(w.start),
        'type': w.type,
        'start_ms': w.start.millisecondsSinceEpoch,
        'end_ms': w.end.millisecondsSinceEpoch,
        'calories': w.calories,
        'calories_estimated': w.caloriesEstimated ? 1 : 0,
        'distance_m': w.distanceMeters,
        'avg_heart_rate': w.avgHeartRate,
        'notes': w.notes,
        'source': w.source,
        'origin': w.origin,
        'external_id': w.externalId,
      };

  Workout _workoutFrom(Map<String, Object?> r) => Workout(
        id: r['id'] as String,
        type: r['type'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(r['start_ms'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(r['end_ms'] as int),
        calories: (r['calories'] as num?)?.toDouble(),
        caloriesEstimated: (r['calories_estimated'] as int) == 1,
        distanceMeters: (r['distance_m'] as num?)?.toDouble(),
        avgHeartRate: r['avg_heart_rate'] as int?,
        notes: r['notes'] as String?,
        source: r['source'] as String,
        origin: r['origin'] as String?,
        externalId: r['external_id'] as String?,
      );

  Map<String, Object?> _sleepRow(SleepEntry s) => {
        'id': s.id,
        // A night belongs to the day you wake up.
        'local_date': DateTimeUtils.dayKey(s.end),
        'start_ms': s.start.millisecondsSinceEpoch,
        'end_ms': s.end.millisecondsSinceEpoch,
        'minutes_asleep': s.minutesAsleep,
        'source': s.source,
        'origin': s.origin,
        'external_id': s.externalId,
      };

  SleepEntry _sleepFrom(Map<String, Object?> r) => SleepEntry(
        id: r['id'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(r['start_ms'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(r['end_ms'] as int),
        minutesAsleep: r['minutes_asleep'] as int,
        source: r['source'] as String,
        origin: r['origin'] as String?,
        externalId: r['external_id'] as String?,
      );
}

class ImportResult {
  const ImportResult(this.added);
  final int added;
}

class BackupActivity {
  const BackupActivity({this.entries = const [], this.workouts = const [], this.sleep = const []});
  final List<ActivityEntry> entries;
  final List<Workout> workouts;
  final List<SleepEntry> sleep;
}
