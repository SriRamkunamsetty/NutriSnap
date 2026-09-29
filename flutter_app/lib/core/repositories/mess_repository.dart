import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/mess.dart';

/// Messes, their daily menus and which meals were logged. Fully local: menus
/// are entered by the user (or copied from an earlier day), so MessOS works
/// with no connection at all.
class MessRepository {
  MessRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _activeKey = 'active_mess_id';
  static const _tables = {Tables.messes, Tables.messMenus, Tables.messMeals};

  // ---------------------------------------------------------------------------
  // Messes
  // ---------------------------------------------------------------------------

  Future<Mess> createMess({required String college, required String hostel, required String name}) async {
    final mess = Mess(
      id: 'mess_${_uuid.v4()}',
      college: college.trim(),
      hostel: hostel.trim(),
      name: name.trim(),
    );
    await _db.db.insert(Tables.messes, {
      'id': mess.id,
      'college': mess.college,
      'hostel': mess.hostel,
      'name': mess.name,
      'created_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await setActive(mess.id);
    _db.notify(Tables.messes);
    return mess;
  }

  Future<List<Mess>> messes() async {
    final rows = await _db.db.query(Tables.messes, orderBy: 'created_ms ASC');
    return rows.map(_messFrom).toList();
  }

  Stream<List<Mess>> watchMesses() => _db.watch({Tables.messes, Tables.kv}, messes);

  /// The mess currently selected; falls back to the first one.
  Future<Mess?> active() async {
    final all = await messes();
    if (all.isEmpty) return null;
    final id = await _db.getKv(_activeKey);
    return all.firstWhere((m) => m.id == id, orElse: () => all.first);
  }

  Stream<Mess?> watchActive() => _db.watch({Tables.messes, Tables.kv}, active);

  Future<void> setActive(String id) => _db.setKv(_activeKey, id);

  Future<void> deleteMess(String id) async {
    await _db.db.delete(Tables.messes, where: 'id = ?', whereArgs: [id]); // menus cascade
    if (await _db.getKv(_activeKey) == id) await _db.setKv(_activeKey, null);
    for (final t in _tables) {
      _db.notify(t);
    }
  }

  // ---------------------------------------------------------------------------
  // Menus
  // ---------------------------------------------------------------------------

  Future<MessMenu?> menu(String messId, String date) async {
    final rows = await _db.db.query(Tables.messMenus,
        where: 'mess_id = ? AND local_date = ?', whereArgs: [messId, date], limit: 1);
    if (rows.isEmpty) return null;
    final id = rows.first['id'] as String;
    final meals = await _db.db.query(Tables.messMeals, where: 'menu_id = ?', whereArgs: [id]);
    return MessMenu(
      id: id,
      messId: messId,
      date: date,
      meals: [for (final m in meals) _mealFrom(m)]
        ..sort((a, b) => MealType.all.indexOf(a.mealType).compareTo(MealType.all.indexOf(b.mealType))),
    );
  }

  Stream<MessMenu?> watchMenu(String messId, String date) => _db.watch(_tables, () => menu(messId, date));

  /// Sets the dishes for one meal (creating the day's menu on first use).
  /// An empty list clears that meal.
  Future<MessMeal?> saveMeal({
    required String messId,
    required String date,
    required String mealType,
    required List<MessDish> dishes,
  }) async {
    MessMeal? saved;
    await _db.db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await txn.query(Tables.messMenus,
          where: 'mess_id = ? AND local_date = ?', whereArgs: [messId, date], limit: 1);
      var menuId = existing.isEmpty ? null : existing.first['id'] as String;

      if (dishes.isEmpty) {
        if (menuId != null) {
          await txn.delete(Tables.messMeals, where: 'menu_id = ? AND meal_type = ?', whereArgs: [menuId, mealType]);
        }
        return;
      }
      if (menuId == null) {
        menuId = 'menu_${_uuid.v4()}';
        await txn.insert(Tables.messMenus,
            {'id': menuId, 'mess_id': messId, 'local_date': date, 'updated_ms': now});
      } else {
        await txn.update(Tables.messMenus, {'updated_ms': now}, where: 'id = ?', whereArgs: [menuId]);
      }

      final prior = await txn.query(Tables.messMeals,
          where: 'menu_id = ? AND meal_type = ?', whereArgs: [menuId, mealType], limit: 1);
      final mealId = prior.isEmpty ? 'mm_${_uuid.v4()}' : prior.first['id'] as String;
      await txn.insert(
        Tables.messMeals,
        {
          'id': mealId,
          'menu_id': menuId,
          'meal_type': mealType,
          'dishes': jsonEncode([for (final d in dishes) d.toJson()]),
          'logged_scan_id': prior.isEmpty ? null : prior.first['logged_scan_id'],
          'updated_ms': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      saved = MessMeal(
        id: mealId,
        menuId: menuId,
        mealType: mealType,
        dishes: dishes,
        loggedScanId: prior.isEmpty ? null : prior.first['logged_scan_id'] as String?,
      );
    });
    for (final t in _tables) {
      _db.notify(t);
    }
    return saved;
  }

  Future<void> setLogged(String mealId, String? scanId) async {
    await _db.db.update(Tables.messMeals, {'logged_scan_id': scanId}, where: 'id = ?', whereArgs: [mealId]);
    _db.notify(Tables.messMeals);
  }

  /// Copies every meal of [fromDate] onto [toDate] (logged flags are not copied).
  /// Returns how many meals were copied.
  Future<int> copyMenu(String messId, String fromDate, String toDate) async {
    final source = await menu(messId, fromDate);
    if (source == null) return 0;
    var n = 0;
    for (final m in source.meals) {
      await saveMeal(messId: messId, date: toDate, mealType: m.mealType, dishes: m.dishes);
      n++;
    }
    return n;
  }

  /// Dates that have a saved menu, newest first (menu history).
  Future<List<String>> menuDates(String messId, {int limit = 30}) async {
    final rows = await _db.db.query(Tables.messMenus,
        columns: ['local_date'],
        where: 'mess_id = ?',
        whereArgs: [messId],
        orderBy: 'local_date DESC',
        limit: limit);
    return [for (final r in rows) r['local_date'] as String];
  }

  Stream<List<String>> watchMenuDates(String messId) => _db.watch(_tables, () => menuDates(messId));

  Future<void> deleteEverything() async {
    await _db.db.delete(Tables.messes);
    await _db.setKv(_activeKey, null);
    for (final t in _tables) {
      _db.notify(t);
    }
  }

  // ---------------------------------------------------------------------------

  Mess _messFrom(Map<String, Object?> r) => Mess(
        id: r['id'] as String,
        college: r['college'] as String,
        hostel: r['hostel'] as String,
        name: r['name'] as String,
      );

  MessMeal _mealFrom(Map<String, Object?> r) {
    final raw = jsonDecode(r['dishes'] as String) as List;
    return MessMeal(
      id: r['id'] as String,
      menuId: r['menu_id'] as String,
      mealType: r['meal_type'] as String,
      dishes: [for (final d in raw) MessDish.fromJson(Map<String, dynamic>.from(d as Map))],
      loggedScanId: r['logged_scan_id'] as String?,
    );
  }
}
