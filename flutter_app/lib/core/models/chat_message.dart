import 'package:equatable/equatable.dart';
import '../utils/datetime_utils.dart';

class ChatMessage extends Equatable {
  final String id;
  final String userId;
  final String role; // 'user' | 'model'
  final String text;
  final String timestamp; // ISO-8601

  const ChatMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      role: map['role'] == 'model' ? 'model' : 'user',
      text: map['text'] as String? ?? '',
      timestamp: DateTimeUtils.parse(map['timestamp'])?.toIso8601String() ??
          DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'role': role,
        'text': text,
        'timestamp': timestamp,
      };

  @override
  List<Object?> get props => [id, userId, role, text, timestamp];
}
