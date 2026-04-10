import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoURL;
  final double height;
  final double weight;
  final double? bmi;
  final String? bodyType;
  final double? fatEstimate;
  final String goal;
  final int calorieLimit;
  final int waterGoal;
  final int proteinGoal;
  final int carbsGoal;
  final int fatsGoal;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoURL,
    required this.height,
    required this.weight,
    this.bmi,
    this.bodyType,
    this.fatEstimate,
    required this.goal,
    required this.calorieLimit,
    required this.waterGoal,
    required this.proteinGoal,
    required this.carbsGoal,
    required this.fatsGoal,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'],
      photoURL: map['photoURL'],
      height: (map['height'] ?? 0).toDouble(),
      weight: (map['weight'] ?? 0).toDouble(),
      bmi: (map['bmi'] ?? 0).toDouble(),
      bodyType: map['bodyType'],
      fatEstimate: (map['fatEstimate'] ?? 0).toDouble(),
      goal: map['goal'] ?? 'maintain',
      calorieLimit: map['calorieLimit'] ?? 2000,
      waterGoal: map['waterGoal'] ?? 2500,
      proteinGoal: map['proteinGoal'] ?? 150,
      carbsGoal: map['carbsGoal'] ?? 250,
      fatsGoal: map['fatsGoal'] ?? 70,
      createdAt: map['createdAt'] != null ? (map['createdAt'] as Timestamp).toDate() : null,
      updatedAt: map['updatedAt'] != null ? (map['updatedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'height': height,
      'weight': weight,
      'bmi': bmi,
      'bodyType': bodyType,
      'fatEstimate': fatEstimate,
      'goal': goal,
      'calorieLimit': calorieLimit,
      'waterGoal': waterGoal,
      'proteinGoal': proteinGoal,
      'carbsGoal': carbsGoal,
      'fatsGoal': fatsGoal,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    double? height,
    double? weight,
    double? bmi,
    String? bodyType,
    double? fatEstimate,
    String? goal,
    int? calorieLimit,
    int? waterGoal,
    int? proteinGoal,
    int? carbsGoal,
    int? fatsGoal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      bmi: bmi ?? this.bmi,
      bodyType: bodyType ?? this.bodyType,
      fatEstimate: fatEstimate ?? this.fatEstimate,
      goal: goal ?? this.goal,
      calorieLimit: calorieLimit ?? this.calorieLimit,
      waterGoal: waterGoal ?? this.waterGoal,
      proteinGoal: proteinGoal ?? this.proteinGoal,
      carbsGoal: carbsGoal ?? this.carbsGoal,
      fatsGoal: fatsGoal ?? this.fatsGoal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
