enum Goal { lose, maintain, gain }
enum BodyType { lean, normal, obese, unknown }
enum AppTheme { light, dark }

extension GoalExtension on Goal {
  static Goal fromString(String? value) {
    if (value == null) return Goal.lose;
    return Goal.values.asNameMap()[value.toLowerCase()] ?? Goal.lose;
  }
}

extension BodyTypeExtension on BodyType {
  static BodyType fromString(String? value) {
    if (value == null) return BodyType.unknown;
    return BodyType.values.asNameMap()[value.toLowerCase()] ?? BodyType.unknown;
  }
}

extension AppThemeExtension on AppTheme {
  static AppTheme fromString(String? value) {
    if (value == null) return AppTheme.light;
    return AppTheme.values.asNameMap()[value.toLowerCase()] ?? AppTheme.light;
  }
}
