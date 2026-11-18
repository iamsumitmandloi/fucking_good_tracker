import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/core/clock.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/viewer/day_view.dart';
import 'package:starting_again/domain/viewer/insights.dart';
import 'package:starting_again/domain/viewer/metrics.dart';
import 'package:starting_again/domain/viewer/nights.dart';
import 'package:starting_again/domain/viewer/viewer_events.dart';

/// The live Events tab exported by `dart run tool/export_events.dart`
/// (gitignored: personal data).
final _fixture = File('fixtures/events_backfill.json');

List<Event> _load() => viewerEvents([
  for (final r in (jsonDecode(_fixture.readAsStringSync()) as List))
    ?Event.fromSheetRow(r as Map<String, dynamic>),
]);

Event ev(
  String id,
  String date,
  EventType type, {
  String? time,
  String? end,
  double? qty,
  double? amount,
  String? category,
  String? label,
  String source = 'chat',
  bool approx = false,
}) => Event(
  id: id,
  date: date,
  type: type,
  time: time,
  endTime: end,
  qty: qty,
  amountInr: amount,
  category: category,
  label: label,
  source: source,
  approx: approx,
);

void main() {
  final week = daysEnding('2026-11-17');

  group('11–17 Nov from the live backfill (brief §7.2 table)', () {
    final skip = _fixture.existsSync()
        ? false
        : 'fixtures/events_backfill.json missing: run `dart run tool/export_events.dart`';
    late List<Event> events;
    late WeekMetrics m;
    setUpAll(() {
      if (skip != false) return;
      events = _load();
      m = weekMetrics(events, week);
    });

    test('cigarettes per day, total, average, timed', () {
      expect(m.cigs, [13, 5, 11, 6, 5, 4, 6]);
      expect(m.cigTotal, 50);
      expect(m.cigAvg, closeTo(7.14, 0.005));
      expect(m.timedTotal, 17);
    }, skip: skip);

    test('tea pairing 8 of 17 timed', () {
      expect(m.paired, 8);
    }, skip: skip);

    test('office vs off days: 7.8 vs 5.5', () {
      expect(m.office.avg, closeTo(7.8, 1e-9));
      expect(m.office.days, 5);
      expect(m.off.avg, closeTo(5.5, 1e-9));
      expect(m.off.days, 2);
    }, skip: skip);

    test('sleep by wake date, bedtime mean and spread', () {
      expect(m.sleep, [6, 7.6, 6, 6, 6.1, 6, 7.5]);
      expect(m.sleepAvg, closeTo(6.46, 0.005));
      expect(m.longNights, 2);
      final b = m.bedtime!;
      expect(hhmmOf(b.meanMin), '00:43');
      expect(b.sdMin.round(), 99);
      expect(hhmmOf(b.earliest.bedMin!), '22:30');
      expect(hhmmOf(b.latest.bedMin!), '04:00');
    }, skip: skip);

    test('commute minutes and office-day average', () {
      expect(m.commute, [150, 145, 140, null, null, 175, 170]);
      expect(m.commuteAvg, 156);
    }, skip: skip);

    test('day-to-day spend, one-offs, categories, pay later', () {
      expect(
        [for (final v in m.dayToDay) double.parse(v!.toStringAsFixed(2))],
        [1654, 225, 1010, 1467.14, 1583, 515, 404],
      );
      expect(m.dayToDayTotal, closeTo(6858.14, 0.001));
      expect(m.burnAvg!.round(), 980);
      expect(
        [for (final o in m.oneOffs) (o.date, o.amount, o.category)],
        [('2026-11-12', 2347.51, 'one_off'), ('2026-11-15', 1537.14, 'bills')],
      );
      expect(
        {
          for (final c in m.categories)
            c.category: double.parse(c.amount.toStringAsFixed(2)),
        },
        {
          'quick_commerce': 4134,
          'food_out': 1553.14,
          'tobacco': 716,
          'transport': 195,
          'groceries': 100,
          'tea': 80,
          'personal_care': 80,
        },
      );
      expect(m.categories.first.category, 'quick_commerce');
      expect(m.categories.first.orders, 6);
      expect(m.categories.first.weekend, 2442);
      expect(m.payLater, closeTo(1821.14, 0.001));
      expect(m.payLaterCount, 3);
      expect(m.payLaterMerchants, ['Zepto', 'Blink', 'Zomato']);
    }, skip: skip);

    test('weight and steps', () {
      expect(m.weight.avg, closeTo(88.12, 0.005));
      expect((m.weight.lo, m.weight.hi), (86, 90));
      expect(m.steps.whereType<double>().length, 6);
      expect(m.steps[3], isNull); // Sat
      expect(m.stepsAvg!.round(), 9779);
    }, skip: skip);

    test('hour histogram and peaks', () {
      expect(m.hours, {10: 1, 11: 2, 14: 4, 16: 4, 18: 2, 19: 1, 20: 1, 22: 2});
      expect(peakHours(m.hours), [14, 16]);
      expect(
        peakSentence(m),
        const Takeaway(
          'Peaks at 14:00 and 16:00',
          ', after lunch and at evening tea.',
        ),
      );
    }, skip: skip);

    test('coverage grid', () {
      String row(String name) {
        final r = m.coverage.firstWhere((r) => r.name == name);
        return '${r.cells.map((c) => c.name[0]).join()} ${r.note}';
      }

      expect(row('Sleep'), 'lllllll 7/7');
      expect(row('Weight'), 'lllllll 7/7');
      expect(row('Spending'), 'lllllll 7/7');
      expect(row('Cigarettes'), 'plppppl 17/50 timed');
      expect(row('Steps'), 'lllmlll 6/7');
      expect(row('Water'), 'mmmmmmm 0/7');
      expect(row('Bkfst protein'), 'mmmmmmm 0/7');
      expect(row('Study'), 'mmmmmmm 0/7');
    }, skip: skip);

    test('insight cards and week takeaways', () {
      final cards = insightCards(m);
      expect(cards.map((c) => (c.title, c.confidence)), [
        ('Tea and cigarettes go together', 3),
        ('More cigarettes on office days', 1),
        ('Fewer after a 7h+ night', 1),
        ('Sunday 15 stands out', 1),
      ]);
      expect(
        cards[1].body,
        '7.8 a day across 5 office days vs 5.5 across 2 off days. Too few days to trust yet.',
      );
      expect(
        cards[2].body,
        '5.5 the next day after 2 longer nights vs 7.8 after 5 shorter ones. '
        'Both long nights were before office days, so it overlaps the card above.',
      );
      expect(
        cards[3].body,
        'Asleep 04:00 to 10:07, 2,096 steps, ₹1,583 spent. One day, so it is a note, not a pattern.',
      );
      expect(weekTakeaways(m), const [
        Takeaway(
          'Smoking clusters after lunch and at evening tea.',
          'On the days with times, 8 of 17 cigarettes sit at 14:00–16:30.',
        ),
        Takeaway(
          'Only 17 of 50 cigarettes have a time.',
          'Wed and Sun have none, so their rows look empty. Ask the logging agent for a time on every entry.',
        ),
      ]);
      expect(
        sleepSentence(m),
        const Takeaway(
          'Bedtime ranged 22:30 → 04:00.',
          ' Usual is about 00:45. Saturday night was the outlier.',
        ),
      );
    }, skip: skip);

    test('Day view for Tue 17 Nov', () {
      final d = dayView(events, '2026-11-17');
      expect(
        [for (final k in d.kpis) '${k.value} | ${k.delta}'],
        [
          '6 | ▼ 1.1 vs 7-day avg 7.1',
          '~7.5 h | ▲ 1.0 h vs avg 6.5',
          '₹404 | ₹576 under avg ₹980',
          '2h 50m | ▲ 14 min vs office avg',
        ],
      );
      expect(d.untimedCigs, 0);
      final sleep = d.marks.where((x) => x.lane == Lane.sleep).toList();
      expect([for (final s in sleep) (s.start, s.end)], [(0, 360)]);
      expect(sleep.single.detail, 'Asleep 22:30 → 06:00 · ~7.5 h');
      final smoke = d.marks.where((x) => x.lane == Lane.smoke).toList();
      expect(
        [for (final s in smoke) (hhmmOf(s.start), s.size)],
        [('11:00', 1), ('14:00', 2), ('16:30', 1), ('19:30', 1), ('22:00', 1)],
      );
      expect(smoke[1].detail, '14:00 · 2 cigarettes');
      final bus = d.marks.where((x) => x.lane == Lane.bus).toList();
      expect(bus.first.detail, 'Bus 09:20 → 10:40 · 80 min');
      // Notes appear in the list only (06:00 health note), then the bus.
      expect(d.entries.first.kind, EntryKind.other);
      expect(d.entries.first.minute, 360);
      expect(d.entries[1].kind, EntryKind.bus);
    }, skip: skip);

    test('Day view for Mon 16: two sleep segments, one-off free', () {
      final d = dayView(events, '2026-11-16');
      final sleep = d.marks.where((x) => x.lane == Lane.sleep);
      expect(
        [for (final s in sleep) (s.start, s.end)],
        [(120, 480), (1350, 1440)],
      );
      expect(d.kpis[0].value, '4');
      expect(d.untimedCigs, 1);
    }, skip: skip);

    test('Day view for Wed 11: untimed cigarettes and payments', () {
      final d = dayView(events, '2026-11-11');
      expect(d.untimedCigs, 13);
      expect(d.marks.where((x) => x.lane == Lane.smoke), isEmpty);
      expect(d.untimedSpendCount, greaterThan(0));
      expect(d.untimed, contains('87.1 kg'));
    }, skip: skip);
  });

  group('rules on small synthetic data', () {
    test('test- ids, dev- ids and voided rows are ignored', () {
      final es = viewerEvents([
        ev('test-1', '2026-11-17', EventType.cigarette, qty: 9),
        ev('dev-1', '2026-11-17', EventType.cigarette, qty: 9),
        ev('a', '2026-11-17', EventType.cigarette, qty: 2),
        ev('b', '2026-11-17', EventType.cigarette, qty: 3),
        ev('v', '2026-11-17', EventType.voidEvent, label: 'b'),
      ]);
      expect(weekMetrics(es, week).cigs.last, 2);
    });

    test('missing days are null, never zero; averages skip them', () {
      final es = [
        ev('a', '2026-11-11', EventType.cigarette, qty: 4),
        ev('b', '2026-11-13', EventType.cigarette, qty: 8),
      ];
      final m = weekMetrics(es, week);
      expect(m.cigs, [4, null, 8, null, null, null, null]);
      expect(m.cigAvg, 6);
      expect(m.sleep, everyElement(isNull));
      expect(m.dayToDay, everyElement(isNull));
      expect(m.burnAvg, isNull);
    });

    test('untimed rows count in totals but not on the time axis', () {
      final es = [
        ev('a', '2026-11-17', EventType.cigarette, qty: 2),
        ev('b', '2026-11-17', EventType.cigarette, qty: 1, time: '10:00'),
      ];
      final m = weekMetrics(es, week);
      expect(m.cigs.last, 3);
      expect(m.cigsTimed.last, 1);
      expect(m.hours, {10: 1});
      final d = dayView(es, '2026-11-17');
      expect(d.marks.where((x) => x.lane == Lane.smoke).length, 1);
      expect(d.untimedCigs, 2);
    });

    test(
      'a bedtime after noon crosses midnight; the night is the wake date',
      () {
        final ns = nights([
          ev('s', '2026-11-16', EventType.sleep, time: '23:00', end: '06:30'),
        ]);
        expect(ns.single.wakeDate, '2026-11-17');
        expect(ns.single.hours, 7.5); // computed: no qty
        expect(sleepByWakeDate(ns, ['2026-11-16', '2026-11-17']), [null, 7.5]);
        expect(ns.single.segmentOn('2026-11-16'), (1380, 1440));
        expect(ns.single.segmentOn('2026-11-17'), (0, 390));
      },
    );

    test('bus legs pair in time order; a lone arrive makes no leg', () {
      final legs = legsOn([
        ev('x', '2026-11-17', EventType.busArrive, time: '08:00'),
        ev('b2', '2026-11-17', EventType.busBoard, time: '20:15'),
        ev('a1', '2026-11-17', EventType.busArrive, time: '10:40'),
        ev('b1', '2026-11-17', EventType.busBoard, time: '09:20'),
        ev('a2', '2026-11-17', EventType.busArrive, time: '21:45'),
      ]);
      expect([for (final l in legs) l.minutes], [80, 90]);
    });

    test('money only on spend rows; bills and one-offs leave the burn', () {
      final es = [
        ev('c', '2026-11-17', EventType.cigarette, qty: 1, amount: 25),
        ev(
          's1',
          '2026-11-17',
          EventType.spend,
          amount: 45,
          category: 'tobacco',
        ),
        ev('s2', '2026-11-17', EventType.spend, amount: 999, category: 'bills'),
        ev(
          's3',
          '2026-11-17',
          EventType.spend,
          amount: 100,
          category: 'food_out',
          source: 'lazypay',
          label: 'Zomato: Dinner',
        ),
      ];
      final m = weekMetrics(es, week);
      expect(m.dayToDay.last, 145);
      expect(m.oneOffTotal, 999);
      expect(m.payLater, 100);
      expect(m.payLaterMerchants, ['Zomato']);
    });

    test('notes never count; an empty day says so', () {
      final es = [ev('n', '2026-11-17', EventType.note, label: 'hello')];
      final m = weekMetrics(es, week);
      expect(m.daysLogged, 0);
      expect(dayView(es, '2026-11-16').isEmpty, isTrue);
      expect(dayView(es, '2026-11-17').entries, isEmpty);
    });

    test('confidence levels', () {
      expect(confidence(2), 1);
      expect(confidence(5), 2);
      expect(confidence(10), 3);
      expect(confidence(1, direct: true), 3);
      expect(confidence(21, consistent: true), 4);
      expect(confidence(42, consistent: true), 5);
    });
  });
}
