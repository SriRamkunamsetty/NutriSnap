import 'package:equatable/equatable.dart';
import '../utils/datetime_utils.dart';

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
  });

  factory ScanResult.fromMap(Map<String, dynamic> map) {
    return ScanResult(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      foodName: map['foodName'] ?? 'Unknown',
      type: map['type'],
      description: map['description'],
      details: map['details'],
      calories: map['calories']?.toInt() ?? 0,
      protein: map['protein']?.toInt() ?? 0,
      carbs: map['carbs']?.toInt() ?? 0,
      fats: map['fats']?.toInt() ?? 0,
      fatEstimate: (map['fatEstimate'] as num?)?.toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'],
      timestamp: DateTimeUtils.parse(map['timestamp'])?.toIso8601String() ?? DateTime.now().toIso8601String(),
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
    );
  }

  @override
  List<Object?> get props => [
        id, userId, foodName, type, description, details, calories,
        protein, carbs, fats, fatEstimate, confidence, imageUrl, timestamp,
      ];
}
