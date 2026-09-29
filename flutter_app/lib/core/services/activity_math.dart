import '../models/activity.dart';

/// Pure activity calculations (no I/O) so they can be tested exhaustively.
class ActivityMath {
  const ActivityMath._();

  /// Cadence at or above which a stretch of steps counts as "active" (brisk
  /// walking is ~100 steps/min; 60 is a deliberately generous floor).
  static const double activeCadence = 60;

  /// Builds the day summary from that day's entries and workouts.
  ///
  /// * steps / distance / active calories come from the entries; Health
  ///   Connect already folds workouts into those, so HC workouts add nothing
  ///   extra (no double counting);
  /// * manually logged workouts *do* add their calories and distance;
  /// * active minutes are the union of brisk-cadence step records and
  ///   workouts, so overlapping periods are counted once.
  static DailyActivity summarize(
    String date,
    List<ActivityEntry> entries,
    List<Workout> workouts,
  ) {
    var steps = 0;
    var distance = 0.0;
    var kcal = 0.0;
    final sources = <String>{};

    for (final e in entries) {
      steps += e.steps;
      distance += e.distanceMeters;
      kcal += e.activeCalories;
      sources.add(e.source);
    }
    for (final w in workouts) {
      sources.add(w.source);
      if (w.source == DataSource.manual) {
        kcal += w.calories ?? 0;
        distance += w.distanceMeters ?? 0;
      }
    }

    final intervals = <_Interval>[
      for (final e in entries)
        if (e.steps > 0 && e.cadence >= activeCadence) _Interval(e.start, e.end),
      for (final w in workouts) _Interval(w.start, w.end),
    ];

    return DailyActivity(
      date: date,
      steps: steps,
      distanceMeters: distance,
      activeCalories: kcal,
      activeMinutes: _unionMinutes(intervals),
      workoutCount: workouts.length,
      sources: sources,
    );
  }

  /// Waking hours (07:00-22:00) already finished at [now] in which fewer than
  /// [inactiveBelowSteps] steps were recorded. Steps in a record are spread
  /// evenly over its duration. Returns null unless a phone/watch source has
  /// reported data, because without one "no steps" only means "not measured".
  static int? inactiveHours(List<ActivityEntry> entries, DateTime now, {int inactiveBelowSteps = 30}) {
    if (!entries.any((e) => e.source != DataSource.manual)) return null;
    final day = DateTime(now.year, now.month, now.day);
    var count = 0;
    for (var h = 7; h < 22; h++) {
      final from = day.add(Duration(hours: h));
      final to = from.add(const Duration(hours: 1));
      if (to.isAfter(now)) break;
      var steps = 0.0;
      var unknown = false;
      for (final e in entries) {
        final ms = e.end.difference(e.start).inMilliseconds;
        // A long record (e.g. phone sensor read after hours) cannot tell us
        // which hour the steps were taken in, so those hours are not judged.
        if (e.end.difference(e.start) > const Duration(hours: 2) && e.end.isAfter(from) && e.start.isBefore(to)) {
          unknown = true;
          continue;
        }
        if (ms <= 0) {
          if (!e.start.isBefore(from) && e.start.isBefore(to)) steps += e.steps;
          continue;
        }
        final a = e.start.isAfter(from) ? e.start : from;
        final b = e.end.isBefore(to) ? e.end : to;
        final overlap = b.difference(a).inMilliseconds;
        if (overlap > 0) steps += e.steps * overlap / ms;
      }
      if (!unknown && steps < inactiveBelowSteps) count++;
    }
    return count;
  }

  static int _unionMinutes(List<_Interval> intervals) {
    if (intervals.isEmpty) return 0;
    final sorted = [...intervals]..sort((a, b) => a.start.compareTo(b.start));
    var total = Duration.zero;
    var curStart = sorted.first.start;
    var curEnd = sorted.first.end;
    for (final i in sorted.skip(1)) {
      if (i.start.isAfter(curEnd)) {
        total += curEnd.difference(curStart);
        curStart = i.start;
        curEnd = i.end;
      } else if (i.end.isAfter(curEnd)) {
        curEnd = i.end;
      }
    }
    total += curEnd.difference(curStart);
    return (total.inSeconds / 60).round();
  }

  /// Removes duplicate coverage when several apps (phone, watch) all report
  /// steps for the same time. Per day the origin with the most steps wins;
  /// other origins only contribute records that don't overlap the winner.
  static List<ActivityEntry> dedupeOverlaps(
    List<ActivityEntry> entries,
    String Function(DateTime) dayKey, {
    double Function(ActivityEntry)? score,
  }) {
    final weigh = score ?? (ActivityEntry e) => e.steps.toDouble();
    final byDay = <String, List<ActivityEntry>>{};
    for (final e in entries) {
      (byDay[dayKey(e.start)] ??= []).add(e);
    }

    final result = <ActivityEntry>[];
    for (final day in byDay.values) {
      final totals = <String, double>{};
      for (final e in day) {
        final o = e.origin ?? '';
        totals[o] = (totals[o] ?? 0) + weigh(e);
      }
      final ranked = totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));

