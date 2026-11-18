import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../event.dart';
import '../event_type.dart';
import 'metrics.dart';
import 'nights.dart';
import 'viewer_events.dart';

/// Ribbon lanes, in drawing order.
enum Lane { sleep, bus, smoke, food, money }

/// One tappable mark on the Day ribbon. Minutes are after midnight.
class RibbonMark extends Equatable {
  const RibbonMark({
    required this.lane,
    required this.start,
    this.end,
    this.size = 1,
    this.big = false,
    required this.detail,
    required this.semantics,
  });

  final Lane lane;
  final int start;

  /// Bars (sleep, bus) have an end; points don't.
  final int? end;

  /// Smoke: cigarettes at this minute. Money: rupees.
  final double size;

  /// Food: a meal (bigger dot) rather than a snack or a drink.
  final bool big;

  /// The line shown under the ribbon when this mark is tapped.
  final String detail;
  final String semantics;

  @override
  List<Object?> get props => [lane, start, end, size, big, detail];
}

enum EntryKind { smoke, food, money, bus, sleep, other }

class DayEntry extends Equatable {
  const DayEntry(this.minute, this.kind, this.text, {this.amount});
  final int minute;
  final EntryKind kind;
  final String text;
  final double? amount;
  @override
  List<Object?> get props => [minute, kind, text, amount];
}

/// One KPI tile: value plus a comparison with the 7-day average.
class Kpi extends Equatable {
  const Kpi(this.label, this.value, this.delta);
  final String label;
  final String value;
  final String delta;
  @override
  List<Object?> get props => [label, value, delta];
}

class DayView extends Equatable {
  const DayView({
    required this.date,
    required this.cigs,
    required this.cigsTimed,
    required this.sleep,
    required this.dayToDay,
    required this.oneOff,
    required this.commute,
    required this.kpis,
    required this.marks,
    required this.untimed,
    required this.untimedSpendCount,
    required this.untimedSpend,
    required this.entries,
    required this.isEmpty,
  });

  final String date;
  final double? cigs;
  final double? cigsTimed;
  final double? sleep;
  final double? dayToDay;
  final double? oneOff;
  final int? commute;

  /// Cigarettes · Slept · Day-to-day spend · Commute.
  final List<Kpi> kpis;
  final List<RibbonMark> marks;

  /// Chips for things logged without a time (cigarettes and payments are
  /// summarised separately).
  final List<String> untimed;
  final int untimedSpendCount;
  final double untimedSpend;

  /// Timed entries, oldest first.
  final List<DayEntry> entries;

  /// Nothing at all was logged this day.
  final bool isEmpty;

  double get untimedCigs => (cigs ?? 0) - (cigsTimed ?? 0);

  @override
  List<Object?> get props => [date, kpis, marks, untimed, entries, isEmpty];
}

String _cigWord(num n) => n == 1 ? 'cigarette' : 'cigarettes';

String _arrow(double diff) => diff <= 0 ? '▼' : '▲';

