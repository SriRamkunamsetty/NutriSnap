import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/providers/app_providers.dart';
import '../../coach/widgets/insight_card.dart';

/// Exactly one, most valuable, AI-backed insight on Home. Shows nothing until
/// there is something real to say.
class TopInsightCard extends ConsumerWidget {
  const TopInsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(topInsightProvider);
    if (insight == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: InsightCard(
        insight: insight,
        compact: true,
        onTap: () => context.go(AppRoutes.coach),
      ),
    );
  }
}
