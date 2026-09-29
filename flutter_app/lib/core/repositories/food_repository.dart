import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/food.dart';

/// The local food knowledge base: built-in regional reference foods plus the
/// user's own. Everything is searchable offline.
class FoodRepository {
  FoodRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _seedKey = 'foods_seed_version';

  // ---------------------------------------------------------------------------
  // Seeding
  // ---------------------------------------------------------------------------

  /// Loads the built-in dataset. Safe to call on every start: it only does
  /// work when the bundled data version changes, and it never touches or
  /// removes the user's custom foods or usage history.
  Future<void> ensureSeeded(String datasetJson) async {
    final data = jsonDecode(datasetJson) as Map<String, dynamic>;
    final version = (data['version'] as num?)?.toInt() ?? 1;
    final current = int.tryParse(await _db.getKv(_seedKey) ?? '') ?? 0;
    if (current >= version) return;

    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.75;
    final list = (data['foods'] as List).cast<Map<String, dynamic>>();
    final ids = <String>{};

    await _db.db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final j in list) {
        final food = Food.fromJson(j, confidence: confidence);
        ids.add(food.id);
        final existing = await txn.query(Tables.foods,
            columns: ['use_count', 'last_used_ms', 'created_ms'], where: 'id = ?', whereArgs: [food.id], limit: 1);
        final row = _row(food, createdMs: existing.isEmpty ? now : existing.first['created_ms'] as int);
        if (existing.isNotEmpty) {
          // Refresh reference data, keep the user's usage stats.
          row['use_count'] = existing.first['use_count'];
          row['last_used_ms'] = existing.first['last_used_ms'];
        }
        await txn.insert(Tables.foods, row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      // Drop reference foods that were removed from the dataset (never custom ones).
      final built = await txn.query(Tables.foods, columns: ['id'], where: 'is_custom = 0');
      for (final r in built) {
        if (!ids.contains(r['id'])) {
          await txn.delete(Tables.foods, where: 'id = ?', whereArgs: [r['id']]);
        }
      }
    });
    await _db.setKv(_seedKey, '$version');
    _db.notify(Tables.foods);
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Text + tag search. Matches every word of [query] against names and
  /// aliases; exact and prefix matches rank first, then frequently used foods.
  Future<List<Food>> search(
    String query, {
    Set<String> tags = const {},
    bool customOnly = false,
    int limit = 60,
    int offset = 0,
  }) async {
    final norm = normalizeFoodName(query);
    final tokens = norm.isEmpty ? <String>[] : norm.split(' ');
    final where = <String>[];
    final args = <Object?>[];

    for (final t in tokens) {
      where.add('search_text LIKE ?');
      args.add('%$t%');
    }
    for (final tag in tags) {
      where.add("(',' || lower(tags) || ',') LIKE ?");
      args.add('%,${tag.toLowerCase()},%');
    }
    if (customOnly) where.add('is_custom = 1');

    var order = 'use_count DESC, name COLLATE NOCASE ASC';
    final orderArgs = <Object?>[];
    if (norm.isNotEmpty) {
      order = '''
        CASE WHEN lower(name) = ? THEN 0
             WHEN lower(name) LIKE ? THEN 1
             WHEN lower(name) LIKE ? THEN 2
             WHEN search_text LIKE ? THEN 3
             ELSE 4 END,
        use_count DESC, name COLLATE NOCASE ASC''';
      orderArgs.addAll([norm, '$norm%', '%$norm%', '$norm%']);
    }

    final sql = 'SELECT * FROM ${Tables.foods}'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY $order LIMIT $limit${offset > 0 ? ' OFFSET $offset' : ''}';
    final rows = await _db.db.rawQuery(sql, [...args, ...orderArgs]);
    return rows.map(_from).toList();
  }

