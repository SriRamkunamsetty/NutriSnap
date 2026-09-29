import '../ai/nutrition_ai.dart';
import '../models/food.dart';
import '../models/meal_item.dart';
import '../models/mess.dart';
import '../models/scan_result.dart';
import '../repositories/food_repository.dart';
import '../repositories/mess_repository.dart';
import '../repositories/scan_repository.dart';

/// Menu text -> meals -> dishes.
class MessMenuParser {
  const MessMenuParser._();

  static final _header = RegExp(
    r'^\s*(breakfast|tiffin|morning|lunch|afternoon|snacks?|tea|evening snacks?|evening|dinner|supper)\b\s*[:\-–—]?\s*(.*)$',
    caseSensitive: false,
  );

  static String? _typeOf(String header) {
    final h = header.toLowerCase();
    if (h.startsWith('breakfast') || h == 'tiffin' || h == 'morning') return MealType.breakfast;
    if (h.startsWith('lunch') || h == 'afternoon') return MealType.lunch;
    if (h.startsWith('snack') || h == 'tea' || h.startsWith('evening')) return MealType.snacks;
    if (h.startsWith('dinner') || h == 'supper') return MealType.dinner;
    return null;
  }

  /// Splits a dish list ("Idli, Sambar + Chutney") into clean names.
  static List<String> splitDishes(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (var part in text.split(RegExp(r'[,;|+\n•·/]|\s&\s|\sand\s', caseSensitive: false))) {
      part = part.replaceAll(RegExp(r'^[\s\-\*•\d\.\)]+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (part.length < 2 || part.length > 60) continue;
      final key = part.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(part[0].toUpperCase() + part.substring(1));
    }
    return out;
  }

  /// Understands a pasted whole-day menu, e.g.
  /// `Breakfast: Idli, Sambar\nLunch - Rice, Dal, Curd\nDinner: Chapati + Paneer curry`.
  /// Lines before any header go to [unassigned].
  static ParsedMenu parse(String text) {
    final meals = <String, List<String>>{};
    final unassigned = <String>[];
    String? current;

    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final m = _header.firstMatch(line);
      if (m != null) {
        current = _typeOf(m.group(1)!);
        final rest = m.group(2) ?? '';
        if (current != null && rest.trim().isNotEmpty) {
          _add(meals[current] ??= [], splitDishes(rest));
        }
        continue;
      }
      final dishes = splitDishes(line);
      if (current == null) {
        _add(unassigned, dishes);
      } else {
        _add(meals[current] ??= [], dishes);
      }
    }
    return ParsedMenu(meals, unassigned);
  }

  static void _add(List<String> into, List<String> more) {
    final seen = into.map((e) => e.toLowerCase()).toSet();
    for (final d in more) {
      if (seen.add(d.toLowerCase())) into.add(d);
    }
  }
}

class ParsedMenu {
  const ParsedMenu(this.meals, this.unassigned);
  final Map<String, List<String>> meals;
  final List<String> unassigned;
  bool get isEmpty => meals.values.every((l) => l.isEmpty) && unassigned.isEmpty;
}

/// Turns dish names into nutrition: local library first, on-device AI second,
/// otherwise honestly "unknown" so the user can fill it in.
class MessService {
  MessService({
    required FoodRepository foods,
    required MessRepository messes,
    required ScanRepository scans,
  })  : _foods = foods,
        _messes = messes,
        _scans = scans;

  final FoodRepository _foods;
  final MessRepository _messes;
  final ScanRepository _scans;

  // ---------------------------------------------------------------------------
  // Nutrition
  // ---------------------------------------------------------------------------

  /// Matches names against the food library. Exact name/alias matches count as
  /// library; a close match ("Rice" vs "Steamed Rice") is used at lower
  /// confidence; anything else stays `unknown`.
  Future<List<MessDish>> match(List<String> names, {List<MessDish> keep = const []}) async {
    final byName = {for (final d in keep) d.name.toLowerCase(): d};
    final out = <MessDish>[];
    for (final name in names) {
      final existing = byName[name.toLowerCase()];
      if (existing != null && !existing.needsEstimate) {
        out.add(existing); // never overwrite what the user or AI already settled
        continue;
      }
      out.add(await _matchOne(name));
    }
    return out;
  }

  Future<MessDish> _matchOne(String name) async {
    var food = await _foods.findByName(name);
    var exact = food != null;
    if (food == null) {
      final tokens = normalizeFoodName(name).split(' ').where((t) => t.isNotEmpty).toSet();
      if (tokens.isNotEmpty) {
        final candidates = await _foods.search(name, limit: 5);
        for (final c in candidates) {
          final ct = normalizeFoodName(c.name).split(' ').toSet();
          if (ct.containsAll(tokens) || tokens.containsAll(ct)) {
            food = c;
            break;
          }
        }
      }
    }
    if (food == null) return MessDish(name: name);
    return MessDish(
      name: name,
      foodId: food.id,
      calories: food.calories,
      protein: food.protein,
      carbs: food.carbs,
      fats: food.fats,
      serving: food.serving,
      source: DishSource.library,
      confidence: exact ? food.confidence : food.confidence * 0.85,
    );
  }

