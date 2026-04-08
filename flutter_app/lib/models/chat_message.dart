import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String userId;
  final String role;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.userId,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      userId: map['userId'] ?? '',
      role: map['role'] ?? 'user',
      text: map['text'] ?? '',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'role': role,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
