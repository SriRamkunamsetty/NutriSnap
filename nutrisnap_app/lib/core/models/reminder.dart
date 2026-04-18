import 'package:equatable/equatable.dart';

class Reminder extends Equatable {
  final String id;
  final String time; // HH:mm
  final String type; // 'meal' | 'water'
  final bool enabled;

  const Reminder({
    required this.id,
    required this.time,
    required this.type,
    required this.enabled,
  });

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as String? ?? '',
      time: map['time'] as String? ?? '12:00',
      type: map['type'] as String? ?? 'meal',
      enabled: map['enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'type': type,
      'enabled': enabled,
    };
  }

  Reminder copyWith({
    String? id,
    String? time,
    String? type,
    bool? enabled,
  }) {
    return Reminder(
      id: id ?? this.id,
      time: time ?? this.time,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  List<Object?> get props => [id, time, type, enabled];
}
