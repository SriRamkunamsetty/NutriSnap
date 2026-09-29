import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/coach/trends.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/datetime_utils.dart';
import '../../../core/widgets/ios_kit.dart';

/// Which window the trends cover.
final trendWindowProvider = StateProvider.autoDispose<int>((ref) => 7);

/// Recomputed whenever meals, water, activity or goals change.
final trendReportProvider = FutureProvider.autoDispose<TrendReport>((ref) async {
  final window = ref.watch(trendWindowProvider);
  ref.watch(scanHistoryStreamProvider);
  ref.watch(dailySummaryStreamProvider);
  final profile = ref.watch(profileStreamProvider).valueOrNull;
  final actGoals = ref.watch(activityGoalsProvider).valueOrNull;

  final today = DateTime.now();
  final from = DateTimeUtils.dayKey(DateTime(today.year, today.month, today.day).subtract(Duration(days: window - 1)));
  final to = DateTimeUtils.dayKey(today);

  final summaries = await ref.watch(summaryRepositoryProvider).range(from, to);
  final activityRepo = ref.watch(activityRepositoryProvider);
  final activity = await activityRepo.range(from, to);
  final sleep = await activityRepo.sleepBetween(from, to);
  ref.watch(profileStreamProvider);
  final profiles = ref.watch(profileRepositoryProvider);
  final weights = await profiles.weights(from, to);
  final before = await profiles.weightBefore(from);

  return TrendCalculator.build(
    today: today,
    windowDays: window,
    summaries: summaries,
    activity: activity,
    sleep: sleep,
    weights: [for (final w in weights) (w.date, w.kg)],
    weightBefore: before == null ? null : (before.date, before.kg),
    goals: TrendGoals(
      calories: profile?.calorieLimit,
      protein: profile?.proteinGoal,
      water: profile?.waterGoal,
      steps: actGoals?.dailySteps,
    ),
  );
});

/// Week / month trends built only from what was actually logged.
class TrendsSection extends ConsumerWidget {
  const TrendsSection({super.key});

