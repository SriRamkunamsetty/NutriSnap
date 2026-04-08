import 'package:cloud_firestore/cloud_firestore.dart';

class ScanResult {
  final String? id;
  final String userId;
  final String foodName;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final double confidence;
  final String? imageUrl;
  final DateTime timestamp;
  final String? type;
  final String? description;

  ScanResult({
    this.id,
    required this.userId,
    required this.foodName,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.confidence,
    this.imageUrl,
    required this.timestamp,
    this.type,
    this.description,
  });

  factory ScanResult.fromMap(Map<String, dynamic> map, String id) {
    return ScanResult(
      id: id,
      userId: map['userId'] ?? '',
      foodName: map['foodName'] ?? '',
      calories: map['calories'] ?? 0,
      protein: map['protein'] ?? 0,
      carbs: map['carbs'] ?? 0,
      fats: map['fats'] ?? 0,
      confidence: (map['confidence'] ?? 0).toDouble(),
      imageUrl: map['imageUrl'],
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      type: map['type'],
      description: map['description'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'foodName': foodName,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fats': fats,
      'confidence': confidence,
      'imageUrl': imageUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      'description': description,
    };
  }
}
