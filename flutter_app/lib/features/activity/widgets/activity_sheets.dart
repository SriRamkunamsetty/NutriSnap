import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/activity.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';
import '../../auth/providers/user_provider.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

Widget _grabber() => Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: AppColors.borderDark, borderRadius: BorderRadius.circular(3)),
      ),
    );

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Text(t.toUpperCase(),
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary)),
    );

InputDecoration _fieldDecoration({String? suffix, String? hint}) => InputDecoration(
      suffixText: suffix,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );

// -----------------------------------------------------------------------------
// Add menu
// -----------------------------------------------------------------------------

Future<void> showAddActivityMenu(BuildContext context) {
  return _sheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Add activity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        _MenuRow(
          icon: LucideIcons.dumbbell,
          title: 'Log a workout',
          subtitle: 'Walking, running, cycling, gym…',
          onTap: () {
            Navigator.pop(context);
            showLogWorkoutSheet(context);
          },
        ),
        _MenuRow(
          icon: LucideIcons.footprints,
          title: 'Add steps manually',
          subtitle: 'For a walk your phone didn\'t record',
          onTap: () {
            Navigator.pop(context);
            showManualStepsSheet(context);
          },
        ),
      ],
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.green.shade700, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Log workout
// -----------------------------------------------------------------------------

Future<void> showLogWorkoutSheet(BuildContext context) => _sheet<void>(context, const _WorkoutForm());

class _WorkoutForm extends ConsumerStatefulWidget {
  const _WorkoutForm();

  @override
  ConsumerState<_WorkoutForm> createState() => _WorkoutFormState();
}

