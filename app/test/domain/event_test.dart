import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/effective_events.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';

void main() {
  group('Event JSON', () {
    test('round-trips through toJson / fromJson', () {
      const e = Event(
        id: 'a1',
        date: '2026-11-17',
        time: '18:02',
        type: EventType.cigarette,
        qty: 1,
        unit: 'cig',
        amountInr: 25,
        category: 'tobacco',
        approx: true,
        note: 'after lunch',
      );
      expect(Event.fromJson(e.toJson()), e);
    });

    test('toJson omits nulls and never sends created_at', () {
      const e = Event(id: 'a', date: '2026-11-17', type: EventType.tea);
      expect(e.toJson().keys.toSet(), {
        'id',
        'date',
        'type',
        'approx',
        'source',
      });
    });

    test('parses a sheet row where every cell is a string', () {
      final e = Event.fromSheetRow({
        '_row': 5,
        'id': 'x',
        'date': '2026-11-17',
        'time': '9:05',
        'end_time': '',
        'type': 'weight',
        'qty': '87.91',
        'unit': 'kg',
        'label': '',
        'amount_inr': '',
        'category': '',
        'approx': 'FALSE',
        'source': 'app',
        'note': '',
        'created_at': '2026-11-17T03:35:00.000Z',
      })!;
      expect(e.time, '09:05');
      expect(e.endTime, isNull);
      expect(e.qty, 87.91);
      expect(e.amountInr, isNull);
      expect(e.approx, isFalse);
      expect(e.label, isNull);
    });

    test('approx reads back as "TRUE"', () {
      final e = Event.fromSheetRow({
        'id': 'x',
        'date': '2026-11-17',
        'type': 'sleep',
        'approx': 'TRUE',
      })!;
      expect(e.approx, isTrue);
    });

    test('rows with no id, bad date or unknown type are dropped', () {
      expect(Event.fromSheetRow({'date': '2026-11-17', 'type': 'tea'}), isNull);
      expect(
        Event.fromSheetRow({'id': 'a', 'date': 'Tue', 'type': 'tea'}),
        isNull,
      );
      expect(
        Event.fromSheetRow({'id': 'a', 'date': '2026-11-17', 'type': 'dance'}),
        isNull,
      );
    });
  });

  group('effectiveEvents', () {
    test('drops dev- ids, voids and voided targets', () {
      const events = [
        Event(id: 'keep', date: '2026-11-17', type: EventType.tea),
        Event(id: 'gone', date: '2026-11-17', type: EventType.cigarette),
        Event(
          id: 'v1',
          date: '2026-11-17',
          type: EventType.voidEvent,
          label: 'gone',
        ),
        Event(id: 'dev-x', date: '2026-11-17', type: EventType.study),
      ];
      expect(effectiveEvents(events).map((e) => e.id), ['keep']);
    });

    test('a dev- void cannot cancel a real event', () {
      const events = [
        Event(id: 'real', date: '2026-11-17', type: EventType.tea),
        Event(
          id: 'dev-v',
          date: '2026-11-17',
          type: EventType.voidEvent,
          label: 'real',
        ),
      ];
      expect(effectiveEvents(events).map((e) => e.id), ['real']);
    });
  });
}
