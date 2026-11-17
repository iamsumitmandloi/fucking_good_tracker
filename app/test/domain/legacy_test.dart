import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/legacy/legacy_adapter.dart';
import 'package:starting_again/domain/legacy/legacy_cell.dart';

/// Header names are assumptions until the owner's live read (DECISIONS 21).
List<Map<String, dynamic>> dailySummary() => [
  {
    '_row': 2,
    'Date': '15 Nov 2026',
    'Cigarettes': '6',
    'Sleep (h)': '~7.5 (inferred from timeline)',
    'Weight (kg)': '88.1',
    'Steps': '2,096',
    'Water': 'N/A',
    'Energy': '5',
    'Commute (min)': 'N/A — weekend',
    'Work': '',
    'Exercise': '',
  },
  {
    '_row': 3,
    'Date': '16 Nov 2026',
    'Cigarettes': '~4–5',
    'Sleep (h)': '~6–6.25 h',
    'Weight (kg)': '88.7',
    'Steps': '',
    'Water': '',
    'Energy': '',
    'Commute (min)': '90',
    'Work': 'Office 10:40–18:00; commute 175 min door to door',
    'Exercise': 'Walked to the station, 12,576 steps total',
  },
  {'_row': 4, 'Date': 'Totals', 'Cigarettes': '10'},
];

List<Map<String, dynamic>> spending() => [
  {
    '_row': 2,
    'Date': '2026-11-16',
    'Time': '20:15',
    'Item': 'Zepto groceries',
    'Category': 'Delivery',
    'Amount (₹)': '612.50',
    'Method': 'LazyPay',
  },
  {
    '_row': 3,
    'Date': '2026-11-16',
    'Time': '',
    'Item': 'Electricity',
    'Category': 'Bills',
    'Amount (₹)': '1,450',
    'Method': 'UPI',
  },
  {
    '_row': 4,
    'Date': '16/11/2026',
    'Item': 'Play Console',
    'Category': 'One-off',
    'Amount (₹)': '2,435',
    'Method': 'Card',
  },
  {'_row': 5, 'Date': '2026-11-16', 'Item': 'Bad row', 'Amount (₹)': 'n/a'},
];

List<Map<String, dynamic>> timeline() => [
  {'_row': 2, 'Date': '2026-11-15', 'Time': '23:10', 'Entry': 'slept 22:30'},
  {'_row': 3, 'Date': '2026-11-16', 'Time': '06:30', 'Entry': 'woke 6:00'},
  {'_row': 4, 'Date': '2026-11-16', 'Time': '07:05', 'Entry': 'slept 23:30'},
  {'_row': 5, 'Date': '2026-11-16', 'Time': '09:00', 'Entry': '1 cig + tea 45'},
];

