import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/food_twin_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/ios_kit.dart';

/// What NutriSnap has learned about how *you* eat. All of it is computed from
/// your own meals and corrections and stays on this phone.
class FoodTwinScreen extends ConsumerWidget {
  const FoodTwinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(foodTwinProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
          children: [
            Row(children: [RoundIconButton(icon: LucideIcons.chevronLeft, tooltip: 'Back', onTap: () => context.pop())]),
            const SizedBox(height: 14),
            const LargeTitle(title: 'Food Twin', subtitle: 'Learns only on this device'),
            const SizedBox(height: 18),
            profile.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (_, __) => IosCard(
                child: EmptyPanel(
                  icon: LucideIcons.circleAlert,
                  title: 'Couldn\'t load your Food Twin',
                  message: 'Something went wrong reading your history.',
                  action: TextButton(onPressed: () => ref.invalidate(foodTwinProfileProvider), child: const Text('Retry')),
                ),
              ),
              data: (p) => _Body(profile: p),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.profile});
  final FoodTwinProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acc = profile.personalAccuracy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _stat('${profile.foodsLearned}', 'Foods learned', LucideIcons.brain, Colors.green)),
          const SizedBox(width: 12),
          Expanded(
            child: _stat(
              acc == null ? '—' : '${(acc * 100).round()}%',
              'Personal accuracy',
              LucideIcons.target,
              Colors.blue,
              footnote: acc == null ? 'Needs 5 scanned foods' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _stat('${profile.correctionHistory.length}', 'Corrections', LucideIcons.pencil, Colors.orange)),
        ]),
        const SizedBox(height: 8),
        if (!profile.hasLearned)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: IosCard(
              child: EmptyPanel(
                icon: LucideIcons.sprout,
                title: 'Nothing learned yet',
                message:
                    'Scan and confirm a few meals. When you correct a portion or a name, NutriSnap remembers, and after you repeat a correction it applies it for you next time.',
              ),
            ),
          )
        else ...[
          const SectionTitle('Frequently eaten'),
          IosCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: profile.frequentlyUsedFoods.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('No foods yet.'))
                : Column(children: [
                    for (var i = 0; i < profile.frequentlyUsedFoods.length && i < 8; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.border),
                      _usageRow(profile.frequentlyUsedFoods[i]),
                    ],
                  ]),
          ),
          if (profile.regionalPreferences.isNotEmpty) ...[
            const SizedBox(height: 8),
            const SectionTitle('Your food style'),
            IosCard(child: _regions(profile.regionalPreferences)),
          ],
          const SizedBox(height: 8),
          SectionTitle('Custom foods', trailing: TextButton(onPressed: () => context.push('/food-library'), child: const Text('Manage'))),
          IosCard(
            child: profile.customFoods.isEmpty
                ? const Text('You haven\'t added any foods yet. Add family recipes in the Food Library.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
                : Wrap(spacing: 8, runSpacing: 8, children: [for (final f in profile.customFoods) SourceChip(f.name)]),
          ),
          const SizedBox(height: 8),
          const SectionTitle('Corrections'),
          IosCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: profile.correctionHistory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No corrections yet. That means the AI has matched you so far.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)))
                : Column(children: [
                    for (var i = 0; i < profile.correctionHistory.length && i < 10; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.border),
                      _correctionRow(profile.correctionHistory[i]),
                    ],
                  ]),
          ),
          if (profile.aliases.isNotEmpty) ...[
            const SizedBox(height: 8),
            const SectionTitle('Names you prefer'),
            IosCard(
              child: Column(children: [
                for (final e in profile.aliases.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(e.key, style: const TextStyle(color: AppColors.textSecondary))),
                      const Icon(LucideIcons.arrowRight, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                  ),
              ]),
            ),
          ],
        ],
        const SizedBox(height: 24),
        const Row(children: [
          Icon(LucideIcons.lock, size: 14, color: AppColors.textTertiary),
          SizedBox(width: 6),
          Expanded(
            child: Text('Your Food Twin is built on this phone and never uploaded.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
        ]),
        if (profile.hasLearned) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _confirmReset(context, ref),
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('Reset what it has learned'),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorRed, minimumSize: const Size(0, 48)),
          ),
        ],
      ],
    );
  }

  Widget _stat(String value, String label, IconData icon, MaterialColor c, {String? footnote}) => StatTile(
        icon: icon,
        color: c,
        value: value,
        unit: '',
        label: label,
        footnote: footnote,
      );

  Widget _usageRow(FoodUsage u) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(
                u.typicalPortion == null ? 'Eaten ${u.count}×' : 'Eaten ${u.count}×  ·  usually ${u.typicalPortion}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ]),
          ),
          Text('${u.avgKcal.round()} kcal', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );

  Widget _correctionRow(FoodCorrection c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.renamed ? '${c.originalName} → ${c.correctedName}' : c.correctedName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(DateFormat('d MMM, h:mm a').format(c.at), style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ]),
          ),
          Text('${c.originalKcal.round()} → ${c.correctedKcal.round()} kcal',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.correctedKcal < c.originalKcal ? Colors.green.shade700 : Colors.orange.shade800)),
        ]),
      );

  Widget _regions(Map<String, int> regions) {
    final entries = regions.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    return Column(children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 100, child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: e.value / max,
                  minHeight: 8,
                  backgroundColor: Colors.green.shade50,
                  color: Colors.green.shade500,
                ),
              ),
            ),
            SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ),
    ]);
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Food Twin?'),
        content: const Text(
            'This forgets your corrections, custom foods and food usage. Your logged meals stay as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(foodTwinServiceProvider).reset();
      if (context.mounted) UIFeedback.showSuccess(context, 'Food Twin reset');
    }
  }
}
