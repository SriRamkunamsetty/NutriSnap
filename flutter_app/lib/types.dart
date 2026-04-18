import 'package:cloud_firestore/cloud_firestore.dart';

enum Goal { lose, maintain, gain }
enum BodyType { lean, normal, obese, unknown }
enum ThemeType { light, dark }
enum ReminderType { meal, water }
enum ChatRole { user, model }
enum ScanType { food, person, animal, other }

class Reminder {
  final String id;
  final String time; // HH:mm
  final ReminderType type;
  final bool enabled;

  Reminder({
    required this.id,
    required this.time,
    required this.type,
    required this.enabled,
  });

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] ?? '',
      time: map['time'] ?? '00:00',
      type: ReminderType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ReminderType.meal,
      ),
      enabled: map['enabled'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'type': type.name,
      'enabled': enabled,
    };
  }
}

class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoURL;
  final double? height;
  final double? weight;
  final double? bmi;
  final BodyType? bodyType;
  final double? fatEstimate;
  final String? bodyScanURL;
  final Goal? goal;
  final int? calorieLimit;
  final int? proteinGoal;
  final int? carbsGoal;
  final int? fatsGoal;
  final int? proteinPct;
  final int? carbsPct;
  final int? fatsPct;
  final int? waterGoal; // in ml
  final List<Reminder>? reminders;
  final ThemeType? theme;
  final String? aiAvatarURL;
  final bool? hasCompletedOnboarding;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoURL,
    this.height,
    this.weight,
    this.bmi,
    this.bodyType,
    this.fatEstimate,
    this.bodyScanURL,
    this.goal,
    this.calorieLimit,
    this.proteinGoal,
    this.carbsGoal,
    this.fatsGoal,
    this.proteinPct,
    this.carbsPct,
    this.fatsPct,
    this.waterGoal,
    this.reminders,
    this.theme,
    this.aiAvatarURL,
    this.hasCompletedOnboarding,
    required this.createdAt,
    this.lastLoginAt,
  });

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    double? height,
    double? weight,
    double? bmi,
    BodyType? bodyType,
    double? fatEstimate,
    String? bodyScanURL,
    Goal? goal,
    int? calorieLimit,
    int? proteinGoal,
    int? carbsGoal,
    int? fatsGoal,
    int? proteinPct,
    int? carbsPct,
    int? fatsPct,
    int? waterGoal,
    List<Reminder>? reminders,
    ThemeType? theme,
    String? aiAvatarURL,
    bool? hasCompletedOnboarding,
    DateTime? createdAt,
    DateTime? lastLoginAt,
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
      bodyScanURL: bodyScanURL ?? this.bodyScanURL,
      goal: goal ?? this.goal,
      calorieLimit: calorieLimit ?? this.calorieLimit,
      proteinGoal: proteinGoal ?? this.proteinGoal,
      carbsGoal: carbsGoal ?? this.carbsGoal,
      fatsGoal: fatsGoal ?? this.fatsGoal,
      proteinPct: proteinPct ?? this.proteinPct,
      carbsPct: carbsPct ?? this.carbsPct,
      fatsPct: fatsPct ?? this.fatsPct,
      waterGoal: waterGoal ?? this.waterGoal,
      reminders: reminders ?? this.reminders,
      theme: theme ?? this.theme,
      aiAvatarURL: aiAvatarURL ?? this.aiAvatarURL,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'],
      photoURL: map['photoURL'],
      height: (map['height'] as num?)?.toDouble(),
      weight: (map['weight'] as num?)?.toDouble(),
      bmi: (map['bmi'] as num?)?.toDouble(),
      bodyType: map['bodyType'] != null
          ? BodyType.values.firstWhere((e) => e.name == map['bodyType'], orElse: () => BodyType.unknown)
          : null,
      fatEstimate: (map['fatEstimate'] as num?)?.toDouble(),
      bodyScanURL: map['bodyScanURL'],
      goal: map['goal'] != null
          ? Goal.values.firstWhere((e) => e.name == map['goal'], orElse: () => Goal.maintain)
          : null,
      calorieLimit: (map['calorieLimit'] as num?)?.toInt(),
      proteinGoal: (map['proteinGoal'] as num?)?.toInt(),
      carbsGoal: (map['carbsGoal'] as num?)?.toInt(),
      fatsGoal: (map['fatsGoal'] as num?)?.toInt(),
      proteinPct: (map['proteinPct'] as num?)?.toInt(),
      carbsPct: (map['carbsPct'] as num?)?.toInt(),
      fatsPct: (map['fatsPct'] as num?)?.toInt(),
      waterGoal: (map['waterGoal'] as num?)?.toInt(),
      reminders: map['reminders'] != null
          ? List<Reminder>.from((map['reminders'] as List).map((x) => Reminder.fromMap(x)))
          : null,
      theme: map['theme'] != null
          ? ThemeType.values.firstWhere((e) => e.name == map['theme'], orElse: () => ThemeType.light)
          : null,
      aiAvatarURL: map['aiAvatarURL'],
      hasCompletedOnboarding: map['hasCompletedOnboarding'],
      createdAt: map['createdAt'] is Timestamp 
          ? (map['createdAt'] as Timestamp).toDate() 
          : DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      lastLoginAt: map['lastLoginAt'] != null
          ? (map['lastLoginAt'] is Timestamp 
              ? (map['lastLoginAt'] as Timestamp).toDate() 
              : DateTime.parse(map['lastLoginAt']))
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      if (displayName != null) 'displayName': displayName,
      if (photoURL != null) 'photoURL': photoURL,
      if (height != null) 'height': height,
      if (weight != null) 'weight': weight,
      if (bmi != null) 'bmi': bmi,
      if (bodyType != null) 'bodyType': bodyType?.name,
      if (fatEstimate != null) 'fatEstimate': fatEstimate,
      if (bodyScanURL != null) 'bodyScanURL': bodyScanURL,
      if (goal != null) 'goal': goal?.name,
      if (calorieLimit != null) 'calorieLimit': calorieLimit,
      if (proteinGoal != null) 'proteinGoal': proteinGoal,
      if (carbsGoal != null) 'carbsGoal': carbsGoal,
      if (fatsGoal != null) 'fatsGoal': fatsGoal,
      if (proteinPct != null) 'proteinPct': proteinPct,
      if (carbsPct != null) 'carbsPct': carbsPct,
      if (fatsPct != null) 'fatsPct': fatsPct,
      if (waterGoal != null) 'waterGoal': waterGoal,
      if (reminders != null) 'reminders': reminders?.map((x) => x.toMap()).toList(),
      if (theme != null) 'theme': theme?.name,
      if (aiAvatarURL != null) 'aiAvatarURL': aiAvatarURL,
      if (hasCompletedOnboarding != null) 'hasCompletedOnboarding': hasCompletedOnboarding,
      'createdAt': Timestamp.fromDate(createdAt),
      if (lastLoginAt != null) 'lastLoginAt': Timestamp.fromDate(lastLoginAt!),
    };
  }
}

