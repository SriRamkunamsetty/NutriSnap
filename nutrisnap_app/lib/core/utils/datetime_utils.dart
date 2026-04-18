import 'package:cloud_firestore/cloud_firestore.dart';

class DateTimeUtils {
  /// Safely parses dynamic Firestore timestamp, String, or int to DateTime
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Converts DateTime to Firestore Timestamp for serialization
  static Timestamp? toTimestamp(DateTime? dateTime) {
    if (dateTime == null) return null;
    return Timestamp.fromDate(dateTime);
  }
}
