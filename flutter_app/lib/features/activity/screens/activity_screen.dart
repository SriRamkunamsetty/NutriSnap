import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/activity.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/activity_math.dart';
import '../../../core/services/health_connect_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/datetime_utils.dart';
import '../../../core/widgets/ios_kit.dart';
import '../widgets/activity_sheets.dart';

/// Steps, distance, active energy, movement timeline, workouts and sleep.
/// Everything shown comes from the local database; nothing is a placeholder.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {

  @override
  void initState() {
    super.initState();
    // Bring in fresh Health Connect data whenever the tab is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(healthConnectProvider.notifier).syncIfStale();
      _syncPhoneSteps();
    });
  }

  /// Phone-sensor steps are only used when Health Connect is not connected,
  /// because Health Connect already includes the phone's own steps.
  Future<void> _syncPhoneSteps() async {
    final svc = ref.read(phoneStepServiceProvider);
    final on = await svc.isEnabled();
    if (!mounted) return;
    ref.read(phoneStepsEnabledProvider.notifier).state = on;
    if (!on) return;
    if (ref.read(healthConnectProvider).connected) {
      // Health Connect already includes this phone's steps; keeping both would
      // count every step twice, so the sensor records are retired.
      await svc.disable(deleteData: true);
      if (mounted) ref.read(phoneStepsEnabledProvider.notifier).state = false;
    } else {
      await svc.sync();
    }
  }

  Future<void> _refresh() async {
    final hc = ref.read(healthConnectProvider.notifier);
    await hc.refresh();
    await hc.sync(force: true);
    await _syncPhoneSteps();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayActivityProvider);
    final goals = ref.watch(activityGoalsProvider).valueOrNull ?? const ActivityGoals();
    final hc = ref.watch(healthConnectProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              LargeTitle(
                title: 'Activity',
                subtitle: DateFormat('EEEE, d MMM').format(DateTime.now()),
                actions: [
                  RoundIconButton(
                    icon: LucideIcons.target,
                    tooltip: 'Activity goals',
                    onTap: () => showActivityGoalsSheet(context, goals),
                  ),
                  const SizedBox(width: 10),
                  RoundIconButton(
                    icon: LucideIcons.plus,
                    tooltip: 'Add activity',
                    onTap: () => showAddActivityMenu(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ConnectionCard(state: hc),
              if (!hc.connected && !hc.loading) ...[
                const SizedBox(height: 12),
                const _PhoneStepsCard(),
              ],
              const SizedBox(height: 16),
              today.when(
                data: (d) => _TodaySection(day: d, goals: goals, connected: hc.connected),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                ),
                error: (_, __) => IosCard(
                  child: EmptyPanel(
                    icon: LucideIcons.circleAlert,
                    title: 'Couldn\'t load your activity',
                    message: 'Pull down to try again.',
                    action: TextButton(onPressed: () => ref.invalidate(todayActivityProvider), child: const Text('Retry')),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const _SleepSection(),
              const _TimelineSection(),
              const _WorkoutsSection(),
              _WeekSection(goals: goals),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Connection
// -----------------------------------------------------------------------------

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.state});
  final HcState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = ref.read(healthConnectProvider.notifier);

    if (state.loading || state.availability == HcAvailability.unsupportedPlatform) {
      return const SizedBox.shrink();
    }

    // Connected: a quiet status row.
    if (state.connected) {
      final last = state.prefs.lastSync;
      return IosCard(
        padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.heartPulse, size: 18, color: Colors.green.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.syncing
                        ? 'Syncing Health Connect…'
                        : last == null
                            ? 'Health Connect connected'
                            : 'Health Connect · synced ${_ago(last)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                if (state.syncing)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    tooltip: 'Sync now',
                    onPressed: () => hc.sync(force: true),
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                  ),
              ],
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, right: 8),
                child: Text(state.error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),
            if (!state.prefs.sleep)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextButton.icon(
                  onPressed: () => hc.connect({HcGroup.sleep}),
                  icon: const Icon(LucideIcons.moon, size: 16),
                  label: const Text('Also connect sleep'),
                ),
              ),
          ],
        ),
      );
    }

    // Not usable yet: explain exactly why and what to do.
    final (icon, title, body, action, onAction) = switch (state.availability) {
      HcAvailability.unavailable => (
          LucideIcons.download,
          'Health Connect isn\'t installed',
          'Install Health Connect to bring in steps and workouts from your phone or watch. You can also log activity by hand.',
          'Get Health Connect',
          () => hc.connect({HcGroup.activity}),
        ),
      HcAvailability.needsUpdate => (
          LucideIcons.refreshCw,
          'Update Health Connect',
          'Health Connect needs an update before NutriSnap can read your steps.',
          'Update',
          () => hc.connect({HcGroup.activity}),
        ),
      _ when state.permissionDenied => (
          LucideIcons.heartOff,
          'Health data connection unavailable',
          'NutriSnap doesn\'t have permission to read your health data. If the prompt doesn\'t appear, open Health Connect › App permissions › NutriSnap and allow access. Everything else still works.',
          'Connect Health Data',
          () => hc.connect({HcGroup.activity}),
        ),
      _ => (
          LucideIcons.heartPulse,
          'Connect your health data',
          'Bring in steps, distance and workouts from Health Connect. Read-only, stored only on this phone, and you choose what to share.',
          'Connect Health Data',
          () => hc.connect({HcGroup.activity}),
        ),
    };

    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.blue.shade600, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          ProminentButton(label: action, onPressed: onAction, color: Colors.blue.shade600),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return DateFormat('d MMM').format(t);
  }
}

