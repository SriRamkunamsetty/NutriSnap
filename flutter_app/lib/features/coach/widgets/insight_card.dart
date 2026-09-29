import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/coach/why_engine.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';

/// One Why Engine insight. The three parts are labelled so that computed
/// FACTS, a probable INFERENCE and a RECOMMENDATION can never be confused.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight, this.compact = false, this.onTap, this.onAsk});
  final Insight insight;

  /// Compact: just the headline and the recommendation (used on Home).
  final bool compact;
  final VoidCallback? onTap;

  /// "Ask the coach about this".
  final VoidCallback? onAsk;

  static IconData iconFor(InsightKind k) => switch (k) {
        InsightKind.protein => LucideIcons.beef,
        InsightKind.calories => LucideIcons.flame,
        InsightKind.hydration => LucideIcons.droplets,
        InsightKind.activity => LucideIcons.footprints,
        InsightKind.sleep => LucideIcons.moon,
        InsightKind.combined => LucideIcons.layers,
        InsightKind.weekly => LucideIcons.calendarDays,
        InsightKind.data => LucideIcons.clipboardList,
      };

  @override
  Widget build(BuildContext context) {
    final color = insight.positive ? Colors.green : Colors.orange;
    return IosCard(
      onTap: onTap,
      semanticLabel: '${insight.title}. ${insight.recommendation}',
      padding: EdgeInsets.all(compact ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(13)),
                child: Icon(iconFor(insight.kind), size: 19, color: color.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(insight.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.25)),
                ),
              ),
            ],
          ),
          if (compact) ...[
            const SizedBox(height: 10),
            Text(insight.recommendation,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary)),
          ] else ...[
            const SizedBox(height: 14),
            _block('FACT', insight.facts.join('\n'), Colors.blue),
            if (insight.inference != null) ...[
              const SizedBox(height: 10),
              _block('MY GUESS', insight.inference!, Colors.purple),
            ],
            const SizedBox(height: 10),
            _block('TRY', insight.recommendation, Colors.green),
            if (insight.suggestedFoods.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final f in insight.suggestedFoods) SourceChip(f)]),
            ],
            if (onAsk != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAsk,
                  icon: const Icon(LucideIcons.messageCircle, size: 16),
                  label: const Text('Ask the coach about this'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _block(String label, String text, MaterialColor c) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.shade50.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: c.shade700)),
            const SizedBox(height: 3),
            Text(text, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textPrimary)),
          ],
        ),
      );
}
