import 'package:equatable/equatable.dart';

/// A food in the local library: built-in reference data or the user's own.
///
/// Nutrition is for **one [serving]** (about [servingGrams] g).
class Food extends Equatable {
  const Food({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.tags = const [],
    this.category = 'other',
    required this.serving,
    required this.servingGrams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    this.fiber,
    this.source = builtInSource,
    this.confidence = 0.75,
    this.isCustom = false,
    this.useCount = 0,
    this.lastUsed,
  });

  static const builtInSource = 'NutriSnap reference (approximate)';
  static const customSource = 'Added by you';

  final String id;
  final String name;
  final List<String> aliases;

  /// Regions, styles and meal times, e.g. `Andhra`, `Hostel`, `Breakfast`.
  final List<String> tags;
  final String category;

  /// Human label, e.g. "2 idlis" or "1 katori".
  final String serving;
  final double servingGrams;
  final double calories;
  final double protein;
  final double carbs;
  final double fats;
  final double? fiber;

  /// Where the numbers come from; shown in the details sheet.
  final String source;

  /// How much to trust the numbers (reference data is approximate).
  final double confidence;
  final bool isCustom;
  final int useCount;
  final DateTime? lastUsed;

  bool hasTag(String t) => tags.any((x) => x.toLowerCase() == t.toLowerCase());

  /// Region tags used by the "Regional preferences" statistics.
  static const regionTags = ['Andhra', 'Telangana', 'South Indian', 'North Indian'];

  Iterable<String> get regions => regionTags.where(hasTag);

  factory Food.fromJson(Map<String, dynamic> j, {double confidence = 0.75, String source = builtInSource}) {
    double d(dynamic v, [double def = 0]) => (v as num?)?.toDouble() ?? def;
    return Food(
      id: j['id'] as String,
      name: (j['name'] as String).trim(),
      aliases: [for (final a in (j['aliases'] as List? ?? const [])) '$a'],
      tags: [for (final t in (j['tags'] as List? ?? const [])) '$t'],
      category: j['category'] as String? ?? 'other',
      serving: j['serving'] as String? ?? '1 serving',
      servingGrams: d(j['servingGrams'], 100),
      calories: d(j['calories']),
      protein: d(j['protein']),
      carbs: d(j['carbs']),
      fats: d(j['fats']),
      fiber: (j['fiber'] as num?)?.toDouble(),
      confidence: confidence,
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aliases': aliases,
        'tags': tags,
        'category': category,
        'serving': serving,
        'servingGrams': servingGrams,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fats': fats,
        if (fiber != null) 'fiber': fiber,
        'source': source,
        'confidence': confidence,
        'isCustom': isCustom,
      };

  Food copyWith({
    String? name,
    List<String>? aliases,
    List<String>? tags,
    String? category,
    String? serving,
    double? servingGrams,
    double? calories,
    double? protein,
    double? carbs,
    double? fats,
    double? fiber,
  }) =>
      Food(
        id: id,
        name: name ?? this.name,
        aliases: aliases ?? this.aliases,
        tags: tags ?? this.tags,
        category: category ?? this.category,
        serving: serving ?? this.serving,
        servingGrams: servingGrams ?? this.servingGrams,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fats: fats ?? this.fats,
        fiber: fiber ?? this.fiber,
        source: source,
        confidence: confidence,
        isCustom: isCustom,
        useCount: useCount,
        lastUsed: lastUsed,
      );

  @override
  List<Object?> get props => [
        id, name, aliases, tags, category, serving, servingGrams, calories, protein, carbs,
        fats, fiber, source, confidence, isCustom, useCount, lastUsed,
      ];
}

/// Lower-cases and strips punctuation so "Chicken  Biryani!" == "chicken biryani".
String normalizeFoodName(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-෿]+'), ' ').trim();
