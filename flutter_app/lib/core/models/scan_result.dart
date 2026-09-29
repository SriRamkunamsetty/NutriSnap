import 'package:equatable/equatable.dart';
import '../utils/datetime_utils.dart';
import 'meal_item.dart';

/// How a logged meal's numbers came to be.
class AnalysisStatus {
  const AnalysisStatus._();

  /// An AI result the user has not reviewed yet. Never persisted.
  static const pending = 'pending';

  /// AI result accepted as-is by the user.
  static const confirmed = 'confirmed';

  /// AI result the user changed before saving.
  static const edited = 'edited';

  /// Entered by hand or picked from a list; no AI involved.
  static const manual = 'manual';
}

/// A logged entry: a meal (one or more [items]) or a body scan.
///
/// For meals, [calories]/[protein]/[carbs]/[fats] are the totals of [items].
class ScanResult extends Equatable {
  final String id;
  final String userId;
  final String foodName;
  final String? type;
  final String? description;
  final String? details;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final double? fatEstimate;
  final double confidence;
  final String? imageUrl;
  final String timestamp;

  /// The foods that make up this meal (empty for body scans).
  final List<MealItem> items;

  /// e.g. `gemma-4-E2B-it`; null for manual entries.
  final String? modelVersion;
  final String analysisStatus;

  const ScanResult({
    required this.id,
    required this.userId,
    required this.foodName,
    this.type,
    this.description,
    this.details,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    this.fatEstimate,
    required this.confidence,
    this.imageUrl,
    required this.timestamp,
    this.items = const [],
    this.modelVersion,
    this.analysisStatus = AnalysisStatus.confirmed,
  });

  bool get isFood => (type ?? 'food') == 'food';

  /// A readable list of foods, e.g. "Chicken Curry, Rice, Curd".
  String get itemsSummary => items.map((i) => i.name).join(', ');

  /// Same meal with totals recomputed from [items] (no-op without items).
  ScanResult withTotalsFromItems() {
    if (items.isEmpty) return this;
    final t = MealTotals.of(items);
    return copyWith(calories: t.calories, protein: t.protein, carbs: t.carbs, fats: t.fats);
  }

  factory ScanResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    return ScanResult(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      foodName: map['foodName'] as String? ?? 'Unknown',
      type: map['type'] as String?,
      description: map['description'] as String?,
      details: map['details'] as String?,
      calories: (map['calories'] as num?)?.round() ?? 0,
      protein: (map['protein'] as num?)?.round() ?? 0,
      carbs: (map['carbs'] as num?)?.round() ?? 0,
      fats: (map['fats'] as num?)?.round() ?? 0,
      fatEstimate: (map['fatEstimate'] as num?)?.toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'] as String?,
      timestamp: DateTimeUtils.parse(map['timestamp'])?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      items: rawItems is List
          ? [
              for (final e in rawItems)
                if (e is Map) MealItem.fromMap(Map<String, dynamic>.from(e)),
            ]
          : const [],
      modelVersion: map['modelVersion'] as String?,
      analysisStatus: map['analysisStatus'] as String? ?? AnalysisStatus.confirmed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'foodName': foodName,
      if (type != null) 'type': type,
      if (description != null) 'description': description,
      if (details != null) 'details': details,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fats': fats,
      if (fatEstimate != null) 'fatEstimate': fatEstimate,
      'confidence': confidence,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'timestamp': timestamp,
      if (items.isNotEmpty) 'items': items.map((i) => i.toMap()).toList(),
      if (modelVersion != null) 'modelVersion': modelVersion,
      'analysisStatus': analysisStatus,
    };
  }

  ScanResult copyWith({
    String? id,
    String? userId,
    String? foodName,
    String? type,
    String? description,
    String? details,
    int? calories,
    int? protein,
    int? carbs,
    int? fats,
    double? fatEstimate,
    double? confidence,
    String? imageUrl,
    String? timestamp,
    List<MealItem>? items,
    String? modelVersion,
    String? analysisStatus,
  }) {
    return ScanResult(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      foodName: foodName ?? this.foodName,
      type: type ?? this.type,
      description: description ?? this.description,
      details: details ?? this.details,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fats: fats ?? this.fats,
      fatEstimate: fatEstimate ?? this.fatEstimate,
      confidence: confidence ?? this.confidence,
      imageUrl: imageUrl ?? this.imageUrl,
      timestamp: timestamp ?? this.timestamp,
      items: items ?? this.items,
      modelVersion: modelVersion ?? this.modelVersion,
      analysisStatus: analysisStatus ?? this.analysisStatus,
    );
  }

  @override
  List<Object?> get props => [
        id, userId, foodName, type, description, details, calories,
        protein, carbs, fats, fatEstimate, confidence, imageUrl, timestamp,
        items, modelVersion, analysisStatus,
      ];
}
