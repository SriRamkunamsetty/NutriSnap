class DateTimeUtils {
  /// Safely parses a DateTime, ISO8601 String, or epoch-millis int into a DateTime.
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Serializes a DateTime to the ISO8601 string format used across all
  /// on-device storage (SQLite TEXT columns and JSON export/import).
  static String? toIso8601(DateTime? dateTime) {
    if (dateTime == null) return null;
    return dateTime.toIso8601String();
  }
}
