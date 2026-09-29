import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/ai_model_card.dart';
import '../../auth/providers/user_provider.dart';
import 'privacy_center.dart';

/// Settings block for everything that concerns the user's data: the on-device
/// AI model, backup / restore, retention and erasing.
class DataPrivacySection extends ConsumerStatefulWidget {
  const DataPrivacySection({super.key});

  @override
  ConsumerState<DataPrivacySection> createState() => _DataPrivacySectionState();
}

class _DataPrivacySectionState extends ConsumerState<DataPrivacySection> {
  bool _busy = false;
  bool _includePhotos = false;
  int? _retentionDays = AppConfig.defaultRetentionDays;
  int _archiveCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await ref.read(settingsRepositoryProvider).retentionDays();
    final archives = await ref.read(retentionServiceProvider).listArchives();
    if (mounted) {
      setState(() {
        _retentionDays = days;
        _archiveCount = archives.length;
      });
    }
  }

  Future<void> _guard(Future<void> Function() job, {String? failure}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } on BackupException catch (e) {
      if (mounted) UIFeedback.showError(context, e.message);
    } catch (e) {
      debugPrint('[DataPrivacy] $e');
      if (mounted) UIFeedback.showError(context, failure ?? 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _guard(() async {
        final file = await ref
            .read(backupServiceProvider)
            .exportToFile(includeImages: _includePhotos);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'NutriSnap backup',
        ));
      }, failure: 'Could not create the backup.');

  Future<void> _restore() => _guard(() async {
        final picked = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        final path = picked?.path;
        if (path == null || !mounted) return;

        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore backup'),
            content: const Text(
                'Merge adds the backup to what is already on this device. '
                'Replace erases current meals, chats, water, activity, sleep, custom foods and mess menus first.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Merge')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replace == null) return;

        final r = await ref
            .read(backupServiceProvider)
            .restoreFromFile(File(path), replace: replace);
        await ref.read(userNotifierProvider.notifier).refreshProfile();
        if (mounted) {
          UIFeedback.showSuccess(
            context,
            'Restored ${r.scans} meals, ${r.chatMessages} messages'
            '${r.extraRows > 0 ? ', ${r.extraRows} activity and food records' : ''}'
            '${r.skipped > 0 ? ' (${r.skipped} skipped)' : ''}.',
          );
        }
      }, failure: 'Could not restore that file.');

  Future<void> _setRetention(int? days) async {
    setState(() => _retentionDays = days);
    await ref.read(settingsRepositoryProvider).setRetentionDays(days);
    // Apply right away, so shortening the window has an immediate, visible effect.
    final report = await ref.read(retentionServiceProvider).run(force: true);
    await _load();
    if (!mounted) return;
    if (report.failed) {
      UIFeedback.showError(context, 'Could not archive old history, nothing was deleted.');
    } else if (report.removedAnything) {
      UIFeedback.showInfo(context, 'Archived ${report.scans} older meals.');
    }
  }

  Future<void> _shareLatestArchive() => _guard(() async {
        final archives = await ref.read(retentionServiceProvider).listArchives();
        if (archives.isEmpty) return;
        await SharePlus.instance.share(ShareParams(
          files: [XFile(archives.first.path, mimeType: 'application/json')],
          subject: 'NutriSnap archive',
        ));
      });

  Future<void> _erase() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all data?'),
        content: const Text(
            'This permanently deletes your profile, meals, photos, chats and archives from this device. '
            'Export a backup first if you might want them back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      for (final f in await ref.read(retentionServiceProvider).listArchives()) {
        await f.delete();
      }
      await ref.read(userNotifierProvider.notifier).eraseEverything();
    }, failure: 'Could not erase your data.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12),
          child: Text('DATA & PRIVACY',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.0)),
        ),
        const ModuleShortcuts(),
        const SizedBox(height: 16),
        const AiModelCard(),
        const SizedBox(height: 16),
        const PrivacyCenterCard(),
        const SizedBox(height: 16),
        _card(
          icon: LucideIcons.hardDrive,
          title: 'Backup & restore',
          subtitle: 'Your data lives only on this phone. Keep a copy somewhere safe.',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Include meal photos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Makes the file much larger', style: TextStyle(fontSize: 11)),
              value: _includePhotos,
              onChanged: _busy ? null : (v) => setState(() => _includePhotos = v),
              activeThumbColor: AppColors.primary,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _outlined('Export', LucideIcons.upload, _export)),
                const SizedBox(width: 12),
                Expanded(child: _outlined('Restore', LucideIcons.download, _restore)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _card(
          icon: LucideIcons.archive,
          title: 'History',
          subtitle: 'Older meals and chats are saved to an archive file on this device, '
              'then removed along with their photos.',
          children: [
            DropdownButtonFormField<int?>(
              initialValue: AppConfig.retentionOptions.contains(_retentionDays) ? _retentionDays : 30,
              decoration: InputDecoration(
                labelText: 'Keep history for',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
              items: [
                for (final d in AppConfig.retentionOptions)
                  DropdownMenuItem<int?>(
                    value: d,
                    child: Text(switch (d) {
                      null => 'Forever',
                      365 => '1 year',
                      _ => '$d days',
                    }),
                  ),
              ],
              onChanged: _busy ? null : _setRetention,
            ),
            if (_archiveCount > 0) ...[
              const SizedBox(height: 12),
              _outlined('Share latest archive ($_archiveCount saved)', LucideIcons.share2, _shareLatestArchive),
            ],
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _erase,
          icon: const Icon(LucideIcons.trash2, size: 18),
          label: const Text('Erase all my data'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.errorRed,
            side: BorderSide(color: Colors.red.shade100),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ],
    );
  }

  Widget _outlined(String label, IconData icon, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: Colors.blue.shade600),
            const SizedBox(width: 12),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
