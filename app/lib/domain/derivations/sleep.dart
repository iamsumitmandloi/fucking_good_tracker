import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../event.dart';
import '../event_type.dart';

class SleepWindow extends Equatable {
  const SleepWindow({
    required this.bedDate,
    required this.bed,
    required this.wakeDate,
    this.wake,
    this.approx = false,
  });

  final String bedDate;

  /// `HH:mm`.
  final String bed;

  /// Row label in the Week card: the morning this sleep ended.
  final String wakeDate;
  final String? wake;
  final bool approx;

  int? get minutes {
    final b = _abs(bedDate, bed);
    final w = wake == null ? null : _abs(wakeDate, wake!);
    if (b == null || w == null) return null;
    return w - b;
  }

  double? get hours => minutes == null ? null : minutes! / 60;

  /// Bedtime at or after 02:00 (and before noon) is a late night.
  bool get late {
    final m = minutesOf(bed);
    return m != null && m >= 2 * 60 && m < 12 * 60;
  }

  @override
  List<Object?> get props => [bedDate, bed, wakeDate, wake, approx];
}

int? _abs(String date, String time) {
  final d = parseDate(date);
  final m = minutesOf(time);
  if (d == null || m == null) return null;
  return d.millisecondsSinceEpoch ~/ 60000 + m;
}

/// Each `sleep` (time = bedtime) pairs with the first `wake` after it,
/// within 18 h. A sleep with no wake yet is returned with `wake == null`.
List<SleepWindow> sleepWindows(Iterable<Event> effective) {
  final timed =
      effective
          .where(
            (e) =>
                (e.type == EventType.sleep || e.type == EventType.wake) &&
                _abs(e.date, e.time ?? '') != null,
          )
          .toList()
        ..sort((a, b) => _abs(a.date, a.time!)!.compareTo(_abs(b.date, b.time!)!));
  final out = <SleepWindow>[];
  for (var i = 0; i < timed.length; i++) {
    final s = timed[i];
    if (s.type != EventType.sleep) continue;
    final start = _abs(s.date, s.time!)!;
    // Only the very next timed event can close this window: a second
    // bedtime first means this one never got a wake.
    Event? wake;
    if (i + 1 < timed.length) {
      final w = timed[i + 1];
      if (w.type == EventType.wake &&
          _abs(w.date, w.time!)! - start <= 18 * 60) {
        wake = w;
      }
    }
    final bedMin = minutesOf(s.time)!;
    out.add(
      SleepWindow(
        bedDate: s.date,
        bed: s.time!,
        wakeDate: wake?.date ?? (bedMin >= 12 * 60 ? addDays(s.date, 1) : s.date),
        wake: wake?.time,
        approx: s.approx || (wake?.approx ?? false),
      ),
    );
  }
  return out;
}

/// The night that ended on [date] (the window labelled with that day).
SleepWindow? nightEndingOn(List<SleepWindow> windows, String date) {
  for (final w in windows.reversed) {
    if (w.wakeDate == date) return w;
  }
  return null;
}
