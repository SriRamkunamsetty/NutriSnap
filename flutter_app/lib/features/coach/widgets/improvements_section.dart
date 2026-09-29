import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/ios_kit.dart';
import 'insight_card.dart';

/// The Insights tab's "what to improve" list. Each card blends nutrition and
/// activity evidence (the Why Engine), with FACT / MY GUESS / TRY separated.
class ImprovementsSection extends ConsumerWidget {
  const ImprovementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(coachSnapshotProvider);
    final insights = ref.watch(insightsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Improvements for you'),
        if (snap.isLoading && insights.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (snap.hasError)
          IosCard(
            child: EmptyPanel(
              icon: LucideIcons.circleAlert,
              title: 'Couldn\'t analyse your day',
              message: 'Something went wrong reading your data.',
              action: TextButton(onPressed: () => ref.invalidate(coachSnapshotProvider), child: const Text('Retry')),
            ),
          )
        else if (insights.isEmpty)
          const IosCard(
            child: EmptyPanel(
              icon: LucideIcons.sprout,
              title: 'Not enough to go on yet',
              message: 'Log meals, water and activity for a day or two and personalised improvements will appear here.',
            ),
          )
        else
          for (final i in insights.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InsightCard(insight: i, onAsk: () => context.go(AppRoutes.coach)),
            ),
        const SizedBox(height: 12),
      ],
    );
  }
}
