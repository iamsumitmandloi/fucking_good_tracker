import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/quicklog/build_events.dart';
import 'package:starting_again/domain/quicklog/parser.dart';

/// 17 Nov 2026, 18:02 IST (UTC-flagged wall clock, like Clock.nowIst()).
final now = DateTime.utc(2026, 11, 17, 18, 2);

List<ParsedEntry> parse(String s) =>
    parseQuickLog(s, cigPrice: 25, teaPrice: 20).entries;

List<Event> build(
  String s, {
  WhenMode mode = WhenMode.now,
  String? picked,
  DateTime? at,
}) {
  var n = 0;
  return buildEvents(
    parse(s),
    nowIst: at ?? now,
    mode: mode,
    pickedTime: picked,
    idFactory: () => 'dev-${n++}',
  );
}

var _n = 0;
Event ev(
  String date,
  String label, {
  EventType type = EventType.spend,
  double? amount,
  String time = '12:00',
}) => Event(
  id: 'u${_n++}',
  date: date,
  time: time,
  type: type,
  label: label,
  amountInr: amount,
);

void main() {
  group('buildEvents: when', () {
    test('Now → today at the current minute', () {
      final e = build('tea').single;
      expect(e.id, 'dev-0');
      expect(e.date, '2026-11-17');
      expect(e.time, '18:02');
      expect(e.approx, isFalse);
      expect(e.amountInr, 20);
      expect(e.source, 'app');
    });

    test('15 min ago', () {
      expect(build('tea', mode: WhenMode.fifteenAgo).single.time, '17:47');
    });

    test('15 min ago just after midnight → yesterday', () {
      final e = build(
        'tea',
        mode: WhenMode.fifteenAgo,
        at: DateTime.utc(2026, 11, 17, 0, 5),
      ).single;
      expect(e.date, '2026-11-16');
      expect(e.time, '23:50');
    });

    test('~ Approx marks every entry approx at now', () {
      final es = build('cig + tea', mode: WhenMode.approx);
      expect(es.every((e) => e.approx && e.time == '18:02'), isTrue);
    });

    test('picked time earlier today', () {
      final e = build('lunch 130', mode: WhenMode.pick, picked: '13:00');
      expect(e.single.date, '2026-11-17');
      expect(e.single.time, '13:00');
    });

    test('picked time later than now → yesterday', () {
      final e = build('dinner 200', mode: WhenMode.pick, picked: '21:30');
      expect(e.single.date, '2026-11-16');
    });

    test('explicit time in the text wins over the chip', () {
      final e = build('tea at 16:30', mode: WhenMode.fifteenAgo).single;
      expect(e.time, '16:30');
      expect(e.date, '2026-11-17');
    });

    test('"slept 23:30" typed at 07:00 → yesterday', () {
      final e = build(
        'slept 23:30',
        at: DateTime.utc(2026, 11, 17, 7, 0),
      ).single;
      expect(e.type, EventType.sleep);
      expect(e.date, '2026-11-16');
      expect(e.time, '23:30');
    });

    test('"woke 6:10" typed at 07:00 → today', () {
      final e = build('woke 6:10', at: DateTime.utc(2026, 11, 17, 7, 0)).single;
      expect(e.date, '2026-11-17');
    });

    test('combo keeps the split amounts; ids unique', () {
      final es = build('1 cig + tea 45');
      expect(es.map((e) => e.amountInr), [25, 20]);
      expect(es.map((e) => e.id).toSet(), hasLength(2));
    });

    test('notes carry the raw text', () {
      final e = build('After lunch').single;
      expect(e.type, EventType.note);
      expect(e.note, 'After lunch');
    });
  });

  group('usuals', () {
    test('top 5 labels by count over the last 14 days', () {
      final events = [
        for (var i = 0; i < 4; i++)
          ev(
            '2026-11-1${i + 1}',
            'Canteen lunch',
            type: EventType.meal,
            amount: 130,
          ),
        for (var i = 0; i < 3; i++) ev('2026-11-15', 'Pani puri', amount: 30),
        ev('2026-11-16', 'Lahori Jeera', amount: 10),
        ev('2026-11-16', 'Lahori Jeera', amount: 10),
        ev('2026-11-16', 'Whey'),
        ev('2026-11-16', 'Auto', amount: 40, time: '13:00'),
        ev('2026-11-17', 'Haircut', amount: 150),
        // Older than 14 days: ignored even though frequent.
        for (var i = 0; i < 9; i++) ev('2026-11-01', 'Old thing', amount: 1),
        // Not usual: notes, study ids.
        ev('2026-11-17', 'x', type: EventType.note),
        ev('2026-11-17', 'RS-34', type: EventType.study),
      ];
      final u = usuals(events, today: '2026-11-17');
      expect(u.map((x) => x.label), [
        'Canteen lunch',
        'Pani puri',
        'Lahori Jeera',
        'Haircut', // count 1, most recent first
        'Auto',
      ]);
      expect(u.first.count, 4);
      expect(u.first.chipText, 'Canteen lunch ₹130');
      expect(u.first.entry.type, EventType.meal);
      expect(u.first.entry.time, isNull);
    });

    test('labels group case-insensitively; latest spelling wins', () {
      final u = usuals([
        ev('2026-11-16', 'pani puri', amount: 25),
        ev('2026-11-17', 'Pani Puri', amount: 30),
      ], today: '2026-11-17');
      expect(u.single.label, 'Pani Puri');
      expect(u.single.count, 2);
      expect(u.single.template.amountInr, 30);
    });

    test('chip text without money shows qty and unit', () {
      const u = Usual(
        label: 'Walk',
        template: Event(
          id: 'w',
          date: '2026-11-17',
          type: EventType.exercise,
          qty: 30,
          unit: 'min',
          label: 'Walk',
        ),
      );
      expect(u.chipText, 'Walk 30 min');
    });
  });

  group('logged text', () {
    test('one cigarette', () {
      final es = build('1 cig');
      expect(loggedText(es), 'Logged 1 cigarette · 18:02 · ₹25');
    });

    test('several entries with a total', () {
      expect(
        loggedText(build('1 cig + tea 45')),
        'Logged 2 entries · 18:02 · ₹45',
      );
    });

    test('water has no money', () {
      expect(loggedText(build('water')), 'Logged 250 ml water · 18:02');
    });
  });
}
