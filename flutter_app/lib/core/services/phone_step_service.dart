import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/activity.dart';
import '../repositories/activity_repository.dart';

/// The phone's cumulative step counter (steps since the last reboot).
abstract class StepCounterSource {
  Future<bool> hasPermission();
  Future<bool> requestPermission();

  /// Current cumulative count, or null when the phone has no step sensor or
  /// it did not answer in time.
  Future<int?> readCount();
}

class PluginStepCounterSource implements StepCounterSource {
  @override
  Future<bool> hasPermission() async => (await Permission.activityRecognition.status).isGranted;

  @override
  Future<bool> requestPermission() async => (await Permission.activityRecognition.request()).isGranted;

  @override
  Future<int?> readCount() async {
    try {
      final e = await Pedometer.stepCountStream.first.timeout(const Duration(seconds: 6));
      return e.steps;
    } catch (e) {
      debugPrint('[PhoneSteps] no reading: $e');
      return null;
    }
  }
}

enum PhoneStepResult { off, noPermission, noSensor, baselineSet, nothingNew, recorded }

/// Records steps from the phone's own sensor for people who do not use
/// Health Connect.
///
/// The sensor only reports a running total, so each sync stores the steps
/// gained since the previous sync as one record covering exactly that span.
/// The first sync only sets a starting point: steps taken before the feature
/// was switched on are never invented.
class PhoneStepService {
  PhoneStepService(this._db, this._activity, this._source, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final ActivityRepository _activity;
  final StepCounterSource _source;
  final DateTime Function() _clock;

  static const _enabledKey = 'phone_steps_enabled';
  static const _countKey = 'phone_steps_last_count';
  static const _msKey = 'phone_steps_last_ms';

  /// Longest span a single record may cover; older gaps are not back-filled.
  static const maxSpan = Duration(hours: 12);

  Future<bool> isEnabled() async => await _db.getKv(_enabledKey) == '1';

  /// Asks for permission and switches the feature on. Returns whether it is on.
  Future<bool> enable() async {
    if (!await _source.hasPermission() && !await _source.requestPermission()) return false;
    await _db.setKv(_enabledKey, '1');
    await _db.setKv(_countKey, null);
    await _db.setKv(_msKey, null);
    await sync();
    return true;
  }

  /// Switches off. Steps already recorded stay unless [deleteData].
  Future<void> disable({bool deleteData = false}) async {
    await _db.setKv(_enabledKey, null);
    await _db.setKv(_countKey, null);
    await _db.setKv(_msKey, null);
    if (deleteData) await _activity.deleteBySource(DataSource.phoneSensor);
  }

  Future<PhoneStepResult> sync() async {
    if (!await isEnabled()) return PhoneStepResult.off;
    if (!await _source.hasPermission()) return PhoneStepResult.noPermission;
    final count = await _source.readCount();
    if (count == null) return PhoneStepResult.noSensor;

    final now = _clock();
    final lastCount = int.tryParse(await _db.getKv(_countKey) ?? '');
    final lastMs = int.tryParse(await _db.getKv(_msKey) ?? '');
    await _db.setKv(_countKey, '$count');
    await _db.setKv(_msKey, '${now.millisecondsSinceEpoch}');
    if (lastCount == null || lastMs == null) return PhoneStepResult.baselineSet;

    // The counter restarts from zero after a reboot: everything it shows now
    // was taken since then.
    final delta = count >= lastCount ? count - lastCount : count;
    if (delta <= 0) return PhoneStepResult.nothingNew;

    var start = DateTime.fromMillisecondsSinceEpoch(lastMs);
    if (now.difference(start) > maxSpan) start = now.subtract(maxSpan);
    if (!now.isAfter(start)) return PhoneStepResult.nothingNew;

    await _activity.importBatch(entries: [
      ActivityEntry(
        id: 'act_${const Uuid().v4()}',
        start: start,
        end: now,
        steps: delta,
        // A rough walking stride; shown as an estimate nowhere else.
        distanceMeters: delta * 0.75,
        source: DataSource.phoneSensor,
        externalId: 'sensor_${now.millisecondsSinceEpoch}',
      ),
    ]);
    return PhoneStepResult.recorded;
  }
}
