import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../event.dart';
import '../event_type.dart';
import '../legacy/legacy_cell.dart';
import 'daily_stats.dart';
import 'sleep.dart';

/// The 7 dates ending on [today], oldest first.
List<String> weekDays(String today, {int n = 7}) => [
  for (var i = n - 1; i >= 0; i--) addDays(today, -i),
];

/// One row of the sleep-window card: track 21:00 → 11:00 (14 h).
class SleepRow extends Equatable {
  const SleepRow({
    required this.date,
    this.window,
    this.hours,
    this.approx = false,
  });

  /// The morning the night ended (DECISIONS 6).
  final String date;
  final SleepWindow? window;

  /// From the window, or from a legacy Daily Summary cell.
  final double? hours;
  final bool approx;

  static const trackStart = 21 * 60;
  static const trackLength = 14 * 60;

  /// Bar start/end as 0–1 of the track; null without bed and wake times.
  (double, double)? get bar {
    final w = window;
    final m = w?.minutes;
    if (w == null || m == null || m <= 0) return null;
    final bed = minutesOf(w.bed)!;
    final start = ((bed - trackStart) % (24 * 60)) / trackLength;
    final end = start + m / trackLength;
    return (start.clamp(0.0, 1.0), end.clamp(0.0, 1.0));
  }

  bool get late => window?.late ?? false;

  @override
  List<Object?> get props => [date, window, hours, approx];
}

class WeekStats extends Equatable {
  const WeekStats({
    required this.days,
    required this.cigs,
    required this.sleep,
    required this.daysLogged,
    required this.notLogged,
    required this.studySessions,
  });

  final List<String> days;

  /// Cigarettes per day; null = nothing logged (a gap, never 0).
  final List<double?> cigs;
  final List<SleepRow> sleep;
  final int daysLogged;

  /// Metric → days in the week with at least one entry.
  final Map<String, int> notLogged;
  final int studySessions;

  double? get cigTotal {
    final v = cigs.whereType<double>();
    return v.isEmpty ? null : v.reduce((a, b) => a + b);
  }

  double? get sleepAvg {
    final h = sleep.map((r) => r.hours).whereType<double>();
    return h.isEmpty ? null : h.reduce((a, b) => a + b) / h.length;
  }

  int get nights7h => sleep.where((r) => (r.hours ?? 0) >= 7).length;

  @override
  List<Object?> get props => [
    days,
    cigs,
    sleep,
    daysLogged,
    notLogged,
    studySessions,
  ];
}

/// [events] = effective Events plus legacy (see `withLegacy`).
WeekStats weekStats(
  List<Event> events,
  List<String> days, {
  Map<String, LegacyCell> legacySleepHours = const {},
}) {
  final inWeek = events.where((e) => days.contains(e.date)).toList();
  final summaries = {for (final d in days) d: summarize(inWeek, d)};
  final windows = sleepWindows(events);

  int daysWith(bool Function(Event) test) =>
      days.where((d) => inWeek.any((e) => e.date == d && test(e))).length;

  return WeekStats(
    days: days,
    cigs: [for (final d in days) summaries[d]!.cigs],
    sleep: [
      for (final d in days)
        () {
          final w = nightEndingOn(windows, d);
          if (w != null && w.hours != null) {
            return SleepRow(
              date: d,
              window: w,
              hours: w.hours,
              approx: w.approx,
            );
          }
          final legacy = legacySleepHours[d];
          if (legacy?.value != null) {
            return SleepRow(
              date: d,
              window: w,
              hours: legacy!.value,
              approx: legacy.approx,
            );
          }
          return SleepRow(date: d, window: w);
        }(),
    ],
    daysLogged: days.where((d) => inWeek.any((e) => e.date == d)).length,
    notLogged: {
      'Water': daysWith((e) => e.type == EventType.waterMl),
      'Bkfst protein': daysWith(isProtein),
      'Energy': daysWith((e) => e.type == EventType.energy),
      'Steps': daysWith((e) => e.type == EventType.steps),
      'Weight': daysWith((e) => e.type == EventType.weight),
    },
    studySessions: inWeek
        .where((e) => e.type == EventType.study && e.note == 'session')
        .length,
  );
}
