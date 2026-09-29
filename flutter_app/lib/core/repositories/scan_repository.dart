import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/meal_item.dart';
import '../models/scan_result.dart';
import '../services/image_store.dart';
import '../utils/datetime_utils.dart';

/// Meal / body-scan log. A meal is one `scans` row plus its `meal_items`.
///
/// Daily totals are computed from these rows by `SummaryRepository`, and a
/// meal's own totals are always the sum of its items, so adding, editing and
/// deleting can never leave anything inconsistent.
class ScanRepository {
  ScanRepository(this._db, this._images);

  final AppDatabase _db;
  final ImageStore _images;
  static const _uuid = Uuid();

  /// Inserts a meal and its items in one transaction.
  /// [scan.imageUrl] must be inside the [ImageStore] (or null).
  Future<ScanResult> add(ScanResult scan) async {
    final at = DateTimeUtils.parse(scan.timestamp) ?? DateTime.now();
    final saved = _prepare(scan.copyWith(
      id: scan.id.isEmpty ? 'scan_${_uuid.v4()}' : scan.id,
      userId: AppConfig.localUserId,
      timestamp: at.toIso8601String(),
    ));
    await _db.db.transaction((txn) async {
      await txn.insert(Tables.scans, rowOf(saved),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _writeItems(txn, saved);
    });
    _db.notify(Tables.scans);
    return saved;
  }

  /// Insert-or-replace, used when restoring a backup.
  Future<void> upsertAll(List<ScanResult> scans) async {
    if (scans.isEmpty) return;
    await _db.db.transaction((txn) async {
      for (final raw in scans) {
        final s = _prepare(raw);
        await txn.insert(Tables.scans, rowOf(s),
            conflictAlgorithm: ConflictAlgorithm.replace);
        await _writeItems(txn, s);
      }
    });
    _db.notify(Tables.scans);
  }

  /// Upserts inside a caller-owned transaction (used by backup restore so the
  /// whole restore stays all-or-nothing).
  Future<void> upsertInTransaction(DatabaseExecutor txn, Iterable<ScanResult> scans) async {
    for (final raw in scans) {
      final s = _prepare(raw);
      await txn.insert(Tables.scans, rowOf(s), conflictAlgorithm: ConflictAlgorithm.replace);
      await _writeItems(txn, s);
    }
  }

  /// Replaces a meal's fields and items (a meal keeps the day it was logged).
  Future<ScanResult> update(ScanResult scan) async {
    final at = DateTimeUtils.parse(scan.timestamp) ?? DateTime.now();
    final saved = _prepare(scan.copyWith(timestamp: at.toIso8601String()));
    final row = rowOf(saved)
      ..remove('id')
      ..remove('logged_at')
      ..remove('local_date');
    await _db.db.transaction((txn) async {
      await txn.update(Tables.scans, row, where: 'id = ?', whereArgs: [saved.id]);
      await _writeItems(txn, saved);
    });
    _db.notify(Tables.scans);
    return saved;
  }

  Future<ScanResult?> getById(String id) async {
    final rows = await _db.db
        .query(Tables.scans, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : (await _hydrate(rows)).first;
  }

  Future<List<ScanResult>> recent({int limit = 15, int offset = 0}) async {
    final rows = await _db.db.query(Tables.scans,
        where: 'user_id = ?',
        whereArgs: [AppConfig.localUserId],
        orderBy: 'logged_at DESC',
        limit: limit,
        offset: offset > 0 ? offset : null);
    return _hydrate(rows);
  }

  Future<List<ScanResult>> all() => recent(limit: -1);

  Stream<List<ScanResult>> watchAll({int limit = 1000}) =>
      _db.watch({Tables.scans}, () => recent(limit: limit));

  Future<List<ScanResult>> olderThan(DateTime cutoff) async {
    final rows = await _db.db.query(Tables.scans,
        where: 'user_id = ? AND logged_at < ?',
        whereArgs: [AppConfig.localUserId, cutoff.millisecondsSinceEpoch],
        orderBy: 'logged_at ASC');
    return _hydrate(rows);
  }

  /// Deletes the scan (its items cascade) and its image file.
  Future<void> delete(String id) async {
    final existing = await getById(id);
    await _db.db.delete(Tables.scans, where: 'id = ?', whereArgs: [id]);
    _db.notify(Tables.scans);
    await _images.delete(_images.relativize(existing?.imageUrl));
  }

  /// Deletes many scans (and their images) atomically. Returns rows removed.
  Future<int> deleteAll(Iterable<ScanResult> scans) async {
    if (scans.isEmpty) return 0;
    var removed = 0;
    await _db.db.transaction((txn) async {
      for (final s in scans) {
        removed +=
            await txn.delete(Tables.scans, where: 'id = ?', whereArgs: [s.id]);
      }
    });
    _db.notify(Tables.scans);
    for (final s in scans) {
      await _images.delete(_images.relativize(s.imageUrl));
    }
    return removed;
  }

  Future<void> deleteEverything() async {
    await _db.db.delete(Tables.scans); // items cascade
    _db.notify(Tables.scans);
  }

  // ---------------------------------------------------------------------------
  // Rows
  // ---------------------------------------------------------------------------

  /// Guarantees every food meal has at least one item and that its totals
  /// equal the sum of its items.
  ScanResult _prepare(ScanResult s) {
    var scan = s;
    if (scan.isFood && scan.items.isEmpty && scan.calories + scan.protein + scan.carbs + scan.fats > 0) {
      scan = scan.copyWith(items: [
        MealItem(
          id: 'item_${_uuid.v4()}',
          name: scan.foodName,
          estimatedWeight: 1,
          servingUnit: ServingUnit.serving,
          calories: scan.calories.toDouble(),
          protein: scan.protein.toDouble(),
          carbs: scan.carbs.toDouble(),
          fats: scan.fats.toDouble(),
          confidence: scan.confidence <= 0 ? 1.0 : scan.confidence,
          source: ItemSource.manual,
        ),
      ]);
    }
    // Items without an id (e.g. built in the editor) get one.
    if (scan.items.any((i) => i.id.isEmpty)) {
      scan = scan.copyWith(items: [
        for (final i in scan.items)
          i.id.isEmpty ? i.copyWith(id: 'item_${_uuid.v4()}') : i,
      ]);
    }
    return scan.withTotalsFromItems();
  }

  Future<void> _writeItems(DatabaseExecutor txn, ScanResult scan) async {
    await txn.delete(Tables.mealItems, where: 'scan_id = ?', whereArgs: [scan.id]);
    final batch = txn.batch();
    for (final row in itemRowsOf(scan)) {
      // An item id already used by a *different* meal (e.g. a meal logged again
      // from a template) must not steal that meal's row: give it a fresh id.
      final clash = await txn.query(Tables.mealItems,
          columns: ['scan_id'], where: 'id = ?', whereArgs: [row['id']], limit: 1);
      if (clash.isNotEmpty && clash.first['scan_id'] != scan.id) {
        row['id'] = 'item_${_uuid.v4()}';
      }
      batch.insert(Tables.mealItems, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// `meal_items` rows for [s] (used here and by the backup restore).
  List<Map<String, Object?>> itemRowsOf(ScanResult s) => [
        for (var i = 0; i < s.items.length; i++)
          {
            'id': s.items[i].id,
            'scan_id': s.id,
            'position': i,
            'name': s.items[i].name,
            'category': s.items[i].category,
            'weight': s.items[i].estimatedWeight,
            'unit': s.items[i].servingUnit,
            'calories': s.items[i].calories,
            'protein': s.items[i].protein,
            'carbs': s.items[i].carbs,
            'fats': s.items[i].fats,
            'confidence': s.items[i].confidence,
            'source': s.items[i].source,
            'original_name': s.items[i].originalName,
            'original_calories': s.items[i].originalCalories,
          },
      ];

  Map<String, Object?> rowOf(ScanResult s) {
    final at = DateTimeUtils.parse(s.timestamp) ?? DateTime.now();
    return {
      'id': s.id,
      'user_id': AppConfig.localUserId,
      'food_name': s.foodName,
      'type': s.type ?? 'food',
      'description': s.description,
      'details': s.details,
      'calories': s.calories,
      'protein': s.protein,
      'carbs': s.carbs,
      'fats': s.fats,
      'fat_estimate': s.fatEstimate,
      'confidence': s.confidence,
      'image_path': _images.relativize(s.imageUrl),
      'logged_at': at.millisecondsSinceEpoch,
      'local_date': DateTimeUtils.dayKey(at),
      'model_version': s.modelVersion,
      'analysis_status': s.analysisStatus,
    };
  }

  /// Turns rows into [ScanResult]s, loading all their items in one query per
  /// chunk (never one query per meal).
  Future<List<ScanResult>> _hydrate(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id'] as String).toList();
    final byScan = <String, List<MealItem>>{};

    const chunk = 400; // stay under SQLite's variable limit
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
      final marks = List.filled(part.length, '?').join(',');
      final items = await _db.db.rawQuery(
        'SELECT * FROM ${Tables.mealItems} WHERE scan_id IN ($marks) ORDER BY scan_id, position',
        part,
      );
      for (final r in items) {
        (byScan[r['scan_id'] as String] ??= []).add(_itemFrom(r));
      }
    }
    return [for (final r in rows) _fromRow(r, byScan[r['id']] ?? const [])];
  }

  MealItem _itemFrom(Map<String, Object?> r) => MealItem(
        id: r['id'] as String,
        name: r['name'] as String,
        category: r['category'] as String,
        estimatedWeight: (r['weight'] as num).toDouble(),
        servingUnit: r['unit'] as String,
        calories: (r['calories'] as num).toDouble(),
        protein: (r['protein'] as num).toDouble(),
        carbs: (r['carbs'] as num).toDouble(),
        fats: (r['fats'] as num).toDouble(),
        confidence: (r['confidence'] as num).toDouble(),
        source: r['source'] as String,
        originalName: r['original_name'] as String?,
        originalCalories: (r['original_calories'] as num?)?.toDouble(),
      );

  ScanResult _fromRow(Map<String, Object?> r, List<MealItem> items) {
    return ScanResult(
      id: r['id'] as String,
      userId: r['user_id'] as String,
      foodName: r['food_name'] as String,
      type: r['type'] as String?,
      description: r['description'] as String?,
      details: r['details'] as String?,
      calories: r['calories'] as int,
      protein: r['protein'] as int,
      carbs: r['carbs'] as int,
      fats: r['fats'] as int,
      fatEstimate: (r['fat_estimate'] as num?)?.toDouble(),
      confidence: (r['confidence'] as num).toDouble(),
      imageUrl: _images.absolutePath(r['image_path'] as String?),
      timestamp: DateTime.fromMillisecondsSinceEpoch(r['logged_at'] as int)
          .toIso8601String(),
      items: items,
      modelVersion: r['model_version'] as String?,
      analysisStatus: r['analysis_status'] as String? ?? AnalysisStatus.confirmed,
    );
  }
}
