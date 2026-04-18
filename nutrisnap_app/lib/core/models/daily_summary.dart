import 'package:equatable/equatable.dart';

class DailySummary extends Equatable {
  final String date;
  final int totalCalories;
  final int totalProtein;
  final int totalCarbs;
  final int totalFats;
  final int totalWater;

  const DailySummary({
    required this.date,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFats,
    required this.totalWater,
  });

  factory DailySummary.fromMap(Map<String, dynamic> map) {
    return DailySummary(
      date: map['date'] ?? '',
      totalCalories: map['totalCalories']?.toInt() ?? 0,
      totalProtein: map['totalProtein']?.toInt() ?? 0,
      totalCarbs: map['totalCarbs']?.toInt() ?? 0,
      totalFats: map['totalFats']?.toInt() ?? 0,
      totalWater: map['totalWater']?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [date, totalCalories, totalProtein, totalCarbs, totalFats, totalWater];
}
