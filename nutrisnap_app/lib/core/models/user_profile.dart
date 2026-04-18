import 'package:equatable/equatable.dart';
import '../enums/app_enums.dart';
import '../utils/datetime_utils.dart';
import 'reminder.dart';

class UserProfile extends Equatable {
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
  final double? proteinPct;
  final double? carbsPct;
  final double? fatsPct;
  final int? waterGoal;
  final List<Reminder>? reminders;
  final AppTheme? theme;
  final String? aiAvatarURL;
  final bool? hasCompletedOnboarding;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const UserProfile({
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

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String?,
      photoURL: map['photoURL'] as String?,
      height: (map['height'] as num?)?.toDouble(),
      weight: (map['weight'] as num?)?.toDouble(),
      bmi: (map['bmi'] as num?)?.toDouble(),
      bodyType: BodyTypeExtension.fromString(map['bodyType'] as String?),
      fatEstimate: (map['fatEstimate'] as num?)?.toDouble(),
      bodyScanURL: map['bodyScanURL'] as String?,
      goal: GoalExtension.fromString(map['goal'] as String?),
      calorieLimit: map['calorieLimit'] as int?,
      proteinGoal: map['proteinGoal'] as int?,
      carbsGoal: map['carbsGoal'] as int?,
      fatsGoal: map['fatsGoal'] as int?,
      proteinPct: (map['proteinPct'] as num?)?.toDouble(),
      carbsPct: (map['carbsPct'] as num?)?.toDouble(),
      fatsPct: (map['fatsPct'] as num?)?.toDouble(),
      waterGoal: map['waterGoal'] as int?,
      reminders: (map['reminders'] as List<dynamic>?)
          ?.map((e) => Reminder.fromMap(e as Map<String, dynamic>))
          .toList(),
      theme: AppThemeExtension.fromString(map['theme'] as String?),
      aiAvatarURL: map['aiAvatarURL'] as String?,
      hasCompletedOnboarding: map['hasCompletedOnboarding'] as bool?,
      createdAt: DateTimeUtils.parse(map['createdAt']) ?? DateTime.now(),
      lastLoginAt: DateTimeUtils.parse(map['lastLoginAt']),
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
      if (bodyType != null) 'bodyType': bodyType!.name,
      if (fatEstimate != null) 'fatEstimate': fatEstimate,
      if (bodyScanURL != null) 'bodyScanURL': bodyScanURL,
      if (goal != null) 'goal': goal!.name,
      if (calorieLimit != null) 'calorieLimit': calorieLimit,
      if (proteinGoal != null) 'proteinGoal': proteinGoal,
      if (carbsGoal != null) 'carbsGoal': carbsGoal,
      if (fatsGoal != null) 'fatsGoal': fatsGoal,
      if (proteinPct != null) 'proteinPct': proteinPct,
      if (carbsPct != null) 'carbsPct': carbsPct,
      if (fatsPct != null) 'fatsPct': fatsPct,
      if (waterGoal != null) 'waterGoal': waterGoal,
      if (reminders != null) 'reminders': reminders!.map((x) => x.toMap()).toList(),
      if (theme != null) 'theme': theme!.name,
      if (aiAvatarURL != null) 'aiAvatarURL': aiAvatarURL,
      if (hasCompletedOnboarding != null) 'hasCompletedOnboarding': hasCompletedOnboarding,
      'createdAt': DateTimeUtils.toTimestamp(createdAt),
      if (lastLoginAt != null) 'lastLoginAt': DateTimeUtils.toTimestamp(lastLoginAt),
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
    BodyType? bodyType,
    double? fatEstimate,
    String? bodyScanURL,
    Goal? goal,
    int? calorieLimit,
    int? proteinGoal,
    int? carbsGoal,
    int? fatsGoal,
    double? proteinPct,
    double? carbsPct,
    double? fatsPct,
    int? waterGoal,
    List<Reminder>? reminders,
    AppTheme? theme,
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

  @override
  List<Object?> get props => [
        uid, email, displayName, photoURL, height, weight, bmi, bodyType,
        fatEstimate, bodyScanURL, goal, calorieLimit, proteinGoal,
        carbsGoal, fatsGoal, proteinPct, carbsPct, fatsPct, waterGoal,
        reminders, theme, aiAvatarURL, hasCompletedOnboarding,
        createdAt, lastLoginAt,
      ];
}
