import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../event.dart';
import '../event_type.dart';
import 'parser.dart';

/// The "When" chips in the Quick log sheet.
enum WhenMode { now, fifteenAgo, approx, pick }

/// Turns parsed entries into events.
///
/// - The chip sets the moment: now, now − 15 min, now (marked approx), or a
///   picked `HH:mm`.
/// - A time typed in the text ("tea at 16:30") wins over the chip.
/// - Any explicit time later than [nowIst] means yesterday ("slept 23:30"
///   typed at 07:00).
List<Event> buildEvents(
  List<ParsedEntry> entries, {
  required DateTime nowIst,
  WhenMode mode = WhenMode.now,
  String? pickedTime,
  String Function() idFactory = newEventId,
}) {
  final today = formatDate(nowIst);
  final nowMin = nowIst.hour * 60 + nowIst.minute;

  (String, String) explicit(String hhmm) {
    final m = minutesOf(hhmm)!;
    return (m > nowMin ? addDays(today, -1) : today, hhmmOf(m));
  }

  final (String, String) chip = switch (mode) {
    WhenMode.fifteenAgo => () {
      final t = nowIst.subtract(const Duration(minutes: 15));
      return (formatDate(t), formatTime(t));
    }(),
    WhenMode.pick when minutesOf(pickedTime) != null => explicit(pickedTime!),
    _ => (today, formatTime(nowIst)),
  };

  return [
    for (final e in entries)
      () {
        final (date, time) = e.time != null && minutesOf(e.time) != null
            ? explicit(e.time!)
            : chip;
        return Event(
          id: idFactory(),
          date: date,
          time: time,
          type: e.type,
          qty: e.qty,
          unit: e.unit,
          label: e.label,
          amountInr: e.amount,
          category: e.category,
          approx: e.approx || mode == WhenMode.approx,
          source: e.source,
          note: e.note,
        );
      }(),
  ];
}

/// One "Repeat a usual" chip.
class Usual extends Equatable {
  const Usual({required this.label, required this.template, this.count = 1});

  final String label;

  /// The most recent event with this label.
  final Event template;
  final int count;

  String get chipText {
    final t = template;
    if (t.amountInr != null) return '$label ${rupees(t.amountInr)}';
    if (t.qty != null && t.unit != null && t.unit != 'cup' && t.unit != 'cig') {
      return '$label ${trimNum(t.qty)} ${t.unit}';
    }
    return label;
  }

  ParsedEntry get entry => ParsedEntry.fromEvent(template);

  @override
  List<Object?> get props => [label, template, count];
}

const _notUsual = {EventType.study, EventType.voidEvent, EventType.note};

/// The [max] most frequent labels over the last [days] days (incl. today).
/// Ties go to the most recently used.
List<Usual> usuals(
  Iterable<Event> effective, {
  required String today,
  int days = 14,
  int max = 5,
}) {
  final from = addDays(today, -(days - 1));
  final byKey = <String, List<Event>>{};
  for (final e in effective) {
    final label = e.label?.trim();
    if (label == null || label.isEmpty || _notUsual.contains(e.type)) continue;
    if (e.date.compareTo(from) < 0 || e.date.compareTo(today) > 0) continue;
    (byKey[label.toLowerCase()] ??= []).add(e);
  }
  final list = [
    for (final group in byKey.values)
      () {
        group.sort(compareEvents);
        final last = group.last;
        return Usual(
          label: last.label!.trim(),
          template: last,
          count: group.length,
        );
      }(),
  ];
  list.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : b.template.sortKey.compareTo(a.template.sortKey);
  });
  return list.take(max).toList();
}

/// "1 cigarette", "250 ml water", "Lunch": the middle of "Logged … · 18:02".
String logLine(Event e) {
  final n = trimNum(e.qty ?? 1);
  return switch (e.type) {
    EventType.cigarette => '$n ${e.count == 1 ? 'cigarette' : 'cigarettes'}',
    EventType.tea => '$n tea',
    EventType.coffee => '$n coffee',
    EventType.waterMl => '${trimNum(e.qty ?? 250)} ml water',
    EventType.busBoard => 'bus board',
    EventType.busArrive => 'bus arrival',
    EventType.supplement => e.label ?? 'supplement',
    _ => ParsedEntry.fromEvent(e).title,
  };
}

/// "Logged 1 cigarette · 18:02 · ₹25" for one event,
/// "Logged 2 entries · 18:02 · ₹45" for several.
String loggedText(List<Event> events) {
  if (events.isEmpty) return '';
  final what = events.length == 1
      ? logLine(events.single)
      : '${events.length} entries';
  final paid = events.where((e) => e.amountInr != null);
  final total = paid.isEmpty
      ? null
      : paid.fold<double>(0, (a, e) => a + e.amountInr!);
  return [
    'Logged $what',
    ?events.last.time,
    if (total != null) rupees(total),
  ].join(' · ');
}
