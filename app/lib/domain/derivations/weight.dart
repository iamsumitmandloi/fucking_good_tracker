import 'package:equatable/equatable.dart';

import '../event.dart';
import '../event_type.dart';

class WeightWeek extends Equatable {
  const WeightWeek({
    required this.days,
    required this.values,
    this.avg,
    this.lo,
    this.hi,
  });

  final List<String> days;

  /// Last weight of each day; null = not weighed (a gap, never 0).
  final List<double?> values;

  /// Mean of the days that have a value.
  final double? avg;

  /// Fixed axis, at least 4 kg wide, centred on the rounded average.
  final double? lo;
  final double? hi;

  bool get isEmpty => avg == null;

  double? get swing {
    final v = values.whereType<double>();
    if (v.length < 2) return null;
    return v.reduce((a, b) => a > b ? a : b) -
        v.reduce((a, b) => a < b ? a : b);
  }

  @override
  List<Object?> get props => [days, values, avg, lo, hi];
}

WeightWeek weightWeek(Iterable<Event> events, List<String> days) {
  final byDay = <String, Event>{};
  final sorted =
      events.where((e) => e.type == EventType.weight && e.qty != null).toList()
        ..sort(compareEvents);
  for (final e in sorted) {
    byDay[e.date] = e; // last one that day wins
  }
  final values = [for (final d in days) byDay[d]?.qty];
  final have = values.whereType<double>().toList();
  if (have.isEmpty) return WeightWeek(days: days, values: values);
  final avg = have.reduce((a, b) => a + b) / have.length;
  final centre = avg.roundToDouble();
  var half = 2.0;
  for (final v in have) {
    final d = (v - centre).abs().ceilToDouble();
    if (d > half) half = d;
  }
  return WeightWeek(
    days: days,
    values: values,
    avg: avg,
    lo: centre - half,
    hi: centre + half,
  );
}