void main() {
  group('legacy cell', () {
    test('PRD examples', () {
      expect(
        parseLegacyCell('~7.5 (inferred…)'),
        const LegacyCell(value: 7.5, approx: true, raw: '~7.5 (inferred…)'),
      );
      final r = parseLegacyCell('~6–6.25 h');
      expect(r.value, 6.125);
      expect(r.approx, isTrue);
      final na = parseLegacyCell('N/A — weekend');
      expect(na.missing, isTrue);
      expect(na.raw, 'N/A — weekend');
    });

    test('numbers, ranges, text, empties', () {
      expect(parseLegacyCell('87.91').value, 87.91);
      expect(parseLegacyCell('87.91').approx, isFalse);
      expect(parseLegacyCell('12,576').value, 12576);
      expect(parseLegacyCell('₹1,234.50').value, 1234.5);
      expect(parseLegacyCell('6-7').value, 6.5);
      expect(parseLegacyCell('6 to 7 h').value, 6.5);
      expect(parseLegacyCell('4 (2–3 singles)').value, 4);
      expect(parseLegacyCell('4 (2–3 singles)').approx, isFalse);
      expect(parseLegacyCell('≈ 5').approx, isTrue);
      expect(parseLegacyCell('0').value, 0); // a real zero stays 0
      expect(parseLegacyCell('').missing, isTrue);
      expect(parseLegacyCell(null).missing, isTrue);
      expect(parseLegacyCell('none').missing, isTrue);
      expect(parseLegacyCell('not logged').missing, isTrue);
      expect(parseLegacyCell('skipped breakfast').missing, isTrue);
      expect(parseLegacyCell(42).value, 42);
    });
  });

  group('legacy dates', () {
    test('formats', () {
      expect(legacyDate('2026-11-16', year: 2026), '2026-11-16');
      expect(legacyDate('16/11/2026', year: 2026), '2026-11-16');
      expect(legacyDate('16 Nov 2026', year: 2026), '2026-11-16');
      expect(legacyDate('Mon 16 Nov', year: 2026), '2026-11-16');
      expect(legacyDate('16-Nov', year: 2026), '2026-11-16');
      expect(legacyDate('Totals', year: 2026), isNull);
      expect(legacyDate('', year: 2026), isNull);
    });
  });

  group('adapter', () {
    final imp = adaptLegacy({
      'Daily Summary': dailySummary(),
      'Spending': spending(),
      'Timeline': timeline(),
    }, year: 2026);

    List<Event> of(EventType t, [String? date]) => [
      for (final e in imp.events)
        if (e.type == t && (date == null || e.date == date)) e,
    ];

    test('Daily Summary → counts, weight, steps, energy; N/A skipped', () {
      expect(of(EventType.cigarette).map((e) => e.qty), [6, 4.5]);
      expect(of(EventType.cigarette)[1].approx, isTrue);
      expect(of(EventType.weight).map((e) => e.qty), [88.1, 88.7]);
      expect(of(EventType.steps).single.qty, 2096);
      expect(of(EventType.energy).single.qty, 5);
      expect(of(EventType.waterMl), isEmpty); // "N/A" and "" are missing
      expect(imp.sleepHours['2026-11-15']!.value, 7.5);
      expect(imp.sleepHours['2026-11-16']!.value, 6.125);
      expect(
        imp.events.every((e) => e.source == 'legacy' || e.source == 'lazypay'),
        isTrue,
      );
      expect(imp.events.every((e) => e.id.startsWith('legacy-')), isTrue);
    });

    test('16 Nov data bugs are flagged, not fixed', () {
      expect(imp.flags.map((f) => f.date), everyElement('2026-11-16'));
      expect(
        imp.flags.map((f) => f.text),
        containsAll([
          'Commute: 90 min in the column, 175 in Work',
          'Steps (12,576) are in Exercise, not in the Steps column',
        ]),
      );
      // The steps number stays out of the stats.
      expect(of(EventType.steps, '2026-11-16'), isEmpty);
    });

    test('Spending → spend events with categories and pay later', () {
      final s = of(EventType.spend);
      expect(s.map((e) => e.amountInr), [612.5, 1450, 2435]);
      expect(s.map((e) => e.category), ['delivery', 'bills', 'one_off']);
      expect(s[0].source, 'lazypay');
      expect(s[0].time, '20:15');
      expect(s[2].date, '2026-11-16');
      expect(s[1].label, 'Electricity');
    });

    test(
      'Timeline → sleep and wake only; later-than-row time = day before',
      () {
        final sleeps = of(EventType.sleep);
        expect(sleeps.map((e) => '${e.date} ${e.time}'), [
          '2026-11-15 22:30',
          '2026-11-15 23:30', // written 07:05 on the 16th
        ]);
        expect(of(EventType.wake).single.time, '06:00');
        expect(of(EventType.cigarette, '2026-11-16').single.qty, 4.5);
      },
    );

    test('unknown shapes never throw', () {
      expect(
        adaptLegacy({
          'Daily Summary': [
            {'x': 1},
            {'Date': null},
          ],
          'Spending': [
            {'Amount': '5'},
          ],
          'Timeline': [{}],
        }, year: 2026),
        LegacyImport.empty,
      );
    });
  });

  group('merge: Events tab wins', () {
    test('legacy fills only empty (date, metric) pairs', () {
      final imp = adaptLegacy({
        'Daily Summary': dailySummary(),
        'Spending': spending(),
      }, year: 2026);
      const live = [
        Event(
          id: 'a',
          date: '2026-11-16',
          time: '09:00',
          type: EventType.cigarette,
          qty: 1,
          amountInr: 25,
        ),
      ];
      final merged = withLegacy(live, imp);
      final cigs16 = merged.where(
        (e) => e.type == EventType.cigarette && e.date == '2026-11-16',
      );
      expect(cigs16.single.id, 'a'); // legacy 4.5 dropped
      // 16 Nov has money in Events, so legacy spend for it is dropped.
      expect(merged.where((e) => e.type == EventType.spend), isEmpty);
      // 15 Nov had nothing live: legacy cigarettes stay.
      expect(
        merged.where(
          (e) => e.type == EventType.cigarette && e.date == '2026-11-15',
        ),
        hasLength(1),
      );
    });
  });
}
