import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/chat_message.dart';
import '../utils/datetime_utils.dart';

/// AI-coach conversation history, stored only on this device.
class ChatRepository {
  ChatRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<ChatMessage> add(String role, String text, {DateTime? at}) async {
    assert(role == 'user' || role == 'model');
    final when = at ?? DateTime.now();
    final msg = ChatMessage(
      id: 'msg_${_uuid.v4()}',
      userId: AppConfig.localUserId,
      role: role,
      text: text,
      timestamp: when.toIso8601String(),
    );
    await _db.db.insert(Tables.chatMessages, rowOf(msg));
    _db.notify(Tables.chatMessages);
    return msg;
  }

  Future<void> upsertAll(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    await _db.db.transaction((txn) async {
      final batch = txn.batch();
      for (final m in messages) {
        batch.insert(Tables.chatMessages, rowOf(m),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    _db.notify(Tables.chatMessages);
  }

  /// Oldest-first. When [limit] is set, returns the *latest* [limit] messages,
  /// still ordered oldest-first (what the model needs as context).
  Future<List<ChatMessage>> all({int? limit}) async {
    final rows = await _db.db.query(
      Tables.chatMessages,
      where: 'user_id = ?',
      whereArgs: [AppConfig.localUserId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromRow).toList();
  }

  Stream<List<ChatMessage>> watchAll() =>
      _db.watch({Tables.chatMessages}, () => all());

  Future<List<ChatMessage>> olderThan(DateTime cutoff) async {
    final rows = await _db.db.query(Tables.chatMessages,
        where: 'user_id = ? AND created_at < ?',
        whereArgs: [AppConfig.localUserId, cutoff.millisecondsSinceEpoch],
        orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList();
  }

  Future<int> deleteOlderThan(DateTime cutoff) async {
    final n = await _db.db.delete(Tables.chatMessages,
        where: 'user_id = ? AND created_at < ?',
        whereArgs: [AppConfig.localUserId, cutoff.millisecondsSinceEpoch]);
    _db.notify(Tables.chatMessages);
    return n;
  }

  /// Removes the newest message if it is a coach reply (used by "regenerate").
  Future<void> deleteLatestModelReply() async {
    final rows = await _db.db.query(Tables.chatMessages,
        where: 'user_id = ?', whereArgs: [AppConfig.localUserId], orderBy: 'created_at DESC', limit: 1);
    if (rows.isEmpty || rows.first['role'] != 'model') return;
    await _db.db.delete(Tables.chatMessages, where: 'id = ?', whereArgs: [rows.first['id']]);
    _db.notify(Tables.chatMessages);
  }

  Future<void> clear() async {
    await _db.db.delete(Tables.chatMessages);
    _db.notify(Tables.chatMessages);
  }

  Map<String, Object?> rowOf(ChatMessage m) => {
        'id': m.id,
        'user_id': AppConfig.localUserId,
        'role': m.role,
        'text': m.text,
        'created_at':
            (DateTimeUtils.parse(m.timestamp) ?? DateTime.now()).millisecondsSinceEpoch,
      };

  ChatMessage _fromRow(Map<String, Object?> r) => ChatMessage(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        role: r['role'] as String,
        text: r['text'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int)
            .toIso8601String(),
      );
}