  Future<Food?> byId(String id) async {
    final r = await _db.db.query(Tables.foods, where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : _from(r.first);
  }

  /// Exact (normalised) name or alias match; null when nothing matches.
  Future<Food?> findByName(String name) async {
    final norm = normalizeFoodName(name);
    if (norm.isEmpty) return null;
    final rows = await _db.db.query(
      Tables.foods,
      where: 'search_text LIKE ?',
      whereArgs: ['%$norm%'],
      orderBy: 'is_custom DESC, use_count DESC',
      limit: 25,
    );
    for (final r in rows) {
      final f = _from(r);
      if (normalizeFoodName(f.name) == norm || f.aliases.any((a) => normalizeFoodName(a) == norm)) return f;
    }
    return null;
  }

  Future<List<Food>> recent({int limit = 12}) async {
    final rows = await _db.db.query(Tables.foods,
        where: 'last_used_ms IS NOT NULL', orderBy: 'last_used_ms DESC', limit: limit);
    return rows.map(_from).toList();
  }

  Future<List<Food>> frequent({int limit = 12}) async {
    final rows = await _db.db.query(Tables.foods,
        where: 'use_count > 0', orderBy: 'use_count DESC, last_used_ms DESC', limit: limit);
    return rows.map(_from).toList();
  }

  Future<List<Food>> custom() async {
    final rows = await _db.db.query(Tables.foods, where: 'is_custom = 1', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(_from).toList();
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.db.rawQuery('SELECT COUNT(*) FROM ${Tables.foods}')) ?? 0;

  Stream<List<Food>> watchCustom() => _db.watch({Tables.foods}, custom);
  Stream<List<Food>> watchRecent() => _db.watch({Tables.foods}, recent);
  Stream<List<Food>> watchFrequent() => _db.watch({Tables.foods}, frequent);

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<Food> saveCustom(Food food) async {
    final id = food.isCustom && food.id.isNotEmpty ? food.id : 'custom_${_uuid.v4()}';
    final saved = Food(
      id: id,
      name: food.name.trim(),
      aliases: food.aliases,
      tags: food.tags,
      category: food.category,
      serving: food.serving,
      servingGrams: food.servingGrams,
      calories: food.calories,
      protein: food.protein,
      carbs: food.carbs,
      fats: food.fats,
      fiber: food.fiber,
      source: Food.customSource,
      confidence: 1.0,
      isCustom: true,
      useCount: food.useCount,
      lastUsed: food.lastUsed,
    );
    final existing = await _db.db.query(Tables.foods, columns: ['created_ms'], where: 'id = ?', whereArgs: [id], limit: 1);
    await _db.db.insert(
      Tables.foods,
      _row(saved, createdMs: existing.isEmpty ? DateTime.now().millisecondsSinceEpoch : existing.first['created_ms'] as int),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _db.notify(Tables.foods);
    return saved;
  }

  /// Deletes a custom food. Built-in foods can't be removed.
  Future<bool> deleteCustom(String id) async {
    final n = await _db.db.delete(Tables.foods, where: 'id = ? AND is_custom = 1', whereArgs: [id]);
    if (n > 0) _db.notify(Tables.foods);
    return n > 0;
  }

  Future<void> markUsed(String id, {DateTime? at}) async {
    await _db.db.rawUpdate(
      'UPDATE ${Tables.foods} SET use_count = use_count + 1, last_used_ms = ? WHERE id = ?',
      [(at ?? DateTime.now()).millisecondsSinceEpoch, id],
    );
    _db.notify(Tables.foods);
  }

  /// Removes the user's custom foods and usage history (built-ins stay).
  Future<void> resetUserData() async {
    await _db.db.delete(Tables.foods, where: 'is_custom = 1');
    await _db.db.update(Tables.foods, {'use_count': 0, 'last_used_ms': null});
    _db.notify(Tables.foods);
  }

  Future<void> deleteEverything() async {
    await _db.db.delete(Tables.foods);
    await _db.setKv(_seedKey, null);
    _db.notify(Tables.foods);
  }

  // ---------------------------------------------------------------------------

  Map<String, Object?> _row(Food f, {required int createdMs}) => {
        'id': f.id,
        'name': f.name,
        'aliases': f.aliases.join('|'),
        'tags': f.tags.join(','),
        'category': f.category,
        'serving': f.serving,
        'serving_grams': f.servingGrams,
        'calories': f.calories,
        'protein': f.protein,
        'carbs': f.carbs,
        'fats': f.fats,
        'fiber': f.fiber,
        'source': f.source,
        'confidence': f.confidence,
        'is_custom': f.isCustom ? 1 : 0,
        'search_text': normalizeFoodName('${f.name} ${f.aliases.join(' ')}'),
        'use_count': f.useCount,
        'last_used_ms': f.lastUsed?.millisecondsSinceEpoch,
        'created_ms': createdMs,
      };

  Food _from(Map<String, Object?> r) => Food(
        id: r['id'] as String,
        name: r['name'] as String,
        aliases: (r['aliases'] as String).isEmpty ? const [] : (r['aliases'] as String).split('|'),
        tags: (r['tags'] as String).isEmpty ? const [] : (r['tags'] as String).split(','),
        category: r['category'] as String,
        serving: r['serving'] as String,
        servingGrams: (r['serving_grams'] as num).toDouble(),
        calories: (r['calories'] as num).toDouble(),
        protein: (r['protein'] as num).toDouble(),
        carbs: (r['carbs'] as num).toDouble(),
        fats: (r['fats'] as num).toDouble(),
        fiber: (r['fiber'] as num?)?.toDouble(),
        source: r['source'] as String,
        confidence: (r['confidence'] as num).toDouble(),
        isCustom: (r['is_custom'] as int) == 1,
        useCount: r['use_count'] as int,
        lastUsed: r['last_used_ms'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last_used_ms'] as int),
      );
}