  /// Asks the on-device AI about dishes still unknown. Failures leave them
  /// unknown; nothing is invented.
  Future<List<MessDish>> fillWithAi(List<MessDish> dishes, NutritionAi ai) async {
    final unknown = dishes.where((d) => d.needsEstimate).map((d) => d.name).toList();
    if (unknown.isEmpty) return dishes;
    final estimates = await ai.estimateDishes(unknown);
    final byName = {for (final e in estimates) e.name.toLowerCase(): e};
    return [
      for (final d in dishes)
        if (d.needsEstimate && byName.containsKey(d.name.toLowerCase()))
          d.copyWith(
            calories: byName[d.name.toLowerCase()]!.calories,
            protein: byName[d.name.toLowerCase()]!.protein,
            carbs: byName[d.name.toLowerCase()]!.carbs,
            fats: byName[d.name.toLowerCase()]!.fats,
            serving: byName[d.name.toLowerCase()]!.serving,
            source: DishSource.ai,
            confidence: byName[d.name.toLowerCase()]!.confidence,
          )
        else
          d,
    ];
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// One-tap: adds the meal to the diary. Dishes with no nutrition yet are not
  /// counted (the UI warns first). Returns the saved diary entry.
  Future<ScanResult> logMeal(MessMeal meal, Mess mess, {required String menuDate, DateTime? now}) async {
    final counted = meal.dishes.where((d) => !d.needsEstimate).toList();
    if (counted.isEmpty) {
      throw StateError('Nothing to log: no dish has nutrition yet.');
    }
    if (meal.isLogged) throw StateError('This meal is already logged.');

    final clock = now ?? DateTime.now();
    final day = DateTime.parse(menuDate);
    final isToday = day.year == clock.year && day.month == clock.month && day.day == clock.day;
    final at = isToday ? clock : DateTime(day.year, day.month, day.day, _defaultHour(meal.mealType));

    final items = [
      for (final d in counted)
        MealItem(
          id: '',
          name: d.name,
          estimatedWeight: d.servings,
          servingUnit: ServingUnit.serving,
          calories: d.totalCalories,
          protein: d.totalProtein,
          carbs: d.totalCarbs,
          fats: d.totalFats,
          confidence: d.confidence <= 0 ? 1 : d.confidence,
          // Only library matches are "library"; AI/manual mess numbers are not
          // photo predictions and must not affect the scanner's accuracy score.
          source: d.source == DishSource.library ? ItemSource.library : ItemSource.manual,
        ),
    ];

    final saved = await _scans.add(ScanResult(
      id: '',
      userId: '',
      foodName: '${MealType.label(meal.mealType)} · ${mess.label}',
      type: 'food',
      details: 'MessOS · ${counted.map((d) => d.name).join(', ')}',
      description: 'Logged from the ${mess.label} menu',
      calories: 0,
      protein: 0,
      carbs: 0,
      fats: 0,
      confidence: meal.nutrition.confidence <= 0 ? 1 : meal.nutrition.confidence,
      timestamp: at.toIso8601String(),
      items: items,
      analysisStatus: AnalysisStatus.manual,
    ));

    await _messes.setLogged(meal.id, saved.id);
    for (final d in counted) {
      if (d.foodId != null) await _foods.markUsed(d.foodId!, at: at);
    }
    return saved;
  }

  /// Undo: removes the diary entry and frees the meal to be logged again.
  Future<void> unlogMeal(MessMeal meal) async {
    final id = meal.loggedScanId;
    if (id == null) return;
    await _scans.delete(id);
    await _messes.setLogged(meal.id, null);
  }

  int _defaultHour(String type) => switch (type) {
        MealType.breakfast => 8,
        MealType.lunch => 13,
        MealType.snacks => 17,
        _ => 20,
      };

  /// Which day's menu to copy onto [date]: the same weekday last week if we
  /// have it (messes usually run a weekly cycle), else the most recent earlier day.
  Future<String?> suggestCopySource(String messId, String date) async {
    final d = DateTime.parse(date);
    final weekAgo = DateTime(d.year, d.month, d.day - 7);
    final key = '${weekAgo.year.toString().padLeft(4, '0')}-${weekAgo.month.toString().padLeft(2, '0')}-${weekAgo.day.toString().padLeft(2, '0')}';
    if (await _messes.menu(messId, key) != null) return key;
    for (final other in await _messes.menuDates(messId, limit: 60)) {
      if (other.compareTo(date) < 0) return other;
    }
    return null;
  }
}
