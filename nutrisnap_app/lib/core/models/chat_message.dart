import 'package:equatable/equatable.dart';
import '../utils/datetime_utils.dart';

class ChatMessage extends Equatable {
  final String id;
  final String userId;
  final String role; // 'user' | 'model'
  final String text;
  final String timestamp;

  const ChatMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      role: map['role'] ?? 'user',
      text: map['text'] ?? '',
      timestamp: DateTimeUtils.parse(map['timestamp'])?.toIso8601String() ?? DateTime.now().toIso8601String(),
    );
  }

  @override
  List<Object?> get props => [id, userId, role, text, timestamp];
}
