import 'package:equatable/equatable.dart';

/// Totals for one local calendar day. Derived from scans + water rows; it is
/// never stored, so it can not drift out of sync with the meal log.
class DailySummary extends Equatable {
  final String date; // yyyy-MM-dd (device local time)
  final int totalCalories;
  final int totalProtein;
  final int totalCarbs;
  final int totalFats;
  final int totalWater; // ml

  const DailySummary({
    required this.date,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFats,
    required this.totalWater,
  });

  factory DailySummary.empty(String date) => DailySummary(
        date: date,
        totalCalories: 0,
        totalProtein: 0,
        totalCarbs: 0,
        totalFats: 0,
        totalWater: 0,
      );

  factory DailySummary.fromMap(Map<String, dynamic> map) {
    int i(dynamic v) => (v as num?)?.round() ?? 0;
    return DailySummary(
      date: map['date'] as String? ?? '',
      totalCalories: i(map['totalCalories']),
      totalProtein: i(map['totalProtein']),
      totalCarbs: i(map['totalCarbs']),
      totalFats: i(map['totalFats']),
      totalWater: i(map['totalWater']),
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'totalCalories': totalCalories,
        'totalProtein': totalProtein,
        'totalCarbs': totalCarbs,
        'totalFats': totalFats,
        'totalWater': totalWater,
      };

  DailySummary copyWith({
    int? totalCalories,
    int? totalProtein,
    int? totalCarbs,
    int? totalFats,
    int? totalWater,
  }) =>
      DailySummary(
        date: date,
        totalCalories: totalCalories ?? this.totalCalories,
        totalProtein: totalProtein ?? this.totalProtein,
        totalCarbs: totalCarbs ?? this.totalCarbs,
        totalFats: totalFats ?? this.totalFats,
        totalWater: totalWater ?? this.totalWater,
      );

  @override
  List<Object?> get props =>
      [date, totalCalories, totalProtein, totalCarbs, totalFats, totalWater];
}
