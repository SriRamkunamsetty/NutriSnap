import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/local_database.dart';
import '../services/local_file_service.dart';

/// Result report from auto-purge execution
class DataPurgeReport {
  final bool success;
  final String userEmail;
  final int purgedScans;
  final int purgedMessages;
  final int purgedSummaries;
  final int purgedImages;
  final String? archiveFilePath;
  final String backupPayloadPreview;
  final DateTime executedAt;
  final String message;

  DataPurgeReport({
    required this.success,
    required this.userEmail,
    required this.purgedScans,
    required this.purgedMessages,
    required this.purgedSummaries,
    required this.purgedImages,
    required this.archiveFilePath,
    required this.backupPayloadPreview,
    required this.executedAt,
    required this.message,
  });

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'userEmail': userEmail,
      'purgedScans': purgedScans,
      'purgedMessages': purgedMessages,
      'purgedSummaries': purgedSummaries,
      'purgedImages': purgedImages,
      'archiveFilePath': archiveFilePath,
      'executedAt': executedAt.toIso8601String(),
      'message': message,
    };
  }

  @override
  String toString() => 'DataPurgeReport(${toMap()})';
}

/// NutriSnap AI - Automatic Data Purge & Local Backup Archive Engine
/// Runs on app startup to remove scan data, chat messages, and summaries
/// older than 30 days. Prior to cleaning, compiles the full backup archive
/// and writes it to a durable local file — this app has no cloud mail relay,
/// so nothing is silently "emailed" from a background startup routine.
/// Call [composeBackupEmail] from an explicit user action (e.g. a Settings
/// button) to hand the same archive to the user's own mail app.
class DataPurgeManager {
  static const int retentionPeriodDays = 30;
  static DateTime? _lastPurgeTimestamp;

  /// Executes startup purge with pre-cleaning local archive delivery
  static Future<DataPurgeReport> runStartupPurge({
    required String userEmail,
    String? userId,
    bool force = false,
  }) async {
    final now = DateTime.now();

    // Prevent duplicate executions within the same app session unless forced
    if (!force && _lastPurgeTimestamp != null) {
      final hoursSinceLast = now.difference(_lastPurgeTimestamp!).inHours;
      if (hoursSinceLast < 12) {
        return DataPurgeReport(
          success: true,
          userEmail: userEmail,
          purgedScans: 0,
          purgedMessages: 0,
          purgedSummaries: 0,
          purgedImages: 0,
          archiveFilePath: null,
          backupPayloadPreview: 'Purge already executed recently ($hoursSinceLast hours ago)',
          executedAt: now,
          message: 'Purge skipped: already executed within last 12 hours.',
        );
      }
    }

    debugPrint('[DataPurge] Initiating 30-day auto-purge process for account: $userEmail');
    final db = LocalDatabase.instance;
    await db.initialize();

    final cutoffDate = now.subtract(const Duration(days: retentionPeriodDays));
    final cleanUid = userId ?? 'local_user_default';

    // 1. GATHER ALL DATA SCHEDULED FOR PURGING (AND COMPLETE HEALTH RECORD SNAPSHOT)
    final allUserData = await db.getAllUserData(cleanUid);
    final cutoffIso = cutoffDate.toIso8601String();

    final scans = (allUserData['scans'] as List<dynamic>?) ?? [];
    final messages = (allUserData['chat'] as List<dynamic>?) ?? [];
    final summaries = (allUserData['summaries'] as List<dynamic>?) ?? [];

    final scansToPurge = scans.where((s) {
      final ts = s['timestamp']?.toString() ?? '';
      return ts.compareTo(cutoffIso) < 0;
    }).toList();

    final messagesToPurge = messages.where((m) {
      final ts = m['timestamp']?.toString() ?? '';
      return ts.compareTo(cutoffIso) < 0;
    }).toList();

    final cutoffDateStr = "${cutoffDate.year.toString().padLeft(4, '0')}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}";
    final summariesToPurge = summaries.where((s) {
      final date = s['date']?.toString() ?? '';
      return date.compareTo(cutoffDateStr) < 0;
    }).toList();

    debugPrint('[DataPurge] Records older than 30 days found: '
        '${scansToPurge.length} scans, ${messagesToPurge.length} chat messages, ${summariesToPurge.length} daily summaries.');

    // 2. COMPILE BACKUP ARCHIVE BEFORE CLEANING
    final backupArchive = {
      'archiveTitle': 'NutriSnap AI - 30-Day Auto-Purge Backup Archive',
      'userLoginEmail': userEmail,
      'retentionPeriodDays': retentionPeriodDays,
      'archiveGeneratedAt': now.toIso8601String(),
      'purgeCutoffDate': cutoffDate.toIso8601String(),
      'purgedRecordsSummary': {
        'scansCount': scansToPurge.length,
        'messagesCount': messagesToPurge.length,
        'summariesCount': summariesToPurge.length,
      },
      'purgedDataset': {
        'scans': scansToPurge,
        'chat': messagesToPurge,
        'summaries': summariesToPurge,
      },
      'fullHistoricalSnapshot': allUserData,
    };

    final jsonPayload = jsonEncode(backupArchive);

    // 3. ARCHIVE TO A DURABLE LOCAL FILE BEFORE PURGING
    final hasDataToArchive = scansToPurge.isNotEmpty || messagesToPurge.isNotEmpty || summariesToPurge.isNotEmpty;
    String? archiveFilePath;
    if (hasDataToArchive) {
      try {
        archiveFilePath = await _writeArchiveToLocalFile(jsonPayload, now);
        debugPrint('[DataPurge] Backup archive written to local file: $archiveFilePath');
      } catch (e) {
        debugPrint('[DataPurge] Warning: could not write local archive file: $e');
      }
    }

    // 4. SAFELY CLEAN OLD DATA FROM SQLITE LOCAL DATABASE
    final purgedScansCount = await db.deleteScansOlderThan(cutoffDate, userId: cleanUid);
    final purgedMessagesCount = await db.deleteChatMessagesOlderThan(cutoffDate, userId: cleanUid);
    final purgedSummariesCount = await db.deleteDailySummariesOlderThan(cutoffDate, userId: cleanUid);

    // 5. CLEAN UP LOCAL IMAGES OLDER THAN 30 DAYS
    int purgedImagesCount = 0;
    try {
      final fileService = LocalFileService();
      purgedImagesCount = await fileService.purgeImagesOlderThan(const Duration(days: retentionPeriodDays));
    } catch (e) {
      debugPrint('[DataPurge] Image files purge warning: $e');
    }

    // 6. RECORD AUDIT LOG IN LOCAL DATABASE
    await db.recordPurgeLog({
      'id': 'purge_${now.millisecondsSinceEpoch}',
      'userEmail': userEmail,
      'purgedScansCount': purgedScansCount,
      'purgedMessagesCount': purgedMessagesCount,
      'purgedSummariesCount': purgedSummariesCount,
      'backupPayloadSize': jsonPayload.length,
      'timestamp': now.toIso8601String(),
    });

    _lastPurgeTimestamp = now;

    final result = DataPurgeReport(
      success: true,
      userEmail: userEmail,
      purgedScans: purgedScansCount,
      purgedMessages: purgedMessagesCount,
      purgedSummaries: purgedSummariesCount,
      purgedImages: purgedImagesCount,
      archiveFilePath: archiveFilePath,
      backupPayloadPreview: 'Archive size: ${(jsonPayload.length / 1024).toStringAsFixed(1)} KB'
          '${archiveFilePath != null ? ' saved to $archiveFilePath' : ' (nothing to archive)'}',
      executedAt: now,
      message: 'Cleaned records older than 30 days ($purgedScansCount scans, $purgedMessagesCount messages, '
          '$purgedSummariesCount daily summaries removed)'
          '${archiveFilePath != null ? '. A full backup archive was saved locally before cleaning.' : '.'}',
    );

    debugPrint('[DataPurge] Completed: $result');
    return result;
  }

