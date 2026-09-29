import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../ai/ai_models.dart';
import '../database/app_database.dart';
import '../models/food.dart';
import '../models/meal_item.dart';
import '../models/scan_result.dart';
import '../repositories/food_repository.dart';

/// One time the user changed what the AI said.
class FoodCorrection extends Equatable {
  const FoodCorrection({
    required this.id,
    required this.scanId,
    required this.key,
    required this.originalName,
    required this.correctedName,
    required this.originalKcal,
    required this.correctedKcal,
    this.weight,
    this.unit,
    required this.at,
  });

  final String id;
  final String scanId;

  /// Normalised original name the correction is filed under.
  final String key;
  final String originalName;
  final String correctedName;
  final double originalKcal;
  final double correctedKcal;
  final double? weight;
  final String? unit;
  final DateTime at;

  bool get renamed => normalizeFoodName(originalName) != normalizeFoodName(correctedName);
  double get ratio => originalKcal <= 0 ? 1 : correctedKcal / originalKcal;

  @override
  List<Object?> get props => [id, scanId, key, originalName, correctedName, originalKcal, correctedKcal, weight, unit, at];
}

class FoodUsage extends Equatable {
  const FoodUsage({required this.name, required this.count, required this.avgKcal, this.typicalPortion});
  final String name;
  final int count;
  final double avgKcal;

  /// e.g. "180 g", the median amount you usually log.
  final String? typicalPortion;

  @override
  List<Object?> get props => [name, count, avgKcal, typicalPortion];
}

/// Everything the Food Twin has learned, computed from the user's own history.
class FoodTwinProfile extends Equatable {
  const FoodTwinProfile({
    this.foodsLearned = 0,
    this.frequentlyUsedFoods = const [],
    this.customFoods = const [],
    this.correctionHistory = const [],
    this.preferredPortions = const {},
    this.aliases = const {},
    this.regionalPreferences = const {},
    this.aiItemsCount = 0,
    this.averageConfidence,
    this.personalAccuracy,
    this.lastUpdated,
  });

  final int foodsLearned;
  final List<FoodUsage> frequentlyUsedFoods;
  final List<Food> customFoods;
  final List<FoodCorrection> correctionHistory;

  /// Food name -> typical portion, only for foods logged 2+ times.
  final Map<String, String> preferredPortions;

  /// What the AI calls it -> what you call it (from repeated renames).
  final Map<String, String> aliases;

  /// Region tag -> number of logged items (e.g. Andhra: 12).
  final Map<String, int> regionalPreferences;
  final int aiItemsCount;
  final double? averageConfidence;

  /// Share of AI-identified foods you left unchanged. Null until there is
  /// enough data to say anything (5+ AI-identified foods).
  final double? personalAccuracy;
  final DateTime? lastUpdated;

  bool get hasLearned => foodsLearned > 0 || correctionHistory.isNotEmpty;

  @override
  List<Object?> get props => [
        foodsLearned, frequentlyUsedFoods, customFoods, correctionHistory, preferredPortions,
        aliases, regionalPreferences, aiItemsCount, averageConfidence, personalAccuracy, lastUpdated,
      ];
}

/// The Personal Food Twin: a local learning layer. Everything is derived from
/// the user's own confirmed meals and corrections and never leaves the device.
class FoodTwinService {
  FoodTwinService(this._db, this._foods);

  final AppDatabase _db;
  final FoodRepository _foods;
  static const _uuid = Uuid();

  /// How many matching corrections are needed before we act on them.
  static const int minCorrectionsToApply = 2;
  static const int _recentWindow = 6;

  // ---------------------------------------------------------------------------
  // Learning
  // ---------------------------------------------------------------------------

  /// Records what was corrected in [meal]. Idempotent: it replaces any earlier
  /// corrections for the same meal, so re-saving after an edit never
  /// double-counts.
  Future<void> recordMeal(ScanResult meal) async {
    await _db.db.transaction((txn) async {
      await txn.delete(Tables.foodCorrections, where: 'scan_id = ?', whereArgs: [meal.id]);
      final at = DateTime.now().millisecondsSinceEpoch;
      for (final i in meal.items) {
        if (!i.wasCorrected) continue;
        await txn.insert(
          Tables.foodCorrections,
          {
            'id': 'corr_${_uuid.v4()}',
            'scan_id': meal.id,
            'item_id': i.id,
            'key': normalizeFoodName(i.originalName ?? i.name),
            'original_name': i.originalName ?? i.name,
            'corrected_name': i.name,
            'original_kcal': i.originalCalories ?? i.calories,
            'corrected_kcal': i.calories,
            'weight': i.estimatedWeight,
            'unit': i.servingUnit,
            'created_ms': at,
          },
        );
      }
    });
    _db.notify(Tables.foodCorrections);
  }

