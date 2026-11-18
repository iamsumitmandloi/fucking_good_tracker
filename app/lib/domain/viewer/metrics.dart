import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../derivations/daily_stats.dart' show isProtein;
import '../derivations/weight.dart';
import '../event.dart';
import '../event_type.dart';
import 'nights.dart';
import 'viewer_events.dart';

/// `n` days ending on [last], oldest first.
List<String> daysEnding(String last, {int n = 7}) => [
  for (var i = n - 1; i >= 0; i--) addDays(last, -i),
];

/// One bus leg: board → arrive, minutes after midnight.
class Leg extends Equatable {
  const Leg(this.board, this.arrive);
  final int board;
  final int arrive;
  int get minutes => (arrive - board) % 1440;
  @override
  List<Object?> get props => [board, arrive];
}

/// `bus_board`/`bus_arrive` paired in time order. An arrive with no board
/// before it, or a board never followed by an arrive, makes no leg.
List<Leg> legsOn(Iterable<Event> dayEvents) {
  final bus = [
    for (final e in dayEvents)
      if (e.isBus && e.timed) e,
  ]..sort((a, b) => a.minute!.compareTo(b.minute!));
  final legs = <Leg>[];
  int? board;
  for (final e in bus) {
    if (e.type == EventType.busBoard) {
      board = e.minute;
    } else if (board != null) {
      legs.add(Leg(board, e.minute!));
      board = null;
    }
  }
  return legs;
}

class OneOff extends Equatable {
  const OneOff(this.date, this.amount, this.text, this.category);
  final String date;
  final double amount;
  final String text;
  final String? category;
  @override
  List<Object?> get props => [date, amount, text, category];
}

class CategoryTotal extends Equatable {
  const CategoryTotal(this.category, this.amount, this.orders, this.weekend);
  final String category;
  final double amount;

  /// Distinct (date, time) groups; untimed rows of one day count as one.
  final int orders;

  /// Part of [amount] spent on Saturday or Sunday.
  final double weekend;
  String get name => SpendCat.name(category);
  @override
  List<Object?> get props => [category, amount, orders, weekend];
}

class GroupAvg extends Equatable {
  const GroupAvg(this.avg, this.days);
  final double? avg;
  final int days;
  @override
  List<Object?> get props => [avg, days];
}

enum Coverage { logged, partial, missing }

class CoverageRow extends Equatable {
  const CoverageRow(this.name, this.cells, this.note);
  final String name;
  final List<Coverage> cells;
  final String note;
  @override
  List<Object?> get props => [name, cells, note];
}

/// Everything the Week, Trends, Money and Insights tabs show for a run of
/// days. Every per-day list is aligned with [days]; null = not logged.
class WeekMetrics extends Equatable {
  const WeekMetrics({
    required this.days,
    required this.cigs,
    required this.cigsTimed,
    required this.sleep,
    required this.sleepApprox,
    required this.nights,
    required this.bedtime,
    required this.commute,
    required this.legs,
    required this.dayToDay,
    required this.oneOffs,
    required this.categories,
    required this.payLater,
    required this.payLaterCount,
    required this.payLaterMerchants,
    required this.tobaccoSpend,
    required this.steps,
    required this.weight,
    required this.hours,
    required this.smokeMinutes,
    required this.paired,
    required this.office,
    required this.off,
    required this.coverage,
  });

  final List<String> days;
  final List<double?> cigs;
  final List<double?> cigsTimed;
  final List<double?> sleep;
  final List<bool> sleepApprox;

  /// Nights whose wake date is in [days], oldest first.
  final List<Night> nights;
  final BedtimeStats? bedtime;

  /// Total bus minutes per day; null = no legs (an off day).
  final List<int?> commute;
  final List<List<Leg>> legs;

  /// Day-to-day spend per day; null = no spend rows that day.
  final List<double?> dayToDay;
  final List<OneOff> oneOffs;

  /// Day-to-day only, largest first.
  final List<CategoryTotal> categories;
  final double? payLater;
  final int payLaterCount;
  final List<String> payLaterMerchants;
  final double? tobaccoSpend;
  final List<double?> steps;
  final WeightWeek weight;

  /// Timed cigarettes per hour of day (0–23).
  final Map<int, double> hours;

