import 'package:equatable/equatable.dart';

import '../enums/app_enums.dart';
import '../models/meal_item.dart';
import '../models/scan_result.dart';

/// Raised when the on-device model is missing, unloadable, or produced output
/// we cannot use. The message is safe to show to the user.
class AiException implements Exception {
  AiException(this.message, {this.needsModel = false, this.retryable = true});

  final String message;

  /// True when the fix is "download the model" rather than "try again".
  final bool needsModel;
  final bool retryable;

  @override
  String toString() => message;
}

/// Structured result of analysing a meal photo: every distinct food found,
/// with its own portion, nutrition and confidence. It is a *proposal*: nothing
/// is saved until the user reviews and confirms it.
class MealAnalysisResult extends Equatable {
  const MealAnalysisResult({
    required this.mealId,
    required this.detectedItems,
    this.type = 'food',
    this.description = '',
    required this.confidence,
    required this.timestamp,
    this.imageReference,
    this.modelVersion,
    this.analysisStatus = AnalysisStatus.pending,
  });

  final String mealId;
  final List<MealItem> detectedItems;

  /// `food`, `person`, `animal` or `other`.
  final String type;
  final String description;

  /// 0-1 overall confidence (calorie-weighted over the items).
  final double confidence;
  final DateTime timestamp;

  /// Path of the stored photo once the meal is confirmed.
  final String? imageReference;
  final String? modelVersion;
  final String analysisStatus;

  bool get isFood => type == 'food';

  MealTotals get totals => MealTotals.of(detectedItems);
  int get estimatedTotalCalories => totals.calories;
  int get estimatedProtein => totals.protein;
  int get estimatedCarbohydrates => totals.carbs;
  int get estimatedFat => totals.fats;

  /// Below this the result must be looked at before it is saved.
  static const double reviewThreshold = 0.65;

  /// True when the AI was unsure about the meal or about any single food.
  bool get needsReview =>
      isFood &&
      (detectedItems.isEmpty ||
          confidence < reviewThreshold ||
          detectedItems.any((i) => i.confidence < 0.5));

  /// e.g. "Chicken Curry, Rice & Curd" or "Idli, Sambar + 2 more".
  String get title => titleOf(detectedItems, isFood: isFood);

  static String titleOf(List<MealItem> items, {bool isFood = true}) {
    final names = items.map((i) => i.name).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return isFood ? 'Meal' : 'Photo';
    if (names.length == 1) return names.first;
    if (names.length <= 3) {
      return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
    }
    return '${names[0]}, ${names[1]} + ${names.length - 2} more';
  }

  MealAnalysisResult copyWith({
    List<MealItem>? detectedItems,
    double? confidence,
    String? imageReference,
    String? analysisStatus,
    DateTime? timestamp,
  }) =>
      MealAnalysisResult(
        mealId: mealId,
        detectedItems: detectedItems ?? this.detectedItems,
        type: type,
        description: description,
        confidence: confidence ?? this.confidence,
        timestamp: timestamp ?? this.timestamp,
        imageReference: imageReference ?? this.imageReference,
        modelVersion: modelVersion,
        analysisStatus: analysisStatus ?? this.analysisStatus,
      );

  /// Builds the meal to persist. [status] says whether the user changed the
  /// AI's answer.
  ScanResult toScan({String? imagePath, String? status, List<MealItem>? items}) {
    final foods = items ?? detectedItems;
    final t = MealTotals.of(foods);
    return ScanResult(
      id: '',
      userId: '',
      foodName: titleOf(foods, isFood: isFood),
      type: type,
      details: foods.map((i) => i.name).join(', '),
      description: description,
      calories: t.calories,
      protein: t.protein,
      carbs: t.carbs,
      fats: t.fats,
      confidence: confidence,
      imageUrl: imagePath,
      timestamp: timestamp.toIso8601String(),
      items: foods,
      modelVersion: modelVersion,
      analysisStatus: status ?? analysisStatus,
    );
  }

  @override
  List<Object?> get props => [
        mealId, detectedItems, type, description, confidence, timestamp,
        imageReference, modelVersion, analysisStatus,
      ];
}

/// AI estimate for one named dish (no photo): a typical single serving.
class DishEstimate extends Equatable {
  const DishEstimate({
    required this.name,
    required this.serving,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.confidence,
  });

  final String name;
  final String serving;
  final double calories;
  final double protein;
  final double carbs;
  final double fats;
  final double confidence;

  @override
  List<Object?> get props => [name, serving, calories, protein, carbs, fats, confidence];
}

class BodyAnalysis extends Equatable {
  const BodyAnalysis({
    required this.bodyType,
    required this.fatEstimate,
    required this.observations,
  });

  final BodyType bodyType;

  /// Estimated body-fat percentage, clamped to a physiologically sane range.
  final double fatEstimate;
  final String observations;

  @override
  List<Object?> get props => [bodyType, fatEstimate, observations];
}

class CoachReply extends Equatable {
  const CoachReply({required this.text, this.suggestions = const []});

  final String text;
  final List<String> suggestions;

  @override
  List<Object?> get props => [text, suggestions];
}
