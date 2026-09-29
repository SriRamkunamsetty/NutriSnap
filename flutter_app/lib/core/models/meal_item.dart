import 'package:equatable/equatable.dart';

/// Where a food entry came from.
class ItemSource {
  const ItemSource._();
  static const ai = 'ai';
  static const manual = 'manual';
  static const library = 'library';
}

/// Units a portion can be expressed in.
class ServingUnit {
  const ServingUnit._();
  static const gram = 'g';
  static const millilitre = 'ml';
  static const piece = 'piece';
  static const cup = 'cup';
  static const bowl = 'bowl';
  static const slice = 'slice';
  static const tablespoon = 'tbsp';
  static const serving = 'serving';

  static const all = [gram, millilitre, piece, cup, bowl, slice, tablespoon, serving];

  static String normalize(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty) return gram;
    if (all.contains(v)) return v;
    return switch (v) {
      'gram' || 'grams' || 'gm' || 'gms' => gram,
      'milliliter' || 'millilitre' || 'milliliters' || 'millilitres' => millilitre,
      'pieces' || 'pc' || 'pcs' || 'unit' || 'units' => piece,
      'cups' => cup,
      'bowls' => bowl,
      'slices' => slice,
      'tablespoon' || 'tablespoons' => tablespoon,
      'plate' || 'plates' || 'portion' || 'portions' || 'servings' => serving,
      _ => gram,
    };
  }
}

/// One food within a meal.
///
/// [calories]/[protein]/[carbs]/[fats] describe the **whole portion**
/// ([estimatedWeight] x [servingUnit]), not per 100 g. Editing the portion
/// scales them proportionally, so the numbers always stay consistent.
class MealItem extends Equatable {
  const MealItem({
    required this.id,
    required this.name,
    this.category = 'other',
    required this.estimatedWeight,
    this.servingUnit = ServingUnit.gram,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    this.confidence = 1.0,
    this.source = ItemSource.ai,
    this.originalName,
    this.originalCalories,
    this.note,
  });

  final String id;
  final String name;

  /// e.g. `curry`, `rice`, `salad`, `dairy`, `snack`, `beverage`, `other`.
  final String category;

  /// Amount in [servingUnit] (grams by default).
  final double estimatedWeight;
  final String servingUnit;
  final double calories;
  final double protein;
  final double carbs;
  final double fats;

  /// 0-1. User-entered items are 1.0.
  final double confidence;
  final String source;

  /// What the AI first said, kept so corrections can be learned from later.
  final String? originalName;
  final double? originalCalories;

  /// Why the numbers were personalised (shown in the review screen only; not stored).
  final String? note;

  /// Every item can be edited or removed by the user.
  bool get editable => true;

  bool get wasCorrected =>
      source == ItemSource.ai &&
      ((originalName != null && originalName != name) ||
          (originalCalories != null && (originalCalories! - calories).abs() > 0.5));

  /// Same food, different amount: nutrition scales linearly with the amount.
  MealItem withWeight(double newWeight) {
    final w = newWeight.clamp(0.0, 20000.0);
    if (estimatedWeight <= 0) return copyWith(estimatedWeight: w);
    final f = w / estimatedWeight;
    return copyWith(
      estimatedWeight: w,
      calories: calories * f,
      protein: protein * f,
      carbs: carbs * f,
      fats: fats * f,
    );
  }

  MealItem copyWith({
    String? id,
    String? name,
    String? category,
    double? estimatedWeight,
    String? servingUnit,
    double? calories,
    double? protein,
    double? carbs,
    double? fats,
    double? confidence,
    String? source,
    String? originalName,
    double? originalCalories,
    String? note,
  }) =>
      MealItem(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        estimatedWeight: estimatedWeight ?? this.estimatedWeight,
        servingUnit: servingUnit ?? this.servingUnit,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fats: fats ?? this.fats,
        confidence: confidence ?? this.confidence,
        source: source ?? this.source,
        originalName: originalName ?? this.originalName,
        originalCalories: originalCalories ?? this.originalCalories,
        note: note ?? this.note,
      );

  factory MealItem.fromMap(Map<String, dynamic> m) {
    double d(dynamic v, [double def = 0]) => (v as num?)?.toDouble() ?? def;
    return MealItem(
      id: m['id'] as String? ?? '',
      name: (m['name'] as String? ?? '').trim(),
      category: m['category'] as String? ?? 'other',
      estimatedWeight: d(m['estimatedWeight'], 1),
      servingUnit: ServingUnit.normalize(m['servingUnit'] as String?),
      calories: d(m['calories']),
      protein: d(m['protein']),
      carbs: d(m['carbs']),
      fats: d(m['fats']),
      confidence: d(m['confidence'], 1).clamp(0.0, 1.0),
      source: m['source'] as String? ?? ItemSource.ai,
      originalName: m['originalName'] as String?,
      originalCalories: (m['originalCalories'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'estimatedWeight': estimatedWeight,
        'servingUnit': servingUnit,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fats': fats,
        'confidence': confidence,
        'source': source,
        if (originalName != null) 'originalName': originalName,
        if (originalCalories != null) 'originalCalories': originalCalories,
      };

  @override
  List<Object?> get props => [
        id, name, category, estimatedWeight, servingUnit, calories, protein,
        carbs, fats, confidence, source, originalName, originalCalories, note,
      ];
}

/// Sums of a list of items, rounded for display and storage.
class MealTotals extends Equatable {
  const MealTotals(this.calories, this.protein, this.carbs, this.fats);

  factory MealTotals.of(Iterable<MealItem> items) {
    var c = 0.0, p = 0.0, cb = 0.0, f = 0.0;
    for (final i in items) {
      c += i.calories;
      p += i.protein;
      cb += i.carbs;
      f += i.fats;
    }
    return MealTotals(c.round(), p.round(), cb.round(), f.round());
  }

  final int calories;
  final int protein;
  final int carbs;
  final int fats;

  @override
  List<Object?> get props => [calories, protein, carbs, fats];
}