  /// Minute of day of every timed cigarette row.
  final List<int> smokeMinutes;

  /// Timed cigarettes logged at the same date + time as a tea.
  final double paired;
  final GroupAvg office;
  final GroupAvg off;
  final List<CoverageRow> coverage;

  double? get cigTotal => _sum(cigs);
  double get timedTotal => _sum(cigsTimed) ?? 0;
  double? get cigAvg => meanOf(cigs);
  double? get sleepAvg => meanOf(sleep);
  int get longNights => sleep.whereType<double>().where((h) => h >= 7).length;
  int get sleepDays => sleep.whereType<double>().length;
  double? get commuteAvg => meanOf(commute);
  double? get dayToDayTotal => _sum(dayToDay);
  double? get burnAvg => meanOf(dayToDay);
  double? get oneOffTotal =>
      oneOffs.isEmpty ? null : oneOffs.fold<double>(0, (a, o) => a + o.amount);
  double? get stepsAvg => meanOf(steps);
  int get daysLogged => [
    for (var i = 0; i < days.length; i++)
      if (cigs[i] != null ||
          sleep[i] != null ||
          dayToDay[i] != null ||
          weight.values[i] != null ||
          steps[i] != null ||
          commute[i] != null)
        i,
  ].length;

  static double? _sum(List<double?> xs) {
    final have = xs.whereType<double>();
    return have.isEmpty ? null : have.reduce((a, b) => a + b);
  }

  @override
  List<Object?> get props => [
    days,
    cigs,
    cigsTimed,
    sleep,
    nights,
    commute,
    dayToDay,
    oneOffs,
    categories,
    payLater,
    steps,
    weight,
    hours,
    paired,
    office,
    off,
    coverage,
  ];
}

bool _isWeekend(String date) {
  final wd = parseDate(date)!.weekday;
  return wd == DateTime.saturday || wd == DateTime.sunday;
}

