import 'package:equatable/equatable.dart';

class Reminder extends Equatable {
  final String id;
  final String time; // HH:mm
  final String type; // 'meal' | 'water' | 'breakfast' | 'lunch' | 'dinner'
  final bool enabled;
  final String? label;
  final String? message;

  const Reminder({
    required this.id,
    required this.time,
    required this.type,
    required this.enabled,
    this.label,
    this.message,
  });

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as String? ?? '',
      time: map['time'] as String? ?? '12:00',
      type: map['type'] as String? ?? 'meal',
      enabled: map['enabled'] as bool? ?? false,
      label: map['label'] as String?,
      message: map['message'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'type': type,
      'enabled': enabled,
      if (label != null) 'label': label,
      if (message != null) 'message': message,
    };
  }

  Reminder copyWith({
    String? id,
    String? time,
    String? type,
    bool? enabled,
    String? label,
    String? message,
  }) {
    return Reminder(
      id: id ?? this.id,
      time: time ?? this.time,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [id, time, type, enabled, label, message];
}