  /// Applies what has been learned to a fresh AI result: renames foods the
  /// user always calls something else, and rescales calories for foods the AI
  /// keeps getting wrong for them. Only acts on repeated evidence.
  Future<MealAnalysisResult> personalize(MealAnalysisResult analysis) async {
    if (!analysis.isFood || analysis.detectedItems.isEmpty) return analysis;
    final personalised = <MealItem>[];
    var changed = false;

    for (final item in analysis.detectedItems) {
      final key = normalizeFoodName(item.originalName ?? item.name);
      final rows = await _db.db.query(
        Tables.foodCorrections,
        where: 'key = ?',
        whereArgs: [key],
        orderBy: 'created_ms DESC',
        limit: _recentWindow,
      );
      final corrections = rows.map(_correctionFrom).toList();
      var next = item;

      // 1. Name: the same rename at least twice becomes the default.
      final renames = <String, int>{};
      for (final c in corrections.where((c) => c.renamed)) {
        renames[c.correctedName] = (renames[c.correctedName] ?? 0) + 1;
      }
      String? preferred;
      renames.forEach((name, n) {
        if (n >= minCorrectionsToApply && (preferred == null || n > renames[preferred]!)) preferred = name;
      });
      if (preferred != null) {
        next = next.copyWith(
          name: preferred,
          originalName: preferred, // what we propose is the new baseline
          note: 'Renamed from "${item.name}": you usually call it this.',
        );
        changed = true;
      }

      // 2. Calories: repeated same-direction corrections rescale the estimate.
      final sameFood = corrections.where((c) => c.originalKcal > 0 && c.ratio > 0.3 && c.ratio < 3.0).toList();
      if (sameFood.length >= minCorrectionsToApply) {
        final ratio = sameFood.fold<double>(0, (a, c) => a + c.ratio) / sameFood.length;
        final consistent = sameFood.every((c) => (c.ratio - ratio).abs() <= 0.35);
        if (consistent && (ratio - 1).abs() >= 0.05) {
          final scaled = (next.calories * ratio).roundToDouble();
          next = next.copyWith(
            calories: scaled,
            originalCalories: scaled,
            protein: double.parse((next.protein * ratio).toStringAsFixed(1)),
            carbs: double.parse((next.carbs * ratio).toStringAsFixed(1)),
            fats: double.parse((next.fats * ratio).toStringAsFixed(1)),
            note: '${next.note == null ? '' : '${next.note} '}Adjusted ${ratio < 1 ? 'down' : 'up'} using ${sameFood.length} of your earlier corrections.',
          );
          changed = true;
        }
      }
      personalised.add(next);
    }
    return changed ? analysis.copyWith(detectedItems: personalised) : analysis;
  }