class _PhoneStepsCard extends ConsumerStatefulWidget {
  const _PhoneStepsCard();

  @override
  ConsumerState<_PhoneStepsCard> createState() => _PhoneStepsCardState();
}

class _PhoneStepsCardState extends ConsumerState<_PhoneStepsCard> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    final svc = ref.read(phoneStepServiceProvider);
    try {
      if (on) {
        final ok = await svc.enable();
        if (!mounted) return;
        ref.read(phoneStepsEnabledProvider.notifier).state = ok;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Allow "Physical activity" for NutriSnap in system settings to count steps.')));
        }
      } else {
        await svc.disable();
        if (mounted) ref.read(phoneStepsEnabledProvider.notifier).state = false;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(phoneStepsEnabledProvider) ?? false;
    return IosCard(
      child: Row(children: [
        Icon(LucideIcons.footprints, color: Colors.blue.shade600),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Count steps on this phone', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              on
                  ? 'Steps are added each time you open the app, from the phone\'s step sensor.'
                  : 'Uses the phone\'s step sensor, no Health Connect needed. Counting starts when you switch it on.',
              style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
            ),
          ]),
        ),
        Switch(value: on, onChanged: _busy ? null : _toggle),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Today
// -----------------------------------------------------------------------------

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.day, required this.goals, required this.connected});
  final DailyActivity day;
  final ActivityGoals goals;
  final bool connected;

  static final _num = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final progress = goals.dailySteps == 0 ? 0.0 : day.steps / goals.dailySteps;
    final pct = (progress * 100).round();
    final has = day.hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IosCard(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          semanticLabel: has
              ? '${_num.format(day.steps)} steps of ${_num.format(goals.dailySteps)} goal, $pct percent'
              : 'No step data yet today',
          child: Column(
            children: [
              ProgressRing(
                progress: progress,
                color: Colors.green.shade500,
                size: 210,
                strokeWidth: 20,
                child: has
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_num.format(day.steps),
                              style: const TextStyle(
                                  fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -2, color: AppColors.textPrimary)),
                          const Text('steps',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        ],
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.footprints, size: 34, color: AppColors.textTertiary),
                          SizedBox(height: 8),
                          Text('No steps yet',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                has
                    ? (progress >= 1
                        ? 'Goal reached · ${_num.format(goals.dailySteps)} steps'
                        : '$pct% of your ${_num.format(goals.dailySteps)}-step goal')
                    : connected
                        ? 'Nothing recorded today yet. Get moving, or add steps by hand.'
                        : 'Connect Health Data or add steps by hand.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              if (has) ...[
                const SizedBox(height: 10),
                SourceChip(day.sourceLabel),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  icon: LucideIcons.route,
                  color: Colors.blue,
                  value: has ? day.distanceKm.toStringAsFixed(day.distanceKm >= 10 ? 1 : 2) : '—',
                  unit: has ? 'km' : '',
                  label: 'Distance',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: LucideIcons.flame,
                  color: Colors.orange,
                  value: has ? _num.format(day.activeCalories.round()) : '—',
                  unit: has ? 'kcal' : '',
                  label: 'Active calories',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  icon: LucideIcons.timer,
                  color: Colors.green,
                  value: has ? '${day.activeMinutes}' : '—',
                  unit: has ? 'min' : '',
                  label: 'Active time',
                  footnote: 'Goal ${goals.dailyActiveMinutes} min',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: LucideIcons.dumbbell,
                  color: Colors.purple,
                  value: '${day.workoutCount}',
                  unit: day.workoutCount == 1 ? 'workout' : 'workouts',
                  label: 'Workouts today',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Sleep
// -----------------------------------------------------------------------------

class _SleepSection extends ConsumerWidget {
  const _SleepSection();

  static String _dur(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = ref.watch(healthConnectProvider);
    final sleep = ref.watch(recentSleepProvider).valueOrNull ?? const <SleepEntry>[];

    // Only appears when the user has connected sleep or sleep data exists.
    if (sleep.isEmpty && !hc.prefs.sleep) return const SizedBox.shrink();

    final last = sleep.isEmpty ? null : sleep.last;
    final consistency = ActivityMath.consistency(sleep);
    final recent = sleep.length > 7 ? sleep.sublist(sleep.length - 7) : sleep;
    final avg = sleep.isEmpty ? 0 : (sleep.fold<int>(0, (a, s) => a + s.minutesAsleep) / sleep.length).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Sleep'),
        IosCard(
          child: last == null
              ? const EmptyPanel(
                  icon: LucideIcons.moon,
                  title: 'No sleep recorded yet',
                  message: 'Sleep shows up here once your phone or watch has logged a night to Health Connect.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('LAST NIGHT',
                                style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textTertiary)),
                            const SizedBox(height: 4),
                            Text(_dur(last.minutesAsleep),
                                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
                            Text(
                              '${DateFormat('h:mm a').format(last.start)} – ${DateFormat('h:mm a').format(last.end)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ]),
                        ),
                        _bars(recent),
                      ],
                    ),
                    const Divider(height: 28, color: AppColors.border),
                    Row(children: [
                      Expanded(child: _kv('Average', _dur(avg), '${sleep.length} nights')),
                      Expanded(
                        child: _kv(
                          'Consistency',
                          consistency?.label ?? '—',
                          consistency == null
                              ? 'Needs 3 nights'
                              : 'Bedtime varies ±${consistency.bedtimeSpreadMinutes} min',
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    SourceChip(DataSource.label(last.source)),
                    const SizedBox(height: 4),
                    const Text('For general wellness only, not medical advice.',
                        style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                  ],
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _kv(String k, String v, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        ],
      );

  Widget _bars(List<SleepEntry> nights) {
    const maxMin = 600.0; // 10 h fills the bar
    return Semantics(
      label: 'Sleep over the last ${nights.length} nights',
      child: SizedBox(
        height: 54,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final n in nights)
              Container(
                width: 9,
                height: 6 + 48 * (n.minutesAsleep / maxMin).clamp(0.0, 1.0),
                margin: const EdgeInsets.only(left: 5),
                decoration: BoxDecoration(color: Colors.purple.shade300, borderRadius: BorderRadius.circular(5)),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Timeline
// -----------------------------------------------------------------------------

class _TimelineSection extends ConsumerWidget {
  const _TimelineSection();

  static final _num = NumberFormat('#,###');
  static final _time = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(todayTimelineProvider).valueOrNull ?? const <ActivityEntry>[];
    final events = ActivityMath.groupTimeline(entries).reversed.toList();
    final inactive = ActivityMath.inactiveHours(entries, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Timeline'),
        if (inactive != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              label: '$inactive inactive hours so far today',
              child: Text(
                '$inactive inactive hour${inactive == 1 ? '' : 's'} so far today (7 am to 10 pm, under 30 steps in the hour).',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          ),
        IosCard(
          padding: EdgeInsets.symmetric(vertical: events.isEmpty ? 20 : 8, horizontal: 20),
          child: events.isEmpty
              ? const EmptyPanel(
                  icon: LucideIcons.clock,
                  title: 'No movement recorded today',
                  message: 'Walks and activity appear here as your phone or watch records them.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < events.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.border),
                      _row(events[i]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _row(ActivityEvent e) {
    final parts = <String>[
      if (e.steps > 0) '${_num.format(e.steps)} steps',
      if (e.distanceMeters >= 30) '${(e.distanceMeters / 1000).toStringAsFixed(2)} km',
      if (e.activeCalories >= 1) '${e.activeCalories.round()} kcal',
    ];
    return Semantics(
      container: true,
      label: '${_time.format(e.start)}, ${e.title}, ${parts.join(', ')}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(_time.format(e.start),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: e.title == 'Walking' ? Colors.green.shade400 : Colors.blue.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  Text('${e.duration.inMinutes} min${parts.isEmpty ? '' : '  ·  ${parts.join('  ·  ')}'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ),
              SourceChip(e.sources.map(DataSource.label).join(' + ')),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Workouts
// -----------------------------------------------------------------------------

class _WorkoutsSection extends ConsumerWidget {
  const _WorkoutsSection();

  static final _time = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(todayWorkoutsProvider).valueOrNull ?? const <Workout>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Workouts',
          trailing: TextButton.icon(
            onPressed: () => showLogWorkoutSheet(context),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Log'),
          ),
        ),
        IosCard(
          padding: EdgeInsets.symmetric(vertical: workouts.isEmpty ? 20 : 6, horizontal: 20),
          child: workouts.isEmpty
              ? EmptyPanel(
                  icon: LucideIcons.dumbbell,
                  title: 'No workouts today',
                  message: 'Workouts from Health Connect show up automatically. NutriSnap never guesses a workout; log one yourself any time.',
                  action: OutlinedButton(
                    onPressed: () => showLogWorkoutSheet(context),
                    child: const Text('Log a workout'),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < workouts.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.border),
                      _row(context, ref, workouts[i]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Workout w) {
    final parts = <String>[
      '${w.durationMinutes} min',
      if ((w.distanceMeters ?? 0) > 0) '${(w.distanceMeters! / 1000).toStringAsFixed(2)} km',
      if ((w.calories ?? 0) > 0) '${w.calories!.round()} kcal${w.caloriesEstimated ? ' (est.)' : ''}',
      if (w.avgHeartRate != null) '${w.avgHeartRate} bpm',
    ];
    return Dismissible(
      key: ValueKey(w.id),
      direction: w.source == DataSource.manual ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(activityRepositoryProvider).deleteWorkout(w.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(14)),
              child: Icon(LucideIcons.dumbbell, size: 20, color: Colors.purple.shade600),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${ActivityType.label(w.type)} · ${_time.format(w.start)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(parts.join('  ·  '), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (w.notes != null)
                  Text(w.notes!, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ]),
            ),
            SourceChip(DataSource.label(w.source)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// This week
// -----------------------------------------------------------------------------

class _WeekSection extends ConsumerWidget {
  const _WeekSection({required this.goals});
  final ActivityGoals goals;

  static final _num = NumberFormat('#,###');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(activityRangeProvider(7)).valueOrNull ?? const <DailyActivity>[];
    final byDate = {for (final d in week) d.date: d};
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];

    final activeMinutes = week.fold<int>(0, (a, d) => a + d.activeMinutes);
    final workouts = week.fold<int>(0, (a, d) => a + d.workoutCount);
    final daysWithData = week.where((d) => d.steps > 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('This week'),
        IosCard(
          child: daysWithData < 2
              ? EmptyPanel(
                  icon: LucideIcons.chartColumn,
                  title: 'Building your weekly trend',
                  message: daysWithData == 0
                      ? 'Your steps will chart here once activity is recorded.'
                      : 'One more day of activity unlocks your weekly trend.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 130,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final day in days) Expanded(child: _bar(byDate[DateTimeUtils.dayKey(day)], day)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _goalRow('Active minutes', activeMinutes, goals.weeklyActiveMinutes, 'min', Colors.green),
                    const SizedBox(height: 12),
                    _goalRow('Workouts', workouts, goals.weeklyWorkouts, '', Colors.purple),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _bar(DailyActivity? d, DateTime day) {
    final steps = d?.steps ?? 0;
    final frac = goals.dailySteps == 0 ? 0.0 : (steps / goals.dailySteps).clamp(0.0, 1.0);
    final hit = steps >= goals.dailySteps && steps > 0;
    return Semantics(
      label: '${DateFormat('EEEE').format(day)}: ${_num.format(steps)} steps',
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(steps == 0 ? '' : (steps >= 1000 ? '${(steps / 1000).toStringAsFixed(1)}k' : '$steps'),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textTertiary)),
            const SizedBox(height: 4),
            Flexible(
              child: FractionallySizedBox(
                heightFactor: steps == 0 ? 0.04 : (0.08 + 0.92 * frac),
                child: Container(
                  width: 18,
                  decoration: BoxDecoration(
                    color: steps == 0
                        ? AppColors.border
                        : hit
                            ? Colors.green.shade500
                            : Colors.green.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(DateFormat('E').format(day).substring(0, 1),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _goalRow(String label, int value, int goal, String unit, MaterialColor color) {
    final frac = goal == 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
    return Semantics(
      label: '$label: $value of $goal $unit',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              Text('$value / $goal${unit.isEmpty ? '' : ' $unit'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                backgroundColor: color.shade50,
                color: color.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
