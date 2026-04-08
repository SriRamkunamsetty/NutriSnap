class DailySummary {
  final String date;
  final int totalCalories;
  final int totalProtein;
  final int totalCarbs;
  final int totalFats;
  final int totalWater;

  DailySummary({
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
      totalCalories: map['totalCalories'] ?? 0,
      totalProtein: map['totalProtein'] ?? 0,
      totalCarbs: map['totalCarbs'] ?? 0,
      totalFats: map['totalFats'] ?? 0,
      totalWater: map['totalWater'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'totalCalories': totalCalories,
      'totalProtein': totalProtein,
      'totalCarbs': totalCarbs,
      'totalFats': totalFats,
      'totalWater': totalWater,
    };
  }
}
