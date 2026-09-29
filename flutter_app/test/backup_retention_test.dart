import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/models/scan_result.dart';
import 'package:nutrisnap_app/core/models/user_profile.dart';
import 'package:nutrisnap_app/core/services/backup_service.dart';
import 'package:nutrisnap_app/core/services/image_store.dart';
import 'package:nutrisnap_app/core/utils/datetime_utils.dart';

import 'support/test_env.dart';

ScanResult meal(String name, int kcal, DateTime at, {String? image}) => ScanResult(
      id: '',
      userId: '',
      foodName: name,
      type: 'food',
      calories: kcal,
      protein: 10,
      carbs: 20,
      fats: 5,
      confidence: 0.9,
      imageUrl: image,
      timestamp: at.toIso8601String(),
    );

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  group('backup', () {
    test('export then restore into a fresh device reproduces the data', () async {
      final rel = await env.images.saveBytes(Uint8List.fromList([1, 2, 3, 4]), ImageKind.scan);
      await env.scans.add(meal('Dosa', 300, DateTime(2025, 2, 1, 9), image: env.images.absolutePath(rel)));
      await env.scans.add(meal('Rice', 200, DateTime(2025, 2, 1, 13)));
      await env.chat.add('user', 'hello');
      await env.summaries.addWater(750, date: '2025-02-01');
      await env.profiles.save(UserProfile(
        uid: 'x',
        email: '',
        displayName: 'Asha',
        calorieLimit: 1900,
        createdAt: DateTime(2025, 1, 1),
      ));

      final file = await env.backup.exportToFile(includeImages: true);
      final json = await file.readAsString();

      final fresh = await TestEnv.create();
      addTearDown(fresh.dispose);
      final result = await fresh.backup.restoreFromJson(json);

      expect(result.scans, 2);
      expect(result.chatMessages, 1);
      expect(result.waterDays, 1);
      expect(result.images, 1);
      expect(result.profileRestored, isTrue);
      expect(result.skipped, 0);

      final day = await fresh.summaries.forDate('2025-02-01');
      expect(day.totalCalories, 500);
      expect(day.totalWater, 750);
      expect((await fresh.profiles.get())?.displayName, 'Asha');

      final restored = (await fresh.scans.all()).firstWhere((s) => s.foodName == 'Dosa');
      expect(File(restored.imageUrl!).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('restore is idempotent (merge by id)', () async {
      await env.scans.add(meal('A', 100, DateTime(2025, 2, 1)));
      final json = await (await env.backup.exportToFile()).readAsString();
      await env.backup.restoreFromJson(json);
      await env.backup.restoreFromJson(json);
      expect((await env.scans.all()).length, 1);
    });

    test('replace mode wipes existing records first', () async {
      await env.scans.add(meal('keep-in-backup', 100, DateTime(2025, 2, 1)));
      final json = await (await env.backup.exportToFile()).readAsString();
      await env.scans.add(meal('added-later', 999, DateTime(2025, 2, 2)));

      await env.backup.restoreFromJson(json, replace: true);
      expect((await env.scans.all()).map((s) => s.foodName), ['keep-in-backup']);
    });

    test('rejects files that are not NutriSnap backups', () async {
      expect(() => env.backup.restoreFromJson('not json'), throwsA(isA<BackupException>()));
      expect(() => env.backup.restoreFromJson('{"hello":1}'), throwsA(isA<BackupException>()));
      expect(() => env.backup.restoreFromJson('[]'), throwsA(isA<BackupException>()));
    });

    test('rejects backups from a newer app version', () async {
      final json = jsonEncode({'app': 'nutrisnap', 'version': 99});
      expect(() => env.backup.restoreFromJson(json), throwsA(isA<BackupException>()));
    });

    test('malformed records are skipped, valid ones still restored', () async {
      final json = jsonEncode({
        'app': 'nutrisnap',
        'version': 3,
        'scans': [
          {'id': 'good', 'foodName': 'Ok', 'calories': 100, 'timestamp': '2025-02-01T10:00:00.000'},
          {'id': '', 'foodName': 'no id'},
          'garbage',
        ],
        'water': {'2025-02-01': 500, 'not-a-date': 5},
      });
      final r = await env.backup.restoreFromJson(json);
      expect(r.scans, 1);
      expect(r.skipped, greaterThanOrEqualTo(3));
      expect((await env.summaries.forDate('2025-02-01')).totalWater, 500);
    });

    test('a path-traversal image entry can never write outside the image folder', () async {
      final evil = File('${env.dir.path}/pwned.txt');
      final json = jsonEncode({
        'app': 'nutrisnap',
        'version': 3,
        'images': {'../pwned.txt': base64Encode([1, 2, 3])},
      });
      final r = await env.backup.restoreFromJson(json);
      expect(evil.existsSync(), isFalse);
      expect(r.images, 0);
      expect(r.skipped, 1);
    });

    test('scan referencing an unsafe image path is stored without an image', () async {
      final json = jsonEncode({
        'app': 'nutrisnap',
        'version': 3,
        'scans': [
          {
            'id': 's1',
            'foodName': 'X',
            'calories': 1,
            'imagePath': '../../etc/passwd',
            'timestamp': '2025-02-01T10:00:00.000',
          }
        ],
      });
      await env.backup.restoreFromJson(json);
      expect((await env.scans.getById('s1'))?.imageUrl, isNull);
    });
  });

  group('retention', () {
    final now = DateTime(2025, 6, 30, 12);

    test('archives first, then removes only records older than the window', () async {
      await env.settings.setRetentionDays(30);
      final rel = await env.images.saveBytes(Uint8List.fromList([7]), ImageKind.scan);
      final abs = env.images.absolutePath(rel)!;

      await env.scans.add(meal('ancient', 400, now.subtract(const Duration(days: 60)), image: abs));
      await env.scans.add(meal('recent', 300, now.subtract(const Duration(days: 5))));
      await env.chat.add('user', 'old question', at: now.subtract(const Duration(days: 45)));
      await env.chat.add('user', 'new question', at: now.subtract(const Duration(days: 1)));
      await env.summaries.addWater(500, date: DateTimeUtils.dayKey(now.subtract(const Duration(days: 50))));
      await env.summaries.addWater(250, date: DateTimeUtils.dayKey(now.subtract(const Duration(days: 2))));

      final report = await env.retention.run(now: now, force: true);

      expect(report.failed, isFalse);
      expect(report.scans, 1);
      expect(report.chatMessages, 1);
      expect(report.waterDays, 1);

      // Survivors
      expect((await env.scans.all()).map((s) => s.foodName), ['recent']);
      expect((await env.chat.all()).map((m) => m.text), ['new question']);
      // The old meal's photo was removed with it
      expect(File(abs).existsSync(), isFalse);

      // The archive exists, is valid, and holds what was removed
      final archive = jsonDecode(await File(report.archivePath!).readAsString()) as Map<String, dynamic>;
      expect((archive['scans'] as List).single['foodName'], 'ancient');
      expect((archive['chat'] as List).single['text'], 'old question');
      expect(archive['kind'], 'retention-archive');
    });

    test('keep-forever setting never deletes anything', () async {
      await env.settings.setRetentionDays(null);
      await env.scans.add(meal('ancient', 400, now.subtract(const Duration(days: 900))));
      final report = await env.retention.run(now: now, force: true);
      expect(report.ran, isFalse);
      expect((await env.scans.all()).length, 1);
    });

    test('if the archive cannot be written, NOTHING is deleted', () async {
      await env.settings.setRetentionDays(30);
      await env.scans.add(meal('ancient', 400, now.subtract(const Duration(days: 60))));

      // The archive folder lives "inside" a regular file, so it can't be created.
      final blocker = File('${env.dir.path}/not_a_dir')..writeAsStringSync('x');
      final failing = env.retentionWith(() async => Directory('${blocker.path}/sub')..createSync(recursive: true));

      final report = await failing.run(now: now, force: true);

      expect(report.failed, isTrue);
      expect((await env.scans.all()).length, 1, reason: 'data must survive a failed archive');
    });

    test('runs at most once per interval unless forced', () async {
      await env.settings.setRetentionDays(30);
      await env.scans.add(meal('ancient', 400, now.subtract(const Duration(days: 60))));
      final first = await env.retention.run(now: now);
      expect(first.scans, 1);

      await env.scans.add(meal('ancient2', 400, now.subtract(const Duration(days: 70))));
      final second = await env.retention.run(now: now.add(const Duration(hours: 1)));
      expect(second.ran, isFalse);
      expect((await env.scans.all()).length, 1);
    });

    test('defaults to 30 days when never configured', () async {
      expect(await env.settings.retentionDays(), 30);
    });
  });
}