      final accepted = <ActivityEntry>[];
      for (final origin in ranked) {
        final mine = day.where((e) => (e.origin ?? '') == origin);
        for (final e in mine) {
          final overlaps = accepted.any(
              (a) => (a.origin ?? '') != origin && e.start.isBefore(a.end) && e.end.isAfter(a.start));
          if (!overlaps) accepted.add(e);
        }
      }
      result.addAll(accepted);
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  /// Merges a day's raw records into readable events: records less than
  /// [gap] apart become one event (a walk), so the timeline shows
  /// "08:20 Walking, 1,240 steps" instead of dozens of tiny rows.
  static List<ActivityEvent> groupTimeline(
    List<ActivityEntry> entries, {
    Duration gap = const Duration(minutes: 10),
  }) {
    if (entries.isEmpty) return const [];
    final sorted = [...entries]..sort((a, b) => a.start.compareTo(b.start));
    final events = <ActivityEvent>[];
    var group = <ActivityEntry>[sorted.first];
    var groupEnd = sorted.first.end;

    void flush() {
      events.add(ActivityEvent.of(group));
      group = [];
    }

    for (final e in sorted.skip(1)) {
      if (e.start.difference(groupEnd) <= gap) {
        group.add(e);
        if (e.end.isAfter(groupEnd)) groupEnd = e.end;
      } else {
        flush();
        group = [e];
        groupEnd = e.end;
      }
    }
    flush();
    // Drop specks (a few stray steps) so the timeline stays meaningful.
    return events.where((e) => e.steps >= 30 || e.distanceMeters >= 30 || e.activeCalories >= 3).toList();
  }

  /// Sleep consistency from the wake-up times of the last nights, as the
  /// spread (in minutes) of the mid-sleep clock time. Needs at least 3 nights;
  /// returns null otherwise (never invent a score).
  static SleepConsistency? consistency(List<SleepEntry> nights) {
    if (nights.length < 3) return null;
    // Minutes since midnight of the bedtime, shifted so 18:00-06:00 is continuous.
    double shifted(DateTime t) {
      final m = t.hour * 60.0 + t.minute;
      return m < 12 * 60 ? m + 24 * 60 : m;
    }

    final starts = nights.map((n) => shifted(n.start)).toList();
    final mean = starts.reduce((a, b) => a + b) / starts.length;
    final variance = starts.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / starts.length;
    final spread = variance <= 0 ? 0.0 : _sqrt(variance);
    final level = spread <= 30
        ? SleepConsistency.good
        : spread <= 60
            ? SleepConsistency.fair
            : SleepConsistency.irregular;
    return SleepConsistency(level, spread.round());
  }

  static double _sqrt(double v) {
    var x = v;
    for (var i = 0; i < 30; i++) {
      x = 0.5 * (x + v / x);
    }
    return x;
  }
}

class SleepConsistency {
  const SleepConsistency(this.label, this.bedtimeSpreadMinutes);
  static const good = 'Good';
  static const fair = 'Fair';
  static const irregular = 'Irregular';

  final String label;

  /// Standard deviation of bedtime, in minutes.
  final int bedtimeSpreadMinutes;
}

class _Interval {
  const _Interval(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// A run of nearby activity records shown as one timeline row.
class ActivityEvent {
  const ActivityEvent({
    required this.start,
    required this.end,
    required this.steps,
    required this.distanceMeters,
    required this.activeCalories,
    required this.sources,
  });

  factory ActivityEvent.of(List<ActivityEntry> group) => ActivityEvent(
        start: group.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b),
        end: group.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b),
        steps: group.fold(0, (a, e) => a + e.steps),
        distanceMeters: group.fold(0.0, (a, e) => a + e.distanceMeters),
        activeCalories: group.fold(0.0, (a, e) => a + e.activeCalories),
        sources: group.map((e) => e.source).toSet(),
      );

  final DateTime start;
  final DateTime end;
  final int steps;
  final double distanceMeters;
  final double activeCalories;
  final Set<String> sources;

  Duration get duration => end.difference(start);
  double get cadence => duration.inSeconds <= 0 ? 0 : steps / (duration.inSeconds / 60);

  /// Honest label: we only say "Walking" when the pace supports it.
  String get title => steps == 0
      ? 'Movement'
      : cadence >= ActivityMath.activeCadence
          ? 'Walking'
          : 'Light movement';
}
