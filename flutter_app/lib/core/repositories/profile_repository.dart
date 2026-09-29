import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/user_profile.dart';
import '../services/image_store.dart';
import '../utils/datetime_utils.dart';

/// Persists the single on-device [UserProfile].
class ProfileRepository {
  ProfileRepository(this._db, this._images);

  final AppDatabase _db;
  final ImageStore _images;

  Future<UserProfile?> get() async {
    final rows = await _db.db.query(Tables.profiles,
        where: 'uid = ?', whereArgs: [AppConfig.localUserId], limit: 1);
    return rows.isEmpty ? null : _decode(rows.first['data'] as String);
  }

  Stream<UserProfile?> watch() => _db.watch({Tables.profiles}, get);

  Future<void> save(UserProfile profile) async {
    final normalized = profile.copyWith(uid: AppConfig.localUserId);
    final map = normalized.toMap();
    // Persist portable relative image paths only.
    _setPath(map, 'photoURL');
    _setPath(map, 'bodyScanURL');
    await _db.db.insert(
      Tables.profiles,
      {
        'uid': AppConfig.localUserId,
        'data': jsonEncode(map),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _db.notify(Tables.profiles);
    await _recordWeight(normalized.weight);
  }

  /// Adds a weight-history point when the weight changed since the last one.
  Future<void> _recordWeight(double? kg) async {
    if (kg == null || kg < 20 || kg > 400) return;
    final last = await _db.db.query(Tables.weightEntries, orderBy: 'measured_ms DESC', limit: 1);
    if (last.isNotEmpty && ((last.first['weight_kg'] as num).toDouble() - kg).abs() < 0.01) return;
    final now = DateTime.now();
    await _db.db.insert(Tables.weightEntries, {
      'id': 'w_${now.microsecondsSinceEpoch}',
      'weight_kg': kg,
      'measured_ms': now.millisecondsSinceEpoch,
      'local_date': DateTimeUtils.dayKey(now),
    });
    _db.notify(Tables.weightEntries);
  }

  /// Recorded weights between two day keys, oldest first.
  Future<List<WeightPoint>> weights(String from, String to) async {
    final rows = await _db.db.query(Tables.weightEntries,
        where: 'local_date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'measured_ms ASC');
    return [
      for (final r in rows) WeightPoint(r['local_date'] as String, (r['weight_kg'] as num).toDouble()),
    ];
  }

  /// The last weight recorded before [day] (to anchor a trend).
  Future<WeightPoint?> weightBefore(String day) async {
    final rows = await _db.db.query(Tables.weightEntries,
        where: 'local_date < ?', whereArgs: [day], orderBy: 'measured_ms DESC', limit: 1);
    if (rows.isEmpty) return null;
    return WeightPoint(rows.first['local_date'] as String, (rows.first['weight_kg'] as num).toDouble());
  }

  Future<void> deleteAll() async {
    await _db.db.delete(Tables.profiles);
    await _db.db.delete(Tables.weightEntries);
    _db.notify(Tables.profiles);
    _db.notify(Tables.weightEntries);
  }

  UserProfile _decode(String json) {
    final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
    _resolvePath(map, 'photoURL');
    _resolvePath(map, 'bodyScanURL');
    return UserProfile.fromMap(map);
  }

  void _setPath(Map<String, dynamic> map, String key) {
    final v = map[key] as String?;
    if (v == null) return;
    final rel = _images.relativize(v);
    if (rel == null) {
      map.remove(key); // never persist a transient/external path
    } else {
      map[key] = rel;
    }
  }

  void _resolvePath(Map<String, dynamic> map, String key) {
    final v = map[key] as String?;
    final abs = _images.absolutePath(v);
    if (abs == null) {
      map.remove(key);
    } else {
      map[key] = abs;
    }
  }
}

class WeightPoint {
  const WeightPoint(this.date, this.kg);
  final String date;
  final double kg;
}
