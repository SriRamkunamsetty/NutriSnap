import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/daily_summary.dart';
import '../utils/datetime_utils.dart';

/// Daily nutrition + hydration totals.
///
/// Calories/macros are aggregated from `scans`; hydration lives in
/// `water_intake`. Nothing is denormalised.
class SummaryRepository {
  SummaryRepository(this._db);

  final AppDatabase _db;
  static const _tables = {Tables.scans, Tables.waterIntake};

  Future<DailySummary> forDate(String date) async {
    final days = await range(date, date);
    return days.isEmpty ? DailySummary.empty(date) : days.first;
  }

  Stream<DailySummary> watchDate(String date) =>
      _db.watch(_tables, () => forDate(date));

  /// Watches today; rolls over automatically after midnight when the caller
  /// re-subscribes (the provider does this on app resume).
  Stream<DailySummary> watchToday() =>
      _db.watch(_tables, () => forDate(DateTimeUtils.today()));

  /// Days with any data between [from] and [to] inclusive (`yyyy-MM-dd`).
  Future<List<DailySummary>> range(String from, String to) async {
    final rows = await _db.db.rawQuery('''
      SELECT d AS date,
             SUM(cal) AS calories, SUM(p) AS protein, SUM(c) AS carbs,
             SUM(f) AS fats, SUM(w) AS water
      FROM (
        SELECT local_date AS d, calories AS cal, protein AS p, carbs AS c,
               fats AS f, 0 AS w
        FROM ${Tables.scans}
        WHERE user_id = ? AND local_date BETWEEN ? AND ?
        UNION ALL
        SELECT local_date, 0, 0, 0, 0, total_ml
        FROM ${Tables.waterIntake}
        WHERE user_id = ? AND local_date BETWEEN ? AND ?
      )
      GROUP BY d
      ORDER BY d ASC
    ''', [
      AppConfig.localUserId, from, to,
      AppConfig.localUserId, from, to,
    ]);
    return rows
        .map((r) => DailySummary(
              date: r['date'] as String,
              totalCalories: (r['calories'] as num?)?.round() ?? 0,
              totalProtein: (r['protein'] as num?)?.round() ?? 0,
              totalCarbs: (r['carbs'] as num?)?.round() ?? 0,
              totalFats: (r['fats'] as num?)?.round() ?? 0,
              totalWater: (r['water'] as num?)?.round() ?? 0,
            ))
        .toList();
  }

  Stream<List<DailySummary>> watchRange(String from, String to) =>
      _db.watch(_tables, () => range(from, to));

  /// Adds (or subtracts, if negative) hydration for [date] (default today).
  /// Clamped to `0..maxWaterPerDayMl`. Returns the new total.
  Future<int> addWater(int ml, {String? date}) async {
    final day = date ?? DateTimeUtils.today();
    late int total;
    await _db.db.transaction((txn) async {
      final rows = await txn.query(Tables.waterIntake,
          columns: ['total_ml'],
          where: 'user_id = ? AND local_date = ?',
          whereArgs: [AppConfig.localUserId, day]);
      final current = rows.isEmpty ? 0 : rows.first['total_ml'] as int;
      total = (current + ml).clamp(0, AppConfig.maxWaterPerDayMl);
      await txn.insert(
        Tables.waterIntake,
        {'user_id': AppConfig.localUserId, 'local_date': day, 'total_ml': total},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _db.notify(Tables.waterIntake);
    return total;
  }

  /// Raw water rows (for backups and archives).
  Future<Map<String, int>> allWater({String? before}) async {
    final rows = await _db.db.query(Tables.waterIntake,
        where: before == null ? 'user_id = ?' : 'user_id = ? AND local_date < ?',
        whereArgs: [AppConfig.localUserId, if (before != null) before]);
    return {
      for (final r in rows) r['local_date'] as String: r['total_ml'] as int,
    };
  }

  Future<void> restoreWater(Map<String, int> water) async {
    if (water.isEmpty) return;
    await _db.db.transaction((txn) async {
      final batch = txn.batch();
      water.forEach((day, ml) {
        batch.insert(
          Tables.waterIntake,
          {
            'user_id': AppConfig.localUserId,
            'local_date': day,
            'total_ml': ml.clamp(0, AppConfig.maxWaterPerDayMl),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await batch.commit(noResult: true);
    });
    _db.notify(Tables.waterIntake);
  }

  Future<int> deleteWaterBefore(String date) async {
    final n = await _db.db.delete(Tables.waterIntake,
        where: 'user_id = ? AND local_date < ?',
        whereArgs: [AppConfig.localUserId, date]);
    _db.notify(Tables.waterIntake);
    return n;
  }

  Future<void> deleteEverything() async {
    await _db.db.delete(Tables.waterIntake);
    _db.notify(Tables.waterIntake);
  }
}
