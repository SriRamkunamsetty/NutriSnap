import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';

/// Secondary navigation: the modules that do not have a tab of their own.
class ModuleShortcuts extends StatelessWidget {
  const ModuleShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, String)>[
      (LucideIcons.utensils, 'Food Library', 'Search and add foods', AppRoutes.foodLibrary),
      (LucideIcons.fingerprint, 'Food Twin', 'What the app learned from you', AppRoutes.foodTwin),
      (LucideIcons.school, 'MessOS', 'Hostel and mess menus', AppRoutes.messOs),
      (LucideIcons.heartPulse, 'Health & goals', 'Health Connect, steps, sleep goals', AppRoutes.activity),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            Semantics(
              button: true,
              label: '${items[i].$2}. ${items[i].$3}',
              child: ListTile(
                minTileHeight: 56,
                leading: Icon(items[i].$1, color: AppColors.primary),
                title: Text(items[i].$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(items[i].$3, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: () => context.push(items[i].$4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PrivacyFootprint {
  const PrivacyFootprint({required this.meals, required this.chats, required this.photoBytes});
  final int meals;
  final int chats;
  final int photoBytes;
}

final privacyFootprintProvider = FutureProvider.autoDispose<PrivacyFootprint>((ref) async {
  final db = ref.watch(appDatabaseProvider).db;
  Future<int> count(String sql) async => (await db.rawQuery(sql)).first.values.first as int;
  return PrivacyFootprint(
    meals: await count('SELECT COUNT(*) FROM ${Tables.scans}'),
    chats: await count('SELECT COUNT(*) FROM ${Tables.chatMessages}'),
    photoBytes: await ref.watch(imageStoreProvider).sizeBytes(),
  );
});

/// A plain statement of where the data lives and what the app can touch.
class PrivacyCenterCard extends ConsumerWidget {
  const PrivacyCenterCard({super.key});

  static String _size(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).ceil()} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fp = ref.watch(privacyFootprintProvider);
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
        );

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
          const Row(children: [
            Icon(LucideIcons.shieldCheck, size: 20, color: AppColors.primary),
            SizedBox(width: 12),
            Text('Privacy Center', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
          const SizedBox(height: 16),
          row(LucideIcons.smartphone, 'Stored on this phone only',
              'Meals, photos, activity, chats and goals are kept in the app\'s private storage. There is no account and no cloud database.'),
          row(LucideIcons.cpu, 'AI runs on this phone',
              'Gemma analyses your meals and answers the coach locally. Your photos and questions are never uploaded. The internet is used only to download the model once.'),
          row(LucideIcons.keyRound, 'Permissions are optional',
              'Camera and photos for scanning, notifications for reminders, physical activity for the phone step counter, and read-only Health Connect if you connect it. You can revoke any of them in system settings.'),
          row(LucideIcons.eyeOff, 'No tracking',
              'No analytics, ads or health-data telemetry.'),
          const Divider(),
          const SizedBox(height: 8),
          fp.when(
            data: (d) => Semantics(
              label: 'Stored on this device: ${d.meals} meals, ${d.chats} chat messages, photos ${_size(d.photoBytes)}',
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _chip('${d.meals} meals'),
                _chip('${d.chats} messages'),
                _chip('Photos ${_size(d.photoBytes)}'),
              ]),
            ),
            loading: () => const SizedBox(height: 24),
            error: (_, __) => const Text('Could not read storage usage.', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