  /// Writes the pre-purge backup archive to a durable local file so it is
  /// never lost, independent of whether the user ever emails it to themselves.
  static Future<String> _writeArchiveToLocalFile(String jsonPayload, DateTime now) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(p.join(docsDir.path, 'nutrisnap_local_storage', 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    final fileName = 'nutrisnap_backup_${now.millisecondsSinceEpoch}.json';
    final file = File(p.join(backupsDir.path, fileName));
    await file.writeAsString(jsonPayload, flush: true);
    return file.path;
  }

  /// Explicitly hands a fresh backup archive to the user's own mail app.
  /// Must only be called from a direct user action (e.g. a Settings button)
  /// — never automatically from a background routine, since that would
  /// surprise the user by switching them into their mail app unattended.
  static Future<bool> composeBackupEmail({
    required String userEmail,
    required String userId,
  }) async {
    final db = LocalDatabase.instance;
    await db.initialize();
    final allUserData = await db.getAllUserData(userId);
    final jsonPayload = jsonEncode(allUserData);

    if (userEmail.isEmpty || !userEmail.contains('@')) {
      debugPrint('[DataPurge] Invalid email provided ($userEmail), skipping mail dispatch.');
      return false;
    }

    final subject = Uri.encodeComponent('NutriSnap AI - Health Data Backup');
    final body = Uri.encodeComponent(
      "Hello,\n\n"
      "Attached below is your complete NutriSnap AI health record backup, exported directly from your device.\n\n"
      "Backup Archive Payload:\n"
      "${jsonPayload.length > 5000 ? '${jsonPayload.substring(0, 5000)}... [truncated for email]' : jsonPayload}\n\n"
      "Best regards,\n"
      "NutriSnap AI On-Device Health Manager",
    );

    final mailtoUri = Uri.parse('mailto:$userEmail?subject=$subject&body=$body');

    try {
      return await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[DataPurge] Failed to launch mail composer: $e');
      return false;
    }
  }
}
