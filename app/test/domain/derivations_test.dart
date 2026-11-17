import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/derivations/commute.dart';
import 'package:starting_again/domain/derivations/daily_stats.dart';
import 'package:starting_again/domain/derivations/sleep.dart';
import 'package:starting_again/domain/effective_events.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';

var _n = 0;
Event ev(
  EventType type,
  String date,
  String? time, {
  double? qty,
  String? unit,
  String? label,
  double? amount,
  String? category,
  bool approx = false,
  String? note,
  String? id,
}) => Event(
  id: id ?? 'e${_n++}',
  date: date,
  time: time,
  type: type,
  qty: qty,
  unit: unit,
  label: label,
  amountInr: amount,
  category: category,
  approx: approx,
  note: note,
);

void main() {
  group('sleep windows', () {
    test('across midnight: labelled by wake date', () {
      final w = sleepWindows([
        ev(EventType.sleep, '2026-11-16', '22:30'),
        ev(EventType.wake, '2026-11-17', '06:00'),
      ]);
      expect(w, hasLength(1));
      expect(w.single.wakeDate, '2026-11-17');
      expect(w.single.minutes, 450);
      expect(w.single.hours, 7.5);
      expect(w.single.late, isFalse);
      expect(nightEndingOn(w, '2026-11-17'), w.single);
    });

    test('bedtime after 02:00 is late; same-day wake', () {
      final w = sleepWindows([
        ev(EventType.sleep, '2026-11-17', '02:30'),
        ev(EventType.wake, '2026-11-17', '09:00'),
      ]).single;
      expect(w.late, isTrue);
      expect(w.minutes, 390);
      expect(w.wakeDate, '2026-11-17');
    });

    test('approx if either end is approx', () {
      final w = sleepWindows([
        ev(EventType.sleep, '2026-11-16', '22:30', approx: true),
        ev(EventType.wake, '2026-11-17', '06:00'),
      ]).single;
      expect(w.approx, isTrue);
    });

    test('no wake yet → open window, minutes null (never 0)', () {
      final w = sleepWindows([ev(EventType.sleep, '2026-11-16', '23:00')])
          .single;
      expect(w.wake, isNull);
      expect(w.minutes, isNull);
      expect(w.wakeDate, '2026-11-17');
    });

    test('wake more than 18 h later does not close the window', () {
      final w = sleepWindows([
        ev(EventType.sleep, '2026-11-15', '22:00'),
        ev(EventType.wake, '2026-11-16', '18:30'),
      ]);
      expect(w.single.wake, isNull);
    });

    test('two bedtimes in a row: the first never got a wake', () {
      final w = sleepWindows([
        ev(EventType.sleep, '2026-11-16', '22:00'),
        ev(EventType.sleep, '2026-11-16', '23:30'),
        ev(EventType.wake, '2026-11-17', '06:30'),
      ]);
      expect(w, hasLength(2));
      expect(w[0].wake, isNull);
      expect(w[1].minutes, 420);
    });

    test('untimed sleep events are ignored', () {
      expect(sleepWindows([ev(EventType.sleep, '2026-11-16', null)]), isEmpty);
    });
  });

  group('commute', () {
    const d = '2026-11-17';

    test('no events → no legs, total null', () {
      final c = commuteFor([], d);
      expect(c.legs, isEmpty);
      expect(c.riding, isFalse);
      expect(c.totalMinutes, isNull);
    });

    test('board only → riding', () {
      final c = commuteFor([ev(EventType.busBoard, d, '09:20')], d);
      expect(c.riding, isTrue);
      expect(c.completedCount, 0);
    });

    test('two legs: total = sum of both', () {
      final c = commuteFor([
        ev(EventType.busBoard, d, '09:20'),
        ev(EventType.busArrive, d, '10:40'),
        ev(EventType.busBoard, d, '18:02'),
        ev(EventType.busArrive, d, '19:28'),
      ], d);
      expect(c.completedCount, 2);
      expect(c.legs[0].minutes, 80);
      expect(c.legs[1].minutes, 86);
      expect(c.totalMinutes, 166);
      expect(c.lastCompleted!.arrive, '19:28');
      expect(c.riding, isFalse);
    });

    test('leg across midnight adds 24 h', () {
      final c = commuteFor([
        ev(EventType.busBoard, d, '23:30'),
        ev(EventType.busArrive, d, '00:20'),
      ], d);
      // Sorted by time the arrive comes first: an orphan arrive, then an
      // open board. Neither is complete.
      expect(c.completedCount, 0);
      expect(const BusLeg(board: '23:30', arrive: '00:20').minutes, 50);
    });

    test('other days and orphan arrives are handled', () {
      final c = commuteFor([
        ev(EventType.busArrive, d, '08:00'),
        ev(EventType.busBoard, '2026-11-16', '09:00'),
      ], d);
      expect(c.legs, hasLength(1));
      expect(c.legs.single.board, isNull);
      expect(c.totalMinutes, isNull);
    });
  });

  group('daily summary', () {
    const d = '2026-11-17';

    test('nothing logged → every metric null, not 0', () {
      final s = summarize([], d);
      expect(s.cigs, isNull);
      expect(s.teas, isNull);
      expect(s.waterMl, isNull);
      expect(s.proteinG, isNull);
      expect(s.spend, isNull);
      expect(s.weightKg, isNull);
      expect(s.lastMeal, isNull);
    });

    test('counts, water, protein, spend, supplements', () {
      final s = summarize([
        ev(EventType.cigarette, d, '09:00', qty: 1, amount: 25),
        ev(EventType.cigarette, d, '12:00', qty: 2, amount: 50),
        ev(EventType.cigarette, '2026-11-16', '12:00', qty: 9),
        ev(EventType.tea, d, '10:00', amount: 20),
        ev(EventType.waterMl, d, '10:00', qty: 250),
        ev(EventType.waterMl, d, '11:00', qty: 500),
        ev(EventType.meal, d, '08:30', qty: 30, unit: 'g', label: proteinLabel),
        ev(EventType.meal, d, '13:00', label: 'Lunch', amount: 130),
        ev(EventType.supplement, d, '08:00', label: 'D3'),
        ev(EventType.supplement, d, '08:01', label: 'D3'),
        ev(EventType.weight, d, '07:00', qty: 88.1),
        ev(EventType.weight, d, '21:00', qty: 87.9),
      ], d);
      expect(s.cigs, 3);
      expect(s.teas, 1);
      expect(s.waterMl, 750);
      expect(s.proteinG, 30);
      expect(s.spend, 225);
      expect(s.spendEntries, 4);
      expect(s.supplements, {'D3'});
      expect(s.lastMeal!.label, 'Lunch');
      expect(s.meals, hasLength(1)); // protein is not a meal tile entry
      expect(s.weightKg, 87.9);
    });

    test('dev rows and voided events never count', () {
      final all = [
        ev(EventType.cigarette, d, '09:00', id: 'a'),
        ev(EventType.cigarette, d, '09:05', id: 'dev-x'),
        ev(EventType.cigarette, d, '09:10', id: 'b'),
        ev(EventType.voidEvent, d, '09:11', label: 'b', id: 'v1'),
      ];
      expect(summarize(effectiveEvents(all), d).cigs, 1);
    });

    test('firstDate finds the earliest day', () {
      expect(firstDate([]), isNull);
      expect(
        firstDate([
          ev(EventType.tea, '2026-11-15', null),
          ev(EventType.tea, '2026-11-11', null),
        ]),
        '2026-11-11',
      );
    });
  });
}
