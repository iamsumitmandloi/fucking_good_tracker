import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../event.dart';
import '../event_type.dart';

/// One `sleep` row: `date` + `time` = bedtime, `end_time` = wake,
/// `qty` = hours. A bedtime at or after 12:00 crosses midnight, so the
/// wake date is the next day. The night belongs to its wake date.
class Night extends Equatable {
  const Night({
    required this.bedDate,
    required this.wakeDate,
    this.bedMin,
    this.wakeMin,
    this.hours,
    this.approx = false,
  });

  final String bedDate;
  final String wakeDate;

  /// Minutes after midnight; null when not logged.
  final int? bedMin;
  final int? wakeMin;
  final double? hours;
  final bool approx;

  /// Bedtime on a continuous evening scale: after midnight counts +1440,
  /// so 22:30 (1350) sorts before 00:30 (1470).
  int? get bedScaled =>
      bedMin == null ? null : (bedMin! < 720 ? bedMin! + 1440 : bedMin!);

  /// Asleep minutes, from the clock times when both are known.
  int? get durationMin {
    if (bedMin != null && wakeMin != null) {
      return (wakeMin! - bedMin!) % 1440;
    }
    if (hours != null) return (hours! * 60).round();
    return null;
  }

  /// The part of this night inside calendar day [date], as minutes
  /// `[start, end)` within 0–1440, or null when it doesn't touch the day.
  (int, int)? segmentOn(String date) {
    final dur = durationMin;
    if (bedMin == null || dur == null) return null;
    final start = daysBetween(date, bedDate) * 1440 + bedMin!;
    final end = start + dur;
    final s = math.max(0, start);
    final e = math.min(1440, end);
    return e > s ? (s, e) : null;
  }

  @override
  List<Object?> get props => [bedDate, wakeDate, bedMin, wakeMin, hours];
}

List<Night> nights(Iterable<Event> events) =>
    [
      for (final e in events)
        if (e.type == EventType.sleep) _night(e),
    ]..sort((a, b) {
      final d = a.wakeDate.compareTo(b.wakeDate);
      return d != 0 ? d : (a.bedScaled ?? 0).compareTo(b.bedScaled ?? 0);
    });

Night _night(Event e) {
  final bed = minutesOf(e.time);
  final wake = minutesOf(e.endTime);
  final crosses = bed != null && bed >= 720;
  double? hours = e.qty;
  if (hours == null && bed != null && wake != null) {
    hours = ((wake - bed) % 1440) / 60;
  }
  return Night(
    bedDate: e.date,
    wakeDate: crosses ? addDays(e.date, 1) : e.date,
    bedMin: bed,
    wakeMin: wake,
    hours: hours,
    approx: e.approx,
  );
}

/// Hours slept per wake date (two rows on one wake date add up).
/// Null = no night logged for that day.
List<double?> sleepByWakeDate(List<Night> all, List<String> days) => [
  for (final d in days)
    () {
      final hs = [
        for (final n in all)
          if (n.wakeDate == d && n.hours != null) n.hours!,
      ];
      return hs.isEmpty ? null : hs.reduce((a, b) => a + b);
    }(),
];

/// The nights whose wake date is in [days].
List<Night> nightsIn(List<Night> all, List<String> days) => [
  for (final n in all)
    if (days.contains(n.wakeDate)) n,
];

class BedtimeStats extends Equatable {
  const BedtimeStats({
    required this.meanScaled,
    required this.sdMin,
    required this.earliest,
    required this.latest,
    required this.count,
  });

  /// Mean bedtime on the evening scale (see [Night.bedScaled]).
  final double meanScaled;

  /// Population standard deviation, minutes.
  final double sdMin;
  final Night earliest;
  final Night latest;
  final int count;

  /// Mean bedtime as minutes after midnight (0–1439).
  int get meanMin => meanScaled.round() % 1440;

  @override
  List<Object?> get props => [meanScaled, sdMin, earliest, latest, count];
}

BedtimeStats? bedtimeStats(Iterable<Night> ns) {
  final timed = [
    for (final n in ns)
      if (n.bedScaled != null) n,
  ];
  if (timed.isEmpty) return null;
  final xs = [for (final n in timed) n.bedScaled!.toDouble()];
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  final variance =
      xs.fold<double>(0, (a, x) => a + (x - mean) * (x - mean)) / xs.length;
  timed.sort((a, b) => a.bedScaled!.compareTo(b.bedScaled!));
  return BedtimeStats(
    meanScaled: mean,
    sdMin: math.sqrt(variance),
    earliest: timed.first,
    latest: timed.last,
    count: timed.length,
  );
}