class _WorkoutFormState extends ConsumerState<_WorkoutForm> {
  String _type = ActivityType.workout;
  late TimeOfDay _start;
  final _minutes = TextEditingController(text: '30');
  final _km = TextEditingController();
  final _kcal = TextEditingController();
  final _notes = TextEditingController();
  bool _estimate = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().subtract(const Duration(minutes: 30));
    _start = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  @override
  void dispose() {
    _minutes.dispose();
    _km.dispose();
    _kcal.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _weight => ref.read(userNotifierProvider).profile?.weight;

  int? get _mins => int.tryParse(_minutes.text.trim());

  double? get _estimated {
    final w = _weight;
    final m = _mins;
    if (w == null || m == null || m <= 0) return null;
    return ActivityType.estimateCalories(_type, minutes: m, weightKg: w);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _save() async {
    final mins = _mins;
    if (mins == null || mins < 1 || mins > 600) {
      setState(() => _error = 'Enter a duration between 1 and 600 minutes.');
      return;
    }
    final km = _km.text.trim().isEmpty ? null : double.tryParse(_km.text.trim().replaceAll(',', '.'));
    if (_km.text.trim().isNotEmpty && (km == null || km < 0 || km > 500)) {
      setState(() => _error = 'Distance must be between 0 and 500 km.');
      return;
    }

    double? kcal;
    var estimated = false;
    if (_estimate) {
      kcal = _estimated;
      estimated = kcal != null;
    } else if (_kcal.text.trim().isNotEmpty) {
      kcal = double.tryParse(_kcal.text.trim().replaceAll(',', '.'));
      if (kcal == null || kcal < 0 || kcal > 5000) {
        setState(() => _error = 'Calories must be between 0 and 5000.');
        return;
      }
    }

    final now = DateTime.now();
    var start = DateTime(now.year, now.month, now.day, _start.hour, _start.minute);
    if (start.isAfter(now)) start = start.subtract(const Duration(days: 1));
    final end = start.add(Duration(minutes: mins));

    setState(() {
      _saving = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      await ref.read(activityRepositoryProvider).addWorkout(Workout(
            id: '',
            type: _type,
            start: start,
            end: end,
            calories: kcal,
            caloriesEstimated: estimated,
            distanceMeters: km == null ? null : km * 1000,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Could not save the workout. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = _estimated;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Log a workout',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        _label('Type'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in ActivityType.workoutTypes)
              ChoiceChip(
                label: Text(ActivityType.label(t)),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
                selectedColor: Colors.green.shade100,
                labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _type == t ? Colors.green.shade900 : null),
              ),
          ],
        ),
        _label('Started at'),
        InkWell(
          onTap: _pickTime,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(LucideIcons.clock, size: 18),
              const SizedBox(width: 10),
              Text(_start.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Duration'),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: _fieldDecoration(suffix: 'min'),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Distance (optional)'),
                TextField(
                  controller: _km,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _fieldDecoration(suffix: 'km'),
                ),
              ]),
            ),
          ],
        ),
        _label('Calories burned'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: AppColors.primary,
          title: const Text('Estimate for me', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            _weight == null
                ? 'Add your weight in Settings to enable estimates.'
                : est == null
                    ? 'Enter a duration.'
                    : 'About ${est.round()} kcal for ${_mins ?? 0} min at ${_weight!.round()} kg. A rough guide, not a measurement.',
            style: const TextStyle(fontSize: 12),
          ),
          value: _estimate && _weight != null,
          onChanged: _weight == null ? null : (v) => setState(() => _estimate = v),
        ),
        if (!(_estimate && _weight != null))
          TextField(
            controller: _kcal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDecoration(suffix: 'kcal', hint: 'Optional'),
          ),
        _label('Notes (optional)'),
        TextField(controller: _notes, maxLength: 120, decoration: _fieldDecoration(hint: 'e.g. Leg day')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Save workout', busy: _saving, onPressed: _save)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Manual steps
// -----------------------------------------------------------------------------

Future<void> showManualStepsSheet(BuildContext context) => _sheet<void>(context, const _StepsForm());

class _StepsForm extends ConsumerStatefulWidget {
  const _StepsForm();

  @override
  ConsumerState<_StepsForm> createState() => _StepsFormState();
}

class _StepsFormState extends ConsumerState<_StepsForm> {
  final _steps = TextEditingController();
  final _minutes = TextEditingController(text: '20');
  final _km = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _steps.dispose();
    _minutes.dispose();
    _km.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final steps = int.tryParse(_steps.text.trim());
    final mins = int.tryParse(_minutes.text.trim()) ?? 0;
    if (steps == null || steps < 1 || steps > 100000) {
      setState(() => _error = 'Enter a step count between 1 and 100,000.');
      return;
    }
    if (mins < 1 || mins > 600) {
      setState(() => _error = 'Enter a duration between 1 and 600 minutes.');
      return;
    }
    final km = _km.text.trim().isEmpty ? 0.0 : double.tryParse(_km.text.trim().replaceAll(',', '.'));
    if (km == null || km < 0 || km > 200) {
      setState(() => _error = 'Distance must be between 0 and 200 km.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final end = DateTime.now();
    try {
      await ref.read(activityRepositoryProvider).addManualEntry(
            start: end.subtract(Duration(minutes: mins)),
            end: end,
            steps: steps,
            distanceMeters: km * 1000,
          );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Could not save. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Add steps',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Recorded as a walk that just ended, marked "Manual".',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        _label('Steps'),
        TextField(
          controller: _steps,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _fieldDecoration(suffix: 'steps'),
        ),
        Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Took'),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _fieldDecoration(suffix: 'min'),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Distance (optional)'),
                TextField(
                  controller: _km,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _fieldDecoration(suffix: 'km'),
                ),
              ]),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Add steps', busy: _saving, onPressed: _save)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Goals
// -----------------------------------------------------------------------------

Future<void> showActivityGoalsSheet(BuildContext context, ActivityGoals current) =>
    _sheet<void>(context, _GoalsForm(current: current));

class _GoalsForm extends ConsumerStatefulWidget {
  const _GoalsForm({required this.current});
  final ActivityGoals current;

  @override
  ConsumerState<_GoalsForm> createState() => _GoalsFormState();
}

class _GoalsFormState extends ConsumerState<_GoalsForm> {
  late ActivityGoals _g = widget.current;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(settingsRepositoryProvider).setActivityGoals(_g);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context);
  }

  Widget _stepper(String title, String subtitle, int value, int step, int min, int max, ValueChanged<int> onChanged) {
    final fmt = NumberFormat('#,###');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          Container(
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              IconButton(
                tooltip: 'Decrease $title',
                onPressed: value <= min ? null : () => onChanged((value - step).clamp(min, max)),
                icon: const Icon(LucideIcons.minus, size: 18),
              ),
              SizedBox(
                width: 64,
                child: Text(fmt.format(value),
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              IconButton(
                tooltip: 'Increase $title',
                onPressed: value >= max ? null : () => onChanged((value + step).clamp(min, max)),
                icon: const Icon(LucideIcons.plus, size: 18),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Activity goals',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _stepper('Daily steps', 'Your target each day', _g.dailySteps, 500, 1000, 50000,
            (v) => setState(() => _g = _g.copyWith(dailySteps: v))),
        _stepper('Active minutes', 'Per day', _g.dailyActiveMinutes, 5, 5, 300,
            (v) => setState(() => _g = _g.copyWith(dailyActiveMinutes: v))),
        _stepper('Weekly active minutes', 'Per week', _g.weeklyActiveMinutes, 15, 30, 1500,
            (v) => setState(() => _g = _g.copyWith(weeklyActiveMinutes: v))),
        _stepper('Weekly workouts', 'Logged or imported', _g.weeklyWorkouts, 1, 1, 21,
            (v) => setState(() => _g = _g.copyWith(weeklyWorkouts: v))),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Save goals', busy: _saving, onPressed: _save)),
      ],
    );
  }
}
