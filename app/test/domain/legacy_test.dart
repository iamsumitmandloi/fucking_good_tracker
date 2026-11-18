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

/// The live sheet's real headers (17 Nov read); values are made up.
List<Map<String, dynamic>> realDaily() => [
  {
    '_row': 2,
    'Date': '2026-11-16',
    'Sleep start': '~01:30',
    'Wake': '07:30',
    'Sleep hours': '~6',
    'Weight kg': '88.7',
    'Bus boarded': '09:10',
    'Bus arrived': '10:40',
    'Commute minutes': '90',
    'Cigarettes': '4',
    'Tea cups': '2',
    'Water L': '',
    'Exercise': '12,576 total steps (user-reported); separate exercise none',
    'Work': 'Evening bus commute 20:15–21:40 (85 min); morning 90',
    'Spending INR': '278',
    'Steps': '',
    'Energy': 'Okay (despite travel fatigue)',
    'Breakfast protein (g)': '30',
    'Notes': 'Morning commute 90 min',
  },
  {
    '_row': 3,
    'Date': '2026-11-17',
    'Sleep start': '22:30',
    'Wake': '06:00',
    'Sleep hours': '7.5',
    'Commute minutes': '140',
    'Notes': 'Commute 75 min + 65 min = 140 min',
    'Energy': '',
    'Steps': '8,000',
  },
];

List<Map<String, dynamic>> realSpending() => [
  {
    '_row': 2,
    'Date': '2026-11-11',
    'Time IST': '21:05',
    'Merchant / payee': 'Order merchant unreported',
    'Category': 'Cigarette packet',
    'Payment method': 'UPI',
    'Amount INR': '240',
    'Source': 'Gmail',
  },
  {
    '_row': 3,
    'Date': '2026-11-11',
    'Time IST': '21:05',
    'Merchant / payee': 'Order merchant unreported',
    'Category': 'Order handling charge',
    'Payment method': 'UPI',
    'Amount INR': '12',
    'Source': 'Gmail',
  },
  {
    '_row': 4,
    'Date': '2026-11-14',
    'Merchant / payee': 'Zomato',
    'Category': 'Dinner — litti baati meal',
    'Payment method': 'Card',
    'Amount INR': '258',
    'Source': 'Gmail / LazyPay',
  },
  {
    '_row': 5,
    'Date': '2026-11-15',
    'Merchant / payee': 'Google',
    'Category': 'Developer registration fee',
    'Payment method': 'Card',
    'Amount INR': '2,435',
    'Source': 'Gmail HDFC alert + Google receipt',
  },
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
        }, year: 2026),
        LegacyImport.empty,
      );
    });
  });

  group('live sheet headers (17 Nov read)', () {
    final imp = adaptLegacy({
      'Daily Summary': realDaily(),
      'Spending': realSpending(),
    }, year: 2026);
    List<Event> of(EventType t) => [
      for (final e in imp.events)
        if (e.type == t) e,
    ];

    test('sleep start/wake: the night that ended that morning', () {
      expect(
        of(EventType.sleep).map((e) => '${e.date} ${e.time} ${e.approx}'),
        [
          '2026-11-16 01:30 true', // after midnight: same date
          '2026-11-16 22:30 false', // evening: the day before the 17th
        ],
      );
      expect(of(EventType.wake).map((e) => '${e.date} ${e.time}'), [
        '2026-11-16 07:30',
        '2026-11-17 06:00',
      ]);
      expect(imp.sleepHours['2026-11-16']!.value, 6);
      expect(imp.sleepHours['2026-11-17']!.value, 7.5);
    });

    test('tea cups, breakfast protein, weight', () {
      expect(of(EventType.tea).single.qty, 2);
      final p = of(EventType.meal).single;
      expect(p.unit, 'g');
      expect(p.qty, 30);
      expect(of(EventType.weight).single.qty, 88.7);
    });

    test('energy in words counts as logged, without a number', () {
      final e = of(EventType.energy).single;
      expect(e.qty, isNull);
      expect(e.note, 'Okay (despite travel fatigue)');
    });

    test(
      '16 Nov bugs flagged; one leg in Notes or a matching total is not',
      () {
        expect(imp.flags.map((f) => f.text), [
          'Commute: 90 min in the column, 175 in Work (85 + 90)',
          'Steps (12,576) are in Exercise, not in the Steps column',
        ]);
        expect(of(EventType.steps).single.qty, 8000);
      },
    );

    test('Spending: description + merchant decide the category', () {
      final s = of(EventType.spend);
      expect(s.map((e) => e.label), [
        'Cigarette packet',
        'Order handling charge',
        'Dinner — litti baati meal',
        'Developer registration fee',
      ]);
      expect(s.map((e) => e.category), [
        'delivery', // an item of an order (the design counts it too)
        'delivery',
        'delivery', // Zomato
        'one_off',
      ]);
      expect(s[2].source, 'lazypay');
      expect(s[0].time, '21:05');
      expect(s[0].note, 'Order merchant unreported');
      expect(s[3].amountInr, 2435);
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