/// [events] must already be [viewerEvents]. Averages are over the 7 days
/// ending on [date], counting only days that have data.
DayView dayView(List<Event> events, String date) {
  final w = weekMetrics(events, daysEnding(date));
  final i = w.days.length - 1;
  final day = byDate(events)[date] ?? const <Event>[];

  final cigs = w.cigs[i];
  final timed = w.cigsTimed[i];
  final sleep = w.sleep[i];
  final spend = w.dayToDay[i];
  final commute = w.commute[i];
  final oneOff = () {
    final o = w.oneOffs.where((x) => x.date == date);
    return o.isEmpty ? null : o.fold<double>(0, (a, x) => a + x.amount);
  }();

  final kpis = <Kpi>[
    () {
      final avg = w.cigAvg;
      if (cigs == null) return const Kpi('Cigarettes', dash, 'not logged');
      return Kpi(
        'Cigarettes',
        trimNum(cigs),
        avg == null
            ? ''
            : '${_arrow(cigs - avg)} ${(cigs - avg).abs().toStringAsFixed(1)} vs 7-day avg ${trimNum(avg)}',
      );
    }(),
    () {
      final avg = w.sleepAvg;
      if (sleep == null) {
        return const Kpi('Slept (night before)', dash, 'not logged');
      }
      final approx = w.sleepApprox[i] ? '~' : '';
      return Kpi(
        'Slept (night before)',
        '$approx${trimNum(sleep)} h',
        avg == null
            ? ''
            : '${_arrow(sleep - avg)} ${(sleep - avg).abs().toStringAsFixed(1)} h vs avg ${trimNum(avg)}',
      );
    }(),
    () {
      final avg = w.burnAvg;
      final extra = oneOff == null ? '' : ' · +${rupees(oneOff)} one-off';
      if (spend == null) {
        return Kpi('Day-to-day spend', dash, 'not logged$extra');
      }
      final cmp = avg == null
          ? ''
          : (spend <= avg
                ? '${rupees(avg - spend)} under avg ${rupees(avg)}'
                : '${rupees(spend - avg)} over avg ${rupees(avg)}');
      return Kpi('Day-to-day spend', rupees(spend), '$cmp$extra');
    }(),
    () {
      final avg = w.commuteAvg;
      if (commute == null) {
        return const Kpi('Commute', 'Off day', 'no bus legs');
      }
      final diff = avg == null ? 0.0 : commute - avg;
      return Kpi(
        'Commute',
        duration(commute),
        avg == null
            ? ''
            : '${_arrow(diff)} ${diff.abs().round()} min vs office avg',
      );
    }(),
  ];

  final marks = <RibbonMark>[];
  final entries = <DayEntry>[];

  // Sleep: every night touching this calendar day, clipped to it.
  for (final n in nights(events)) {
    final seg = n.segmentOn(date);
    if (seg == null) continue;
    final text =
        'Asleep ${hhmmOf(n.bedMin!)} → ${n.wakeMin == null ? '?' : hhmmOf(n.wakeMin!)}'
        '${n.hours == null ? '' : ' · ${n.approx ? '~' : ''}${trimNum(n.hours)} h'}';
    marks.add(
      RibbonMark(
        lane: Lane.sleep,
        start: seg.$1,
        end: seg.$2,
        detail: text,
        semantics: text,
      ),
    );
  }

  for (final l in w.legs[i]) {
    final text =
        'Bus ${hhmmOf(l.board)} → ${hhmmOf(l.arrive)} · ${l.minutes} min';
    marks.add(
      RibbonMark(
        lane: Lane.bus,
        start: l.board,
        end: l.board + l.minutes,
        detail: text,
        semantics: text,
      ),
    );
    entries.add(
      DayEntry(
        l.board,
        EntryKind.bus,
        'Bus → ${hhmmOf(l.arrive)} (${l.minutes} min)',
      ),
    );
  }

  // Smoke: grouped by minute.
  final smoke = <int, double>{};
  for (final e in day) {
    if (e.type == EventType.cigarette && e.timed) {
      smoke[e.minute!] = (smoke[e.minute!] ?? 0) + e.count;
    }
  }
  for (final MapEntry(key: m, value: n) in smoke.entries) {
    final text = '${hhmmOf(m)} · ${trimNum(n)} ${_cigWord(n)}';
    marks.add(
      RibbonMark(
        lane: Lane.smoke,
        start: m,
        size: n,
        detail: text,
        semantics: '${trimNum(n)} ${_cigWord(n)} at ${hhmmOf(m)}',
      ),
    );
    entries.add(DayEntry(m, EntryKind.smoke, '${trimNum(n)} ${_cigWord(n)}'));
  }

  final untimed = <String>[];
  var untimedSpendCount = 0;
  var untimedSpend = 0.0;

  for (final e in day) {
    final m = e.minute;
    final name = _name(e);
    if (e.isFood) {
      if (m == null) {
        untimed.add(name);
        continue;
      }
      marks.add(
        RibbonMark(
          lane: Lane.food,
          start: m,
          big: e.type == EventType.meal,
          detail: '${hhmmOf(m)} · $name',
          semantics: '$name at ${hhmmOf(m)}',
        ),
      );
      entries.add(DayEntry(m, EntryKind.food, name));
    } else if (e.isSpend) {
      if (m == null) {
        untimedSpendCount++;
        untimedSpend += e.amountInr!;
        continue;
      }
      final text = e.label ?? SpendCat.name(e.category);
      marks.add(
        RibbonMark(
          lane: Lane.money,
          start: m,
          size: e.amountInr!,
          detail: '${hhmmOf(m)} · ${rupees(e.amountInr)} · $text',
          semantics: '${rupees(e.amountInr)} at ${hhmmOf(m)}',
        ),
      );
      entries.add(DayEntry(m, EntryKind.money, text, amount: e.amountInr));
    } else if (e.type == EventType.cigarette ||
        e.type == EventType.sleep ||
        e.isBus ||
        e.type == EventType.spend) {
      continue; // handled above (or a spend row without an amount)
    } else if (m == null) {
      if (e.type != EventType.note) untimed.add(name);
    } else {
      entries.add(DayEntry(m, EntryKind.other, name));
    }
  }

  entries.sort((a, b) {
    final c = a.minute.compareTo(b.minute);
    return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
  });

  return DayView(
    date: date,
    cigs: cigs,
    cigsTimed: timed,
    sleep: sleep,
    dayToDay: spend,
    oneOff: oneOff,
    commute: commute,
    kpis: kpis,
    marks: marks,
    untimed: untimed,
    untimedSpendCount: untimedSpendCount,
    untimedSpend: untimedSpend,
    entries: entries,
    isEmpty: day.isEmpty && sleep == null,
  );
}

/// Short human text for a row.
String _name(Event e) {
  final l = e.label?.trim();
  switch (e.type) {
    case EventType.weight:
      return '${trimNum(e.qty, digits: 2)} kg';
    case EventType.steps:
      return e.qty == null ? 'Steps' : '${rupees(e.qty).substring(1)} steps';
    case EventType.waterMl:
      return e.qty == null ? 'Water' : '${trimNum(e.qty)} ml water';
    case EventType.energy:
      return e.qty == null
          ? (l ?? e.note ?? 'Energy')
          : 'Energy ${trimNum(e.qty)}${e.unit == '/10' ? '/10' : ''}';
    case EventType.study:
      return e.qty == null ? 'Study' : 'Study ${trimNum(e.qty)} min';
    case EventType.tea:
      return (l == null || l.isEmpty) ? 'Tea' : l;
    case EventType.coffee:
      return (l == null || l.isEmpty) ? 'Coffee' : l;
    case EventType.note:
      return (l == null || l.isEmpty) ? (e.note ?? 'Note') : l;
    default:
      if (l != null && l.isNotEmpty) return l;
      final t = e.type.wire.replaceAll('_', ' ');
      return '${t[0].toUpperCase()}${t.substring(1)}';
  }
}

/// "Tue 17 Nov".
String dayLabel(String date) => dayHeader(parseDate(date)!);