/// [events] must already be [viewerEvents].
WeekMetrics weekMetrics(List<Event> events, List<String> days) {
  final idx = byDate(events);
  List<Event> on(String d) => idx[d] ?? const [];
  Iterable<Event> ofType(String d, EventType t) =>
      on(d).where((e) => e.type == t);

  final cigs = <double?>[];
  final timed = <double?>[];
  final commute = <int?>[];
  final legs = <List<Leg>>[];
  final dayToDay = <double?>[];
  final steps = <double?>[];
  final oneOffs = <OneOff>[];
  final hours = <int, double>{};
  final smokeMinutes = <int>[];
  var paired = 0.0;
  final cats = <String, double>{};
  final catOrders = <String, Set<String>>{};
  final catWeekend = <String, double>{};
  double? payLater;
  var payLaterCount = 0;
  final merchants = <String>[];
  double? tobacco;

  for (final d in days) {
    final c = ofType(d, EventType.cigarette).toList();
    cigs.add(sumOrNull(c, (e) => e.count));
    final ct = c.where((e) => e.timed).toList();
    timed.add(c.isEmpty ? null : ct.fold<double>(0, (a, e) => a + e.count));
    final teaTimes = {
      for (final e in ofType(d, EventType.tea))
        if (e.timed) e.minute,
    };
    for (final e in ct) {
      final h = e.minute! ~/ 60;
      hours[h] = (hours[h] ?? 0) + e.count;
      smokeMinutes.add(e.minute!);
      if (teaTimes.contains(e.minute)) paired += e.count;
    }

    final l = legsOn(on(d));
    legs.add(l);
    commute.add(l.isEmpty ? null : l.fold<int>(0, (a, x) => a + x.minutes));

    final spend = on(d).where((e) => e.isSpend).toList();
    dayToDay.add(
      spend.isEmpty
          ? null
          : spend
                .where((e) => e.isDayToDay)
                .fold<double>(0, (a, e) => a + e.amountInr!),
    );
    for (final e in spend) {
      if (!e.isDayToDay) {
        oneOffs.add(OneOff(d, e.amountInr!, e.itemText, e.category));
      } else {
        final k = e.category ?? SpendCat.other;
        cats[k] = (cats[k] ?? 0) + e.amountInr!;
        (catOrders[k] ??= {}).add('$d|${e.time ?? ''}');
        if (_isWeekend(d)) catWeekend[k] = (catWeekend[k] ?? 0) + e.amountInr!;
        if (k == SpendCat.tobacco) tobacco = (tobacco ?? 0) + e.amountInr!;
      }
      if (e.source == 'lazypay') {
        payLater = (payLater ?? 0) + e.amountInr!;
        payLaterCount++;
        final m = e.merchant;
        if (m != null && !merchants.contains(m)) merchants.add(m);
      }
    }

    steps.add(
      sumOrNull(
        ofType(d, EventType.steps).where((e) => e.qty != null),
        (e) => e.qty!,
      ),
    );
  }

  final allNights = nights(events);
  final weekNights = nightsIn(allNights, days);
  final sleep = sleepByWakeDate(allNights, days);
  final sleepApprox = [
    for (final d in days) weekNights.any((n) => n.wakeDate == d && n.approx),
  ];

  // Office day = at least one bus leg. Averages over days with cigarettes.
  final officeCigs = <double>[];
  final offCigs = <double>[];
  for (var i = 0; i < days.length; i++) {
    final c = cigs[i];
    if (c == null) continue;
    (legs[i].isNotEmpty ? officeCigs : offCigs).add(c);
  }

  final categories = [
    for (final k in cats.keys)
      CategoryTotal(k, cats[k]!, catOrders[k]!.length, catWeekend[k] ?? 0),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  final weight = weightWeek(events, days);

  return WeekMetrics(
    days: days,
    cigs: cigs,
    cigsTimed: timed,
    sleep: sleep,
    sleepApprox: sleepApprox,
    nights: weekNights,
    bedtime: bedtimeStats(weekNights),
    commute: commute,
    legs: legs,
    dayToDay: dayToDay,
    oneOffs: oneOffs,
    categories: categories,
    payLater: payLater,
    payLaterCount: payLaterCount,
    payLaterMerchants: merchants,
    tobaccoSpend: tobacco,
    steps: steps,
    weight: weight,
    hours: hours,
    smokeMinutes: smokeMinutes,
    paired: paired,
    office: GroupAvg(meanOf(officeCigs), officeCigs.length),
    off: GroupAvg(meanOf(offCigs), offCigs.length),
    coverage: _coverage(
      days,
      on,
      cigs: cigs,
      timed: timed,
      sleep: sleep,
      weight: weight.values,
      dayToDay: dayToDay,
      steps: steps,
    ),
  );
}

List<CoverageRow> _coverage(
  List<String> days,
  List<Event> Function(String) on, {
  required List<double?> cigs,
  required List<double?> timed,
  required List<double?> sleep,
  required List<double?> weight,
  required List<double?> dayToDay,
  required List<double?> steps,
}) {
  CoverageRow simple(String name, List<bool> have) {
    final n = have.where((h) => h).length;
    return CoverageRow(name, [
      for (final h in have) h ? Coverage.logged : Coverage.missing,
    ], '$n/${days.length}');
  }

  List<bool> present(List<Object?> xs) => [for (final x in xs) x != null];
  List<bool> anyOf(bool Function(Event) f) => [
    for (final d in days) on(d).any(f),
  ];

  final cigCells = [
    for (var i = 0; i < days.length; i++)
      cigs[i] == null
          ? Coverage.missing
          : (timed[i] == cigs[i] ? Coverage.logged : Coverage.partial),
  ];
  final cigTotal = cigs.whereType<double>().fold<double>(0, (a, b) => a + b);
  final timedTotal = timed.whereType<double>().fold<double>(0, (a, b) => a + b);
  String n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  return [
    simple('Sleep', present(sleep)),
    simple('Weight', present(weight)),
    simple('Spending', present(dayToDay)),
    CoverageRow(
      'Cigarettes',
      cigCells,
      cigTotal == 0
          ? '0/${days.length}'
          : '${n(timedTotal)}/${n(cigTotal)} timed',
    ),
    simple('Steps', present(steps)),
    simple('Water', anyOf((e) => e.type == EventType.waterMl)),
    simple('Bkfst protein', anyOf(isProtein)),
    simple('Study', anyOf((e) => e.type == EventType.study)),
  ];
}
