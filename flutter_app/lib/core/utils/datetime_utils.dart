class DateTimeUtils {
  const DateTimeUtils._();

  /// Parses an ISO-8601 string, epoch milliseconds, or [DateTime].
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Serialises a [DateTime] for storage. Always UTC ISO-8601.
  static String? toIso(DateTime? dateTime) => dateTime?.toUtc().toIso8601String();

  /// Local calendar day key (`yyyy-MM-dd`). Uses the device's local time so a
  /// meal eaten at 11:30 pm counts towards that day, not the next UTC day.
  static String dayKey(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  static String today() => dayKey(DateTime.now());
}