  static final _n = NumberFormat.decimalPattern();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(trendWindowProvider);
    final report = ref.watch(trendReportProvider);
    final profile = ref.watch(profileStreamProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Trends',
          trailing: SizedBox(
            width: 170,
            child: Segmented<int>(
              value: window,
              options: const {7: 'Week', 30: 'Month'},
              onChanged: (v) => ref.read(trendWindowProvider.notifier).state = v,
            ),
          ),
        ),
        const SizedBox(height: 12),
        report.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const EmptyPanel(
            icon: LucideIcons.triangleAlert,
            title: 'Could not load trends',
            message: 'Your data is safe. Reopen this screen to retry.',
          ),
          data: (r) {
            if (r.daysLogged == 0 && r.avgSteps == null && r.avgSleepHours == null && r.avgWater == null) {
              return const EmptyPanel(
                icon: LucideIcons.chartNoAxesColumn,
                title: 'No trends yet',
                message: 'Log meals, water or activity and your trends will appear here.',
              );
            }
            return Column(children: [
              if (!r.enoughData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IosCard(
                    semanticLabel: 'Complete ${r.daysNeeded} more days of meal logging to see calorie and protein trends',
                    child: Row(children: [
                      const Icon(LucideIcons.hourglass, color: AppColors.textTertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Complete ${r.daysNeeded} more day${r.daysNeeded == 1 ? '' : 's'} of meal logging to see calorie and protein trends. '
                          '(${r.daysLogged} of ${TrendReport.minDays} so far)',
                          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  ),
                ),
              if (r.enoughData) ...[
                _MetricCard(
                  title: 'Calorie balance',
                  headline: r.calorieBalance == null
                      ? '${_n.format(r.avgCalories!.round())} kcal/day'
                      : '${r.calorieBalance! >= 0 ? '+' : '−'}${_n.format(r.calorieBalance!.abs().round())} kcal/day',
                  caption: r.calorieBalance == null
                      ? 'Average of ${r.daysLogged} logged days. Set a calorie goal to see your balance.'
                      : 'Average of ${r.daysLogged} logged days vs your ${_n.format(profile?.calorieLimit ?? 0)} kcal goal.',
                  color: AppColors.primary,
                  values: r.days.map((d) => d.calories).toList(),
                  goal: profile?.calorieLimit,
                  adherence: r.calorieAdherence,
                  adherenceLabel: 'at or under goal',
                ),
                _MetricCard(
                  title: 'Protein',
                  headline: r.avgProtein == null ? '—' : '${r.avgProtein!.round()} g/day',
                  caption: 'Average of logged days.',
                  color: const Color(0xFF8B5CF6),
                  values: r.days.map((d) => d.protein).toList(),
                  goal: profile?.proteinGoal,
                  adherence: r.proteinAdherence,
                  adherenceLabel: 'near protein goal',
                ),
              ],
              if (r.avgWater != null)
                _MetricCard(
                  title: 'Hydration',
                  headline: '${_n.format(r.avgWater!.round())} ml/day',
                  caption: 'Average of days with water logged.',
                  color: const Color(0xFF3B82F6),
                  values: r.days.map((d) => d.water).toList(),
                  goal: profile?.waterGoal,
                  adherence: r.waterAdherence,
                  adherenceLabel: 'near water goal',
                ),
              if (r.avgSteps != null)
                _MetricCard(
                  title: 'Steps',
                  headline: '${_n.format(r.avgSteps!.round())} /day',
                  caption: '${r.totalWorkouts} workout${r.totalWorkouts == 1 ? '' : 's'} · ${r.totalActiveMinutes} active min in this period.',
                  color: const Color(0xFF0EA5E9),
                  values: r.days.map((d) => d.steps).toList(),
                  goal: null,
                  adherence: r.stepAdherence,
                  adherenceLabel: 'reached step goal',
                ),
              if (r.avgSleepHours != null)
                _MetricCard(
                  title: 'Sleep',
                  headline: '${r.avgSleepHours!.toStringAsFixed(1)} h/night',
                  caption: 'Average of nights with sleep recorded.',
                  color: const Color(0xFF6366F1),
                  values: r.days.map((d) => d.sleepMinutes).toList(),
                  goal: null,
                ),
              _WeightCard(report: r, profile: profile),
              if (r.avgSteps == null && r.avgSleepHours == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Steps and sleep appear here once you connect Health Connect or add activity in the Activity tab.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
            ]);
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.headline,
    required this.caption,
    required this.color,
    required this.values,
    required this.goal,
    this.adherence,
    this.adherenceLabel,
  });

  final String title;
  final String headline;
  final String caption;
  final Color color;
  final List<int?> values;
  final int? goal;
  final Adherence? adherence;
  final String? adherenceLabel;

  @override
  Widget build(BuildContext context) {
    final maxV = [...values.whereType<int>(), if (goal != null) goal!, 1].reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IosCard(
        semanticLabel: '$title. $headline. $caption${adherence == null ? '' : ' ${adherence!.met} of ${adherence!.of} days ${adherenceLabel ?? ''}.'}',
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Flexible(child: Text(headline, textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: Stack(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final v in values)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: values.length > 14 ? 0.5 : 2),
                        child: v == null
                            ? Align(alignment: Alignment.bottomCenter, child: Container(height: 2, color: AppColors.border))
                            : FractionallySizedBox(
                                heightFactor: (v / maxV).clamp(0.03, 1.0),
                                alignment: Alignment.bottomCenter,
                                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                              ),
                      ),
                    ),
                ]),
                if (goal != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 64 * (goal! / maxV).clamp(0.0, 1.0),
                    child: Container(height: 1, color: AppColors.textTertiary.withValues(alpha: 0.6)),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
            if (adherence != null) ...[
              const SizedBox(height: 6),
              Text('${adherence!.met} of ${adherence!.of} days ${adherenceLabel ?? ''}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _WeightCard extends ConsumerWidget {
  const _WeightCard({required this.report, required this.profile});
  final TrendReport report;
  final UserProfile? profile;

  Future<void> _log(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: profile?.weight?.toStringAsFixed(1) ?? '');
    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log your weight'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'kg', hintText: 'e.g. 62.5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = double.tryParse(c.text.replaceAll(',', '.'));
              if (v == null || v < 20 || v > 400) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (kg == null || profile == null) return;
    final h = profile!.height;
    final bmi = h != null && h > 0 ? kg / ((h / 100) * (h / 100)) : profile!.bmi;
    await ref.read(profileRepositoryProvider).save(profile!.copyWith(weight: kg, bmi: bmi));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final change = report.weightChange;
    final hasTrend = change != null;
    final pts = report.weightPoints;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IosCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Weight', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(
              hasTrend ? '${report.weightEnd!.toStringAsFixed(1)} kg' : (profile?.weight != null ? '${profile!.weight!.toStringAsFixed(1)} kg' : '—'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary),
            ),
          ]),
          const SizedBox(height: 8),
          if (hasTrend && pts.length >= 2) ...[
            SizedBox(
              height: 48,
              child: CustomPaint(size: Size.infinite, painter: _LinePainter(pts, AppColors.primary)),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            hasTrend
                ? '${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)} kg over this period.'
                : 'Only recorded weights are charted. Log your weight again to see a trend.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: profile == null ? null : () => _log(context, ref),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Log weight'),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
          ),
        ]),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 0.001 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - 4 - (size.height - 8) * (values[i] - lo) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values || old.color != color;
}
