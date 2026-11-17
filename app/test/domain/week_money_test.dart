import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/derivations/burn.dart';
import 'package:starting_again/domain/derivations/daily_stats.dart';
import 'package:starting_again/domain/derivations/week.dart';
import 'package:starting_again/domain/derivations/weight.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/legacy/legacy_cell.dart';

var _n = 0;
Event ev(
  EventType type,
  String date, {
  String? time,
  double? qty,
  String? unit,
  String? label,
  double? amount,
  String? category,
  String source = 'app',
  String? note,
}) => Event(
  id: 'w${_n++}',
  date: date,
  time: time,
  type: type,
  qty: qty,
  unit: unit,
  label: label,
  amountInr: amount,
  category: category,
  source: source,
  note: note,
);

final days = weekDays('2026-11-17');

void main() {
  test('weekDays: Wed 11 → Tue 17', () {
    expect(days.first, '2026-11-11');
    expect(days.last, '2026-11-17');
    expect(days, hasLength(7));
  });

  group('weight', () {
    test('design week: avg 88.1, axis 86–90, swing 1.6', () {
      final kg = <double>[87.1, 88, 88.5, 88.1, 88.5, 88.7, 87.91];
      final w = weightWeek([
        for (var i = 0; i < 7; i++)
          ev(EventType.weight, days[i], time: '07:00', qty: kg[i]),
      ], days);
      expect(w.avg, closeTo(88.116, 0.001));
      expect(w.lo, 86);
      expect(w.hi, 90);
      expect(w.swing, closeTo(1.6, 1e-9));
    });

    test('last weight of the day wins; missing days are gaps', () {
      final w = weightWeek([
        ev(EventType.weight, days[0], time: '07:00', qty: 90),
        ev(EventType.weight, days[0], time: '21:00', qty: 89),
        ev(EventType.weight, days[3], time: '07:00', qty: 95),
      ], days);
      expect(w.values, [89, null, null, 95, null, null, null]);
      expect(w.avg, 92); // mean of the 2 days with a value, not of 7
      // Centre 92, but 89 and 95 are 3 away: axis widens to 89–95.
      expect(w.lo, 89);
      expect(w.hi, 95);
    });

    test('no weights → empty, no axis', () {
      final w = weightWeek([], days);
      expect(w.isEmpty, isTrue);
      expect(w.values.every((v) => v == null), isTrue);
      expect(w.swing, isNull);
    });
  });

  group('week stats', () {
    test('cig bars: missing days are null, never 0', () {
      final s = weekStats([
        ev(EventType.cigarette, days[0], qty: 13),
        ev(EventType.cigarette, days[6], qty: 4),
      ], days);
      expect(s.cigs, [13, null, null, null, null, null, 4]);
      expect(s.cigTotal, 17);
      expect(s.daysLogged, 2);
    });

    test('sleep rows: bar on the 21:00→11:00 track, late night flagged', () {
      final s = weekStats([
        ev(EventType.sleep, '2026-11-16', time: '22:30'),
        ev(EventType.wake, '2026-11-17', time: '06:00'),
        ev(EventType.sleep, '2026-11-15', time: '04:00'),
        ev(EventType.wake, '2026-11-15', time: '10:06'),
      ], days);
      final tue = s.sleep.last;
      expect(tue.hours, 7.5);
      expect(tue.bar!.$1, closeTo(1.5 / 14, 1e-9));
      expect(tue.bar!.$2, closeTo(9 / 14, 1e-9));
      final sun = s.sleep[4];
      expect(sun.date, '2026-11-15');
      expect(sun.late, isTrue);
      expect(sun.bar!.$1, closeTo(7 / 14, 1e-9));
      expect(s.sleep[0].hours, isNull);
      expect(s.sleepAvg, closeTo((7.5 + 6.1) / 2, 1e-9));
      expect(s.nights7h, 1);
    });

    test('legacy sleep hours fill nights without times (no bar)', () {
      final s = weekStats(
        [],
        days,
        legacySleepHours: {
          '2026-11-12': const LegacyCell(value: 6.125, approx: true),
        },
      );
      expect(s.sleep[1].hours, 6.125);
      expect(s.sleep[1].approx, isTrue);
      expect(s.sleep[1].bar, isNull);
    });

    test('not-logged counts and study sessions', () {
      final s = weekStats([
        ev(EventType.waterMl, days[0], qty: 250),
        ev(EventType.waterMl, days[0], qty: 250),
        ev(EventType.waterMl, days[2], qty: 250),
        ev(EventType.meal, days[1], qty: 30, unit: 'g', label: proteinLabel),
        ev(EventType.study, days[1], qty: 25, note: 'session'),
        ev(EventType.study, days[1], label: 'RS-1', note: 'nailed'),
        ev(EventType.steps, '2026-11-01', qty: 9000), // outside the week
      ], days);
      expect(s.notLogged['Water'], 2);
      expect(s.notLogged['Bkfst protein'], 1);
      expect(s.notLogged['Energy'], 0);
      expect(s.notLogged['Steps'], 0);
      expect(s.studySessions, 1);
    });
  });

  group('burn', () {
    test('excludes bills and one_off; split and pay later', () {
      final b = burn(
        [
          ev(
            EventType.spend,
            days[0],
            amount: 612.5,
            category: 'delivery',
            source: 'lazypay',
          ),
          ev(EventType.spend, days[1], amount: 300, category: 'delivery'),
          ev(
            EventType.cigarette,
            days[1],
            qty: 1,
            amount: 25,
            category: 'tobacco',
          ),
          ev(EventType.meal, days[2], amount: 130, category: 'canteen'),
          ev(
            EventType.spend,
            days[3],
            amount: 1450,
            category: 'bills',
            label: 'Electricity',
          ),
          ev(
            EventType.spend,
            days[4],
            amount: 2435,
            category: 'one_off',
            label: 'Play Console',
          ),
          ev(EventType.spend, days[5], amount: 50), // no category → everyday
          ev(EventType.spend, '2026-11-01', amount: 9999, category: 'other'),
        ],
        from: days.first,
        to: days.last,
      );
      expect(b.days, 7);
      expect(b.dayToDay, 1117.5);
      expect(b.perDay, closeTo(1117.5 / 7, 1e-9));
      expect(b.total, 5002.5);
      expect(b.delivery, 912.5);
      expect(b.deliveryCount, 2);
      expect(b.other, 205);
      expect(b.oneOffs, 3885);
      expect(b.oneOffLabels, ['Electricity', 'Play Console']);
      expect(b.payLater, 612.5);
      expect(b.payLaterCount, 1);
      expect(b.entries, 7);
      expect(b.share(b.oneOffs), closeTo(3885 / 5002.5, 1e-9));
      expect(b.deliveryShareOfDayToDay, closeTo(912.5 / 1117.5, 1e-9));
    });

    test('no money → nulls, never 0', () {
      final b = burn(
        [ev(EventType.tea, days[0])],
        from: days.first,
        to: days.last,
      );
      expect(b.dayToDay, isNull);
      expect(b.perDay, isNull);
      expect(b.total, isNull);
      expect(b.payLater, isNull);
      expect(b.share(null), isNull);
    });
  });
}
