import 'package:equatable/equatable.dart';

/// A dining hall the user eats at: college -> hostel -> mess.
class Mess extends Equatable {
  const Mess({required this.id, required this.college, required this.hostel, required this.name});
  final String id;
  final String college;
  final String hostel;
  final String name;

  String get label => name.isEmpty ? hostel : name;
  String get subtitle => [college, hostel].where((s) => s.isNotEmpty).join(' · ');

  @override
  List<Object?> get props => [id, college, hostel, name];
}

class MealType {
  const MealType._();
  static const breakfast = 'breakfast';
  static const lunch = 'lunch';
  static const snacks = 'snacks';
  static const dinner = 'dinner';
  static const all = [breakfast, lunch, snacks, dinner];

  static String label(String t) => switch (t) {
        breakfast => 'Breakfast',
        lunch => 'Lunch',
        snacks => 'Snacks',
        dinner => 'Dinner',
        _ => t,
      };
}

class DishSource {
  const DishSource._();

  /// Matched a food in the local library.
  static const library = 'library';

  /// Entered or corrected by the user.
  static const manual = 'manual';

  /// Estimated by the on-device AI.
  static const ai = 'ai';

  /// Not in the library yet; nutrition still unknown.
  static const unknown = 'unknown';
}

/// One dish on a mess menu. Nutrition is **per serving**; [servings] is how
/// much you actually ate.
class MessDish extends Equatable {
  const MessDish({
    required this.name,
    this.foodId,
    this.servings = 1,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fats = 0,
    this.source = DishSource.unknown,
    this.confidence = 0,
    this.serving,
  });

  final String name;
  final String? foodId;
  final double servings;
  final double calories;
  final double protein;
  final double carbs;
  final double fats;
  final String source;
  final double confidence;

  /// e.g. "1 katori".
  final String? serving;

  bool get needsEstimate => source == DishSource.unknown;

  double get totalCalories => calories * servings;
  double get totalProtein => protein * servings;
  double get totalCarbs => carbs * servings;
  double get totalFats => fats * servings;

  MessDish copyWith({
    String? name,
    String? foodId,
    double? servings,
    double? calories,
    double? protein,
    double? carbs,
    double? fats,
    String? source,
    double? confidence,
    String? serving,
  }) =>
      MessDish(
        name: name ?? this.name,
        foodId: foodId ?? this.foodId,
        servings: servings ?? this.servings,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fats: fats ?? this.fats,
        source: source ?? this.source,
        confidence: confidence ?? this.confidence,
        serving: serving ?? this.serving,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (foodId != null) 'foodId': foodId,
        'servings': servings,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fats': fats,
        'source': source,
        'confidence': confidence,
        if (serving != null) 'serving': serving,
      };

  factory MessDish.fromJson(Map<String, dynamic> j) {
    double d(dynamic v, [double def = 0]) => (v as num?)?.toDouble() ?? def;
    return MessDish(
      name: j['name'] as String? ?? '',
      foodId: j['foodId'] as String?,
      servings: d(j['servings'], 1),
      calories: d(j['calories']),
      protein: d(j['protein']),
      carbs: d(j['carbs']),
      fats: d(j['fats']),
      source: j['source'] as String? ?? DishSource.unknown,
      confidence: d(j['confidence']),
      serving: j['serving'] as String?,
    );
  }

  @override
  List<Object?> get props => [name, foodId, servings, calories, protein, carbs, fats, source, confidence, serving];
}

/// What one mess meal adds up to, and how much of it is actually known.
class MessNutritionEstimate extends Equatable {
  const MessNutritionEstimate({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.dishCount,
    required this.knownCount,
    required this.confidence,
    required this.unknownDishes,
  });

  factory MessNutritionEstimate.of(List<MessDish> dishes) {
    var c = 0.0, p = 0.0, cb = 0.0, f = 0.0, conf = 0.0;
    var known = 0;
    final unknown = <String>[];
    for (final d in dishes) {
      if (d.needsEstimate) {
        unknown.add(d.name);
        continue;
      }
      known++;
      c += d.totalCalories;
      p += d.totalProtein;
      cb += d.totalCarbs;
      f += d.totalFats;
      conf += d.confidence;
    }
    return MessNutritionEstimate(
      calories: c.round(),
      protein: p.round(),
      carbs: cb.round(),
      fats: f.round(),
      dishCount: dishes.length,
      knownCount: known,
      // Confidence is discounted by the share of dishes we know nothing about.
      confidence: dishes.isEmpty ? 0 : (conf / dishes.length),
      unknownDishes: unknown,
    );
  }

  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final int dishCount;
  final int knownCount;
  final double confidence;
  final List<String> unknownDishes;

  bool get isComplete => dishCount > 0 && unknownDishes.isEmpty;
  bool get isEmpty => dishCount == 0;

  @override
  List<Object?> get props => [calories, protein, carbs, fats, dishCount, knownCount, confidence, unknownDishes];
}

class MessMeal extends Equatable {
  const MessMeal({
    required this.id,
    required this.menuId,
    required this.mealType,
    required this.dishes,
    this.loggedScanId,
  });

  final String id;
  final String menuId;
  final String mealType;
  final List<MessDish> dishes;

  /// Set once the user logged this meal to their diary.
  final String? loggedScanId;

  bool get isLogged => loggedScanId != null;
  MessNutritionEstimate get nutrition => MessNutritionEstimate.of(dishes);

  @override
  List<Object?> get props => [id, menuId, mealType, dishes, loggedScanId];
}

class MessMenu extends Equatable {
  const MessMenu({required this.id, required this.messId, required this.date, this.meals = const []});
  final String id;
  final String messId;
  final String date;
  final List<MessMeal> meals;

  MessMeal? meal(String type) {
    for (final m in meals) {
      if (m.mealType == type) return m;
    }
    return null;
  }

  @override
  List<Object?> get props => [id, messId, date, meals];
}
