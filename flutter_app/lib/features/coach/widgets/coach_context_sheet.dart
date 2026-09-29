import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/coach/evidence.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';

/// Shows exactly what the coach knows about the user, so the AI is never a
/// black box. This is the same text that is sent to the on-device model.
Future<void> showCoachContextSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ContextSheet(),
    );

class _ContextSheet extends ConsumerWidget {
  const _ContextSheet();

  static String _label(EvidenceType t) => switch (t) {
        EvidenceType.meal => 'Meals',
        EvidenceType.nutrition => 'Daily nutrition',
        EvidenceType.hydration => 'Water',
        EvidenceType.activity => 'Activity days',
        EvidenceType.workout => 'Workouts',
        EvidenceType.sleep => 'Nights of sleep',
        EvidenceType.goal => 'Goals',
        EvidenceType.foodCorrection => 'Food corrections',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(evidenceCountsProvider).valueOrNull ?? const <EvidenceType, int>{};
    final briefing = ref.watch(coachBriefingProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.borderDark, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const Text('What your coach can see',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Row(children: [
              Icon(LucideIcons.lock, size: 14, color: AppColors.textTertiary),
              SizedBox(width: 6),
              Expanded(
                child: Text('Gemma runs on this phone. This summary never leaves your device.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ]),
            const SizedBox(height: 18),
            const Text('LAST 7 DAYS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textTertiary)),
            const SizedBox(height: 8),
            if (counts.isEmpty)
              const Text('Nothing recorded yet.', style: TextStyle(color: AppColors.textSecondary))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in counts.entries) SourceChip('${_label(e.key)} · ${e.value}'),
              ]),
            const SizedBox(height: 22),
            const Text('THE BRIEFING GEMMA RECEIVES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textTertiary)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(18)),
              child: SelectableText(
                briefing ?? 'Preparing…',
                style: const TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace', color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Only totals, goals and a few recent meals are shared with the model, never your photos or full history.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
