import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/chat_message.dart';
import '../models/scan_result.dart';
import '../models/user_profile.dart';
import '../repositories/chat_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/scan_repository.dart';
import '../repositories/summary_repository.dart';
import 'image_store.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RestoreResult {
  const RestoreResult({
    required this.scans,
    required this.chatMessages,
    required this.waterDays,
    required this.images,
    required this.skipped,
    required this.profileRestored,
    this.extraRows = 0,
  });

  final int scans;
  final int chatMessages;
  final int waterDays;
  final int images;
  final int skipped;
  final bool profileRestored;

  /// Activity, workouts, sleep, custom foods, corrections and mess data.
  final int extraRows;
}

/// Full-fidelity export / import of everything stored on the device.
///
/// The file is plain JSON so users can read it, keep it, and move it between
/// devices without any server. Restores are validated first and then written
/// in a single SQLite transaction: a bad file can never half-apply.
class BackupService {
  BackupService({
    required AppDatabase database,
    required ImageStore images,
    required ProfileRepository profiles,
    required ScanRepository scans,
    required SummaryRepository summaries,
    required ChatRepository chat,
    Future<Directory> Function()? tempDirectory,
  })  : _tempDirectory = tempDirectory,
        _database = database,
        _images = images,
        _profiles = profiles,
        _scans = scans,
        _summaries = summaries,
        _chat = chat;

  final Future<Directory> Function()? _tempDirectory;
  final AppDatabase _database;
  final ImageStore _images;
  final ProfileRepository _profiles;
  final ScanRepository _scans;
  final SummaryRepository _summaries;
  final ChatRepository _chat;

  static const String appId = 'nutrisnap';
  static const int formatVersion = 4;

  /// Tables carried as raw rows, parents before children. `foods` is limited
  /// to the user's own (custom) foods: the built-in library is re-seeded.
  static const List<String> _extraTables = [
    Tables.activityEntries,
    Tables.workouts,
    Tables.sleepEntries,
    Tables.foods,
    Tables.messes,
    Tables.messMenus,
    Tables.messMeals,
    Tables.foodCorrections,
    Tables.weightEntries,
  ];

  /// Refuse to embed more image data than this in one JSON file.
  static const int _maxEmbeddedImageBytes = 150 * 1024 * 1024;

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> buildSnapshot({bool includeImages = false}) async {
    final profile = await _profiles.get();
    final scans = await _scans.all();
    final chat = await _chat.all();
    final water = await _summaries.allWater();

    final images = <String, String>{};
    final scanMaps = <Map<String, dynamic>>[];
    var embedded = 0;

    Future<void> embed(String? rel) async {
      if (!includeImages || rel == null || images.containsKey(rel)) return;
      final bytes = await _images.read(rel);
      if (bytes == null) return;
      if (embedded + bytes.length > _maxEmbeddedImageBytes) return;
      embedded += bytes.length;
      images[rel] = base64Encode(bytes);
    }

    for (final s in scans) {
      final rel = _images.relativize(s.imageUrl);
      scanMaps.add({...s.toMap(), 'imagePath': rel}..remove('imageUrl'));
      await embed(rel);
    }

    Map<String, dynamic>? profileMap;
    if (profile != null) {
      final photoRel = _images.relativize(profile.photoURL);
      final bodyRel = _images.relativize(profile.bodyScanURL);
      profileMap = {
        ...profile.toMap(),
        'photoPath': photoRel,
        'bodyScanPath': bodyRel,
      }
        ..remove('photoURL')
        ..remove('bodyScanURL');
      await embed(photoRel);
      await embed(bodyRel);
    }

    return {
      'app': appId,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'includesImages': includeImages,
      'profile': profileMap,
      'scans': scanMaps,
      'chat': chat.map((m) => m.toMap()).toList(),
      'water': water,
      'tables': await _dumpExtraTables(),
      if (includeImages) 'images': images,
    };
  }

