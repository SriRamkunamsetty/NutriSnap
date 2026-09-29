import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../repositories/chat_repository.dart';
import '../repositories/scan_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/summary_repository.dart';
import '../utils/datetime_utils.dart';
import 'backup_service.dart';

class RetentionReport {
  const RetentionReport({
    required this.ran,
    this.scans = 0,
    this.chatMessages = 0,
    this.waterDays = 0,
    this.archivePath,
    this.error,
  });

  final bool ran;
  final int scans;
  final int chatMessages;
  final int waterDays;
  final String? archivePath;
  final String? error;

  bool get removedAnything => scans + chatMessages + waterDays > 0;
  bool get failed => error != null;
}

/// Removes history older than the user's retention window.
///
/// Safety contract: **old data is only deleted after it has been written to an
/// archive file that was read back and verified.** If archiving fails, nothing
/// is deleted. Archives stay in the app's private folder and can be shared from
/// Settings.
class RetentionService {
  RetentionService({
    required AppDatabase database,
    required ScanRepository scans,
    required ChatRepository chat,
    required SummaryRepository summaries,
    required SettingsRepository settings,
    Future<Directory> Function()? archiveDirectory,
  })  : _archiveDirectory = archiveDirectory,
        _database = database,
        _scans = scans,
        _chat = chat,
        _summaries = summaries,
        _settings = settings;

  final Future<Directory> Function()? _archiveDirectory;
  final AppDatabase _database;
  final ScanRepository _scans;
  final ChatRepository _chat;
  final SummaryRepository _summaries;
  final SettingsRepository _settings;

  static const Duration _minInterval = Duration(hours: 20);

  Future<Directory> _archiveDir() async {
    final dir = _archiveDirectory != null
        ? await _archiveDirectory()
        : Directory(p.join((await getApplicationDocumentsDirectory()).path, 'archives'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<File>> listArchives() async {
    final dir = await _archiveDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<RetentionReport> run({DateTime? now, bool force = false}) async {
    final clock = now ?? DateTime.now();
    try {
      final days = await _settings.retentionDays();
      if (days == null) return const RetentionReport(ran: false);

      final last = await _settings.lastRetentionRun();
      if (!force && last != null && clock.difference(last) < _minInterval) {
        return const RetentionReport(ran: false);
      }

      final cutoff = clock.subtract(Duration(days: days));
      final cutoffDay = DateTimeUtils.dayKey(cutoff);

      final oldScans = await _scans.olderThan(cutoff);
      final oldChat = await _chat.olderThan(cutoff);
      final oldWater = await _summaries.allWater(before: cutoffDay);

      if (oldScans.isEmpty && oldChat.isEmpty && oldWater.isEmpty) {
        await _settings.markRetentionRun(clock);
        return const RetentionReport(ran: true);
      }

      // 1. Archive first...
      final archive = {
        'app': BackupService.appId,
        'version': BackupService.formatVersion,
        'kind': 'retention-archive',
        'archivedAt': clock.toUtc().toIso8601String(),
        'retentionDays': days,
        'cutoff': cutoff.toUtc().toIso8601String(),
        'scans': oldScans
            .map((s) => {
                  ...s.toMap(),
                  'imagePath': null, // photos are not archived, only records
                }..remove('imageUrl'))
            .toList(),
        'chat': oldChat.map((m) => m.toMap()).toList(),
        'water': oldWater,
      };
      final encoded = await compute(_encode, archive);
      final dir = await _archiveDir();
      final stamp = clock.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File(p.join(dir.path, 'nutrisnap-archive-$stamp.json'));
      await file.writeAsString(encoded, flush: true);

      // 2. ...verify it reads back with the expected record counts...
      final check = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ok = (check['scans'] as List).length == oldScans.length &&
          (check['chat'] as List).length == oldChat.length &&
          (check['water'] as Map).length == oldWater.length;
      if (!ok) {
        await file.delete();
        return const RetentionReport(
            ran: true, error: 'Archive verification failed; nothing was deleted.');
      }

      // 3. ...and only then delete.
      final removedScans = await _scans.deleteAll(oldScans);
      final removedChat = await _chat.deleteOlderThan(cutoff);
      final removedWater = await _summaries.deleteWaterBefore(cutoffDay);

      await _database.db.insert(Tables.archiveLog, {
        'created_at': clock.millisecondsSinceEpoch,
        'file_path': file.path,
        'scans_count': removedScans,
        'chat_count': removedChat,
        'water_days': removedWater,
        'retention_days': days,
      });
      await _settings.markRetentionRun(clock);

      return RetentionReport(
        ran: true,
        scans: removedScans,
        chatMessages: removedChat,
        waterDays: removedWater,
        archivePath: file.path,
      );
    } catch (e, s) {
      debugPrint('[Retention] failed, nothing deleted: $e\n$s');
      return RetentionReport(ran: true, error: e.toString());
    }
  }

  static String _encode(Map<String, dynamic> m) => jsonEncode(m);
}
