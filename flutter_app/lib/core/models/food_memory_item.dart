import 'package:equatable/equatable.dart';

/// NutriSnap AI - "Personal Food Twin"
/// Learns from a user's repeated scans of the same dish (regional / home-cooked
/// / mess food that generic nutrition databases don't recognize well) and
/// builds an on-device profile of their most-eaten meals over time.
class FoodMemoryItem extends Equatable {
  final String id;
  final String foodName;
  final String? localName;
  final String category;
  final int scanCount;
  final int avgCalories;
  final String lastEaten;
  final List<String> tags;
  final bool? isAllergy;
  final bool? isPreferred;
  final double confidenceScore;

  const FoodMemoryItem({
    required this.id,
    required this.foodName,
    this.localName,
    required this.category,
    required this.scanCount,
    required this.avgCalories,
    required this.lastEaten,
    required this.tags,
    this.isAllergy,
    this.isPreferred,
    required this.confidenceScore,
  });

  factory FoodMemoryItem.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'];
    return FoodMemoryItem(
      id: map['id'] as String? ?? '',
      foodName: map['foodName'] as String? ?? 'Unknown',
      localName: map['localName'] as String?,
      category: map['category'] as String? ?? 'Custom',
      scanCount: (map['scanCount'] as num?)?.toInt() ?? 1,
      avgCalories: (map['avgCalories'] as num?)?.toInt() ?? 0,
      lastEaten: map['lastEaten'] as String? ?? DateTime.now().toIso8601String(),
      tags: rawTags is List ? rawTags.map((t) => t.toString()).toList() : const [],
      isAllergy: map['isAllergy'] as bool?,
      isPreferred: map['isPreferred'] as bool?,
      confidenceScore: (map['confidenceScore'] as num?)?.toDouble() ?? 0.9,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'foodName': foodName,
      if (localName != null) 'localName': localName,
      'category': category,
      'scanCount': scanCount,
      'avgCalories': avgCalories,
      'lastEaten': lastEaten,
      'tags': tags,
      if (isAllergy != null) 'isAllergy': isAllergy,
      if (isPreferred != null) 'isPreferred': isPreferred,
      'confidenceScore': confidenceScore,
    };
  }

  FoodMemoryItem copyWith({
    int? scanCount,
    int? avgCalories,
    String? lastEaten,
    List<String>? tags,
    bool? isPreferred,
  }) {
    return FoodMemoryItem(
      id: id,
      foodName: foodName,
      localName: localName,
      category: category,
      scanCount: scanCount ?? this.scanCount,
      avgCalories: avgCalories ?? this.avgCalories,
      lastEaten: lastEaten ?? this.lastEaten,
      tags: tags ?? this.tags,
      isAllergy: isAllergy,
      isPreferred: isPreferred ?? this.isPreferred,
      confidenceScore: confidenceScore,
    );
  }

  @override
  List<Object?> get props => [id, foodName, localName, category, scanCount, avgCalories, lastEaten, tags, isAllergy, isPreferred, confidenceScore];
}