  Future<Map<String, List<Map<String, Object?>>>> _dumpExtraTables() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in _extraTables) {
      final rows = await _database.db.query(t, where: t == Tables.foods ? 'is_custom = 1' : null);
      if (rows.isNotEmpty) out[t] = rows;
    }
    return out;
  }

  /// Rows from a backup, reduced to columns that exist in this app version
  /// (so a backup from a slightly different schema still restores).
  Future<Map<String, List<Map<String, Object?>>>> _parseExtraTables(dynamic raw) async {
    final out = <String, List<Map<String, Object?>>>{};
    if (raw is! Map) return out;
    for (final t in _extraTables) {
      final list = raw[t];
      if (list is! List) continue;
      final cols = (await _database.db.rawQuery('PRAGMA table_info($t)'))
          .map((r) => r['name'] as String)
          .toSet();
      final rows = <Map<String, Object?>>[];
      for (final r in list) {
        if (r is! Map) continue;
        final row = <String, Object?>{};
        r.forEach((k, v) {
          if (k is String && cols.contains(k) && (v == null || v is num || v is String)) row[k] = v;
        });
        if (row['id'] is String && (row['id'] as String).isNotEmpty) rows.add(row);
      }
      if (rows.isNotEmpty) out[t] = rows;
    }
    return out;
  }

  /// Writes a backup to the temp directory and returns it (ready to share).
  Future<File> exportToFile({bool includeImages = false}) async {
    final snapshot = await buildSnapshot(includeImages: includeImages);
    final dir = _tempDirectory != null ? await _tempDirectory() : await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 16);
    final file = File(p.join(dir.path, 'nutrisnap-backup-$stamp.json'));
    // jsonEncode on a large payload blocks the UI isolate; offload it.
    final encoded = await compute(_encode, snapshot);
    await file.writeAsString(encoded, flush: true);
    return file;
  }

  static String _encode(Map<String, dynamic> m) => jsonEncode(m);
  static dynamic _decode(String s) => jsonDecode(s);

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  Future<RestoreResult> restoreFromFile(File file, {bool replace = false}) async {
    final size = await file.length();
    if (size > 500 * 1024 * 1024) {
      throw BackupException('This file is too large to be a NutriSnap backup.');
    }
    return restoreFromJson(await file.readAsString(), replace: replace);
  }

  /// [replace] wipes existing data first; otherwise records are merged by id.
  Future<RestoreResult> restoreFromJson(String json, {bool replace = false}) async {
    dynamic decoded;
    try {
      decoded = await compute(_decode, json);
    } catch (_) {
      throw BackupException('That file is not valid JSON.');
    }
    if (decoded is! Map || decoded['app'] != appId) {
      throw BackupException('That file is not a NutriSnap backup.');
    }
    final version = decoded['version'];
    if (version is! int || version < 1) {
      throw BackupException('Unrecognised backup version.');
    }
    if (version > formatVersion) {
      throw BackupException(
          'This backup was made by a newer version of NutriSnap. Please update the app.');
    }

    var skipped = 0;

    // 1. Parse + validate everything before touching disk or database.
    final scans = <ScanResult>[];
    for (final raw in (decoded['scans'] as List? ?? const [])) {
      try {
        final m = Map<String, dynamic>.from(raw as Map);
        final rel = m['imagePath'] as String?;
        final scan = ScanResult.fromMap(m);
        if (scan.id.isEmpty || scan.foodName.trim().isEmpty) {
          skipped++;
          continue;
        }
        scans.add(scan.copyWith(
          userId: AppConfig.localUserId,
          imageUrl: rel != null && _images.isSafeRelative(rel)
              ? _images.absolutePath(rel)
              : null,
        ));
      } catch (_) {
        skipped++;
      }
    }

    final chat = <ChatMessage>[];
    for (final raw in (decoded['chat'] as List? ?? const [])) {
      try {
        final msg = ChatMessage.fromMap(Map<String, dynamic>.from(raw as Map));
        if (msg.id.isEmpty || msg.text.isEmpty) {
          skipped++;
          continue;
        }
        chat.add(msg);
      } catch (_) {
        skipped++;
      }
    }

    final water = <String, int>{};
    final rawWater = decoded['water'];
    if (rawWater is Map) {
      rawWater.forEach((k, v) {
        if (k is String &&
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k) &&
            v is num) {
          water[k] = v.round().clamp(0, AppConfig.maxWaterPerDayMl);
        } else {
          skipped++;
        }
      });
    }

    final extra = await _parseExtraTables(decoded['tables']);
    if (extra[Tables.foods] != null) {
      for (final r in extra[Tables.foods]!) {
        r['is_custom'] = 1;
      }
    }

    UserProfile? profile;
    final rawProfile = decoded['profile'];
    if (rawProfile is Map) {
      try {
        final m = Map<String, dynamic>.from(rawProfile);
        final photo = m.remove('photoPath') as String?;
        final body = m.remove('bodyScanPath') as String?;
        if (photo != null && _images.isSafeRelative(photo)) {
          m['photoURL'] = _images.absolutePath(photo);
        }
        if (body != null && _images.isSafeRelative(body)) {
          m['bodyScanURL'] = _images.absolutePath(body);
        }
        profile = UserProfile.fromMap(m).copyWith(uid: AppConfig.localUserId);
      } catch (_) {
        skipped++;
      }
    }

    // 2. Restore image files (only safe relative paths).
    var imageCount = 0;
    final rawImages = decoded['images'];
    if (rawImages is Map) {
      for (final entry in rawImages.entries) {
        final rel = entry.key;
        if (rel is! String || entry.value is! String) continue;
        if (!_images.isSafeRelative(rel)) {
          skipped++;
          continue;
        }
        try {
          final file = File(_images.absolutePath(rel)!);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(base64Decode(entry.value as String), flush: true);
          imageCount++;
        } catch (_) {
          skipped++;
        }
      }
    }

    // 3. One transaction: all-or-nothing.
    var extraRows = 0;
    await _database.db.transaction((txn) async {
      if (replace) {
        await txn.delete(Tables.scans);
        await txn.delete(Tables.chatMessages);
        await txn.delete(Tables.waterIntake);
        for (final t in _extraTables.reversed) {
          await txn.delete(t, where: t == Tables.foods ? 'is_custom = 1' : null);
        }
      }
      await _scans.upsertInTransaction(txn, scans);
      final known = {
        for (final r in await txn.query(Tables.scans, columns: ['id'])) r['id'] as String,
      };
      for (final t in _extraTables) {
        for (final row in extra[t] ?? const <Map<String, Object?>>[]) {
          if (t == Tables.foodCorrections && !known.contains(row['scan_id'])) {
            skipped++;
            continue;
          }
          if (t == Tables.messMeals && !known.contains(row['logged_scan_id'])) {
            row['logged_scan_id'] = null;
          }
          try {
            await txn.insert(t, row, conflictAlgorithm: ConflictAlgorithm.replace);
            extraRows++;
          } catch (_) {
            skipped++; // e.g. a menu whose mess is missing
          }
        }
      }
      final batch = txn.batch();
      for (final m in chat) {
        batch.insert(Tables.chatMessages, _chat.rowOf(m),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      water.forEach((day, ml) {
        batch.insert(
          Tables.waterIntake,
          {'user_id': AppConfig.localUserId, 'local_date': day, 'total_ml': ml},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await batch.commit(noResult: true);
    });
    for (final t in [Tables.scans, Tables.chatMessages, Tables.waterIntake, ..._extraTables]) {
      _database.notify(t);
    }

    if (profile != null) await _profiles.save(profile);

    return RestoreResult(
      scans: scans.length,
      chatMessages: chat.length,
      waterDays: water.length,
      images: imageCount,
      skipped: skipped,
      profileRestored: profile != null,
      extraRows: extraRows,
    );
  }
}
