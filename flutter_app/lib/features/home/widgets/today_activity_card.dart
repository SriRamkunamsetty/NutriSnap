import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/models/activity.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';

/// Home's summary of today's movement. Tapping opens the Activity tab.
class TodayActivityCard extends ConsumerWidget {
  const TodayActivityCard({super.key});

  static final _num = NumberFormat('#,###');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(todayActivityProvider).valueOrNull;
    final goals = ref.watch(activityGoalsProvider).valueOrNull ?? const ActivityGoals();

    final steps = day?.steps ?? 0;
    final has = day?.hasData ?? false;
    final progress = goals.dailySteps == 0 ? 0.0 : steps / goals.dailySteps;

    return IosCard(
      onTap: () => context.go(AppRoutes.activity),
      semanticLabel: has
          ? 'Activity: ${_num.format(steps)} of ${_num.format(goals.dailySteps)} steps. Opens the Activity tab.'
          : 'Activity: no data yet today. Opens the Activity tab.',
      child: Row(
        children: [
          ProgressRing(
            progress: progress,
            color: Colors.green.shade500,
            size: 84,
            strokeWidth: 10,
            child: Icon(LucideIcons.footprints, size: 24, color: Colors.green.shade600),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TODAY\'S ACTIVITY',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                if (has) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_num.format(steps),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      const SizedBox(width: 4),
                      Text('/ ${_num.format(goals.dailySteps)} steps',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day!.activeCalories.round()} active kcal  ·  ${day.activeMinutes} min active',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ] else ...[
                  const Text('No activity yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  const Text('Connect Health Data or log a workout',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