  /// A short, factual summary for the coach prompt (empty when nothing learned).
  Future<String> promptSummary() async {
    final p = await profile();
    if (!p.hasLearned) return '';
    final b = StringBuffer();
    if (p.frequentlyUsedFoods.isNotEmpty) {
      b.writeln('Usually eats: ${p.frequentlyUsedFoods.take(5).map((f) => '${f.name}${f.typicalPortion == null ? '' : ' (${f.typicalPortion})'}').join(', ')}.');
    }
    if (p.regionalPreferences.isNotEmpty) {
      final top = p.regionalPreferences.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      b.writeln('Food style: ${top.take(2).map((e) => e.key).join(', ')}.');
    }
    if (p.customFoods.isNotEmpty) {
      b.writeln('Custom foods: ${p.customFoods.take(4).map((f) => f.name).join(', ')}.');
    }
    return b.toString().trim();
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Future<FoodTwinProfile> profile() async {
    final rows = await _db.db.rawQuery('''
      SELECT i.name, i.unit, i.weight, i.calories, i.source, i.confidence,
             i.original_name, i.original_calories, s.logged_at
      FROM ${Tables.mealItems} i
      JOIN ${Tables.scans} s ON s.id = i.scan_id
      ORDER BY s.logged_at DESC
      LIMIT 1000
    ''');

    final byName = <String, _Acc>{};
    var aiItems = 0;
    var aiUnchanged = 0;
    var confSum = 0.0;
    final regions = <String, int>{};
    int? lastMs;

    for (final r in rows) {
      final name = r['name'] as String;
      final key = normalizeFoodName(name);
      final acc = byName.putIfAbsent(key, () => _Acc(name));
      acc.count++;
      acc.kcal += (r['calories'] as num).toDouble();
      acc.weights.add((r['weight'] as num).toDouble());
      acc.units[r['unit'] as String] = (acc.units[r['unit'] as String] ?? 0) + 1;
      lastMs = lastMs == null || (r['logged_at'] as int) > lastMs ? r['logged_at'] as int : lastMs;

      if ((r['source'] as String) == ItemSource.ai) {
        aiItems++;
        confSum += (r['confidence'] as num).toDouble();
        final origName = r['original_name'] as String?;
        final origKcal = (r['original_calories'] as num?)?.toDouble();
        final kcal = (r['calories'] as num).toDouble();
        final sameName = origName == null || normalizeFoodName(origName) == key;
        final sameKcal = origKcal == null || (origKcal - kcal).abs() <= 0.5;
        if (sameName && sameKcal) aiUnchanged++;
      }
    }

    // Region preferences via the library (only foods we can identify).
    for (final entry in byName.entries) {
      final f = await _foods.findByName(entry.key);
      if (f == null) continue;
      for (final region in f.regions) {
        regions[region] = (regions[region] ?? 0) + entry.value.count;
      }
    }

    final usage = byName.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    final portions = <String, String>{};
    final frequent = <FoodUsage>[];
    for (final a in usage.take(12)) {
      final portion = a.count >= 2 ? a.typicalPortion : null;
      if (portion != null) portions[a.display] = portion;
      frequent.add(FoodUsage(name: a.display, count: a.count, avgKcal: a.kcal / a.count, typicalPortion: portion));
    }

    final corrections = (await _db.db.query(Tables.foodCorrections, orderBy: 'created_ms DESC', limit: 100))
        .map(_correctionFrom)
        .toList();

    // Learned aliases = renames seen at least twice.
    final renameCounts = <String, Map<String, int>>{};
    for (final c in corrections.where((c) => c.renamed)) {
      final m = renameCounts.putIfAbsent(c.originalName, () => {});
      m[c.correctedName] = (m[c.correctedName] ?? 0) + 1;
    }
    final aliases = <String, String>{};
    renameCounts.forEach((orig, m) {
      final best = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (best.value >= minCorrectionsToApply) aliases[orig] = best.key;
    });

    return FoodTwinProfile(
      foodsLearned: byName.length,
      frequentlyUsedFoods: frequent,
      customFoods: await _foods.custom(),
      correctionHistory: corrections,
      preferredPortions: portions,
      aliases: aliases,
      regionalPreferences: regions,
      aiItemsCount: aiItems,
      averageConfidence: aiItems == 0 ? null : confSum / aiItems,
      personalAccuracy: aiItems >= 5 ? aiUnchanged / aiItems : null,
      lastUpdated: lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
  }

  Stream<FoodTwinProfile> watchProfile() =>
      _db.watch({Tables.scans, Tables.foodCorrections, Tables.foods}, profile);

  /// Forget everything learned (corrections + usage). Meals are untouched.
  Future<void> reset() async {
    await _db.db.delete(Tables.foodCorrections);
    await _foods.resetUserData();
    _db.notify(Tables.foodCorrections);
  }

  FoodCorrection _correctionFrom(Map<String, Object?> r) => FoodCorrection(
        id: r['id'] as String,
        scanId: r['scan_id'] as String,
        key: r['key'] as String,
        originalName: r['original_name'] as String,
        correctedName: r['corrected_name'] as String,
        originalKcal: (r['original_kcal'] as num).toDouble(),
        correctedKcal: (r['corrected_kcal'] as num).toDouble(),
        weight: (r['weight'] as num?)?.toDouble(),
        unit: r['unit'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(r['created_ms'] as int),
      );
}

class _Acc {
  _Acc(this.display);
  final String display;
  int count = 0;
  double kcal = 0;
  final weights = <double>[];
  final units = <String, int>{};

  String? get typicalPortion {
    if (weights.isEmpty) return null;
    final sorted = [...weights]..sort();
    final median = sorted[sorted.length ~/ 2];
    final unit = units.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final v = median == median.roundToDouble() ? median.round().toString() : median.toStringAsFixed(1);
    return '$v $unit';
  }
}