class ScanResult {
  final String id;
  final String userId;
  final String foodName;
  final ScanType? type;
  final String? description;
  final String? details;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final double? fatEstimate;
  final double confidence;
  final String? imageUrl;
  final DateTime timestamp;

  ScanResult({
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

  factory ScanResult.fromMap(Map<String, dynamic> map, String id) {
    return ScanResult(
      id: id,
      userId: map['userId'] ?? '',
      foodName: map['foodName'] ?? '',
      type: map['type'] != null
          ? ScanType.values.firstWhere((e) => e.name == map['type'], orElse: () => ScanType.other)
          : null,
      description: map['description'],
      details: map['details'],
      calories: (map['calories'] as num?)?.toInt() ?? 0,
      protein: (map['protein'] as num?)?.toInt() ?? 0,
      carbs: (map['carbs'] as num?)?.toInt() ?? 0,
      fats: (map['fats'] as num?)?.toInt() ?? 0,
      fatEstimate: (map['fatEstimate'] as num?)?.toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'],
      timestamp: map['timestamp'] is Timestamp 
          ? (map['timestamp'] as Timestamp).toDate() 
          : DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'foodName': foodName,
      if (type != null) 'type': type?.name,
      if (description != null) 'description': description,
      if (details != null) 'details': details,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fats': fats,
      if (fatEstimate != null) 'fatEstimate': fatEstimate,
      'confidence': confidence,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

class ChatMessage {
  final String id;
  final String userId;
  final ChatRole role;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      userId: map['userId'] ?? '',
      role: ChatRole.values.firstWhere((e) => e.name == map['role'], orElse: () => ChatRole.user),
      text: map['text'] ?? '',
      timestamp: map['timestamp'] is Timestamp 
          ? (map['timestamp'] as Timestamp).toDate() 
          : DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role.name,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

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
      totalCalories: (map['totalCalories'] as num?)?.toInt() ?? 0,
      totalProtein: (map['totalProtein'] as num?)?.toInt() ?? 0,
      totalCarbs: (map['totalCarbs'] as num?)?.toInt() ?? 0,
      totalFats: (map['totalFats'] as num?)?.toInt() ?? 0,
      totalWater: (map['totalWater'] as num?)?.toInt() ?? 0,
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

class DailyStats {
  final String date;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final int water;

  DailyStats({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.water,
  });

  factory DailyStats.fromMap(Map<String, dynamic> map) {
    return DailyStats(
      date: map['date'] ?? '',
      calories: (map['calories'] as num?)?.toInt() ?? 0,
      protein: (map['protein'] as num?)?.toInt() ?? 0,
      carbs: (map['carbs'] as num?)?.toInt() ?? 0,
      fats: (map['fats'] as num?)?.toInt() ?? 0,
      water: (map['water'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fats': fats,
      'water': water,
    };
  }
}
