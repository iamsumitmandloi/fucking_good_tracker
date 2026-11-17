import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

Map<String, dynamic> row(
  String id,
  String date,
  String time,
  String type, {
  String qty = '',
  String amount = '',
  String category = '',
  String source = 'app',
  String label = '',
}) => {
  '_row': 2,
  'id': id,
  'date': date,
  'time': time,
  'end_time': '',
  'type': type,
  'qty': qty,
  'unit': '',
  'label': label,
  'amount_inr': amount,
  'category': category,
  'approx': 'FALSE',
  'source': source,
  'note': '',
  'created_at': '2026-11-17T00:00:00.000Z',
};

final events = [
  row('c1', '2026-11-12', '10:00', 'cigarette', qty: '13'),
  row(
    'c2',
    '2026-11-17',
    '09:00',
    'cigarette',
    qty: '1',
    amount: '25',
    category: 'tobacco',
  ),
  row('c3', '2026-11-17', '12:00', 'cigarette', qty: '3'),
  row('s1', '2026-11-16', '22:30', 'sleep'),
  row('w1', '2026-11-17', '06:00', 'wake'),
  row('k1', '2026-11-17', '06:10', 'weight', qty: '87.91'),
  row('k2', '2026-11-14', '07:00', 'weight', qty: '88.5'),
  row(
    'l1',
    '2026-11-17',
    '13:00',
    'meal',
    amount: '130',
    category: 'canteen',
    label: 'Canteen lunch',
  ),
  row(
    'z1',
    '2026-11-16',
    '20:15',
    'spend',
    amount: '612.5',
    category: 'delivery',
    source: 'lazypay',
    label: 'Zepto',
  ),
  row(
    'b1',
    '2026-11-14',
    '11:00',
    'spend',
    amount: '1450',
    category: 'bills',
    label: 'Electricity',
  ),
  row('dev-x', '2026-11-17', '13:30', 'spend', amount: '9999'),
];

final legacyTabs = {
  'Daily Summary': [
    {
      '_row': 2,
      'Date': '15 Nov 2026',
      'Cigarettes': '6',
      'Sleep (h)': '~7.5',
      'Steps': '2,096',
      'Commute (min)': 'N/A — weekend',
      'Work': '',
      'Exercise': '',
    },
    {
      '_row': 3,
      'Date': '16 Nov 2026',
      'Cigarettes': '~4–5',
      'Sleep (h)': '~6–6.25 h',
      'Steps': '',
      'Commute (min)': '90',
      'Work': 'commute 175 min door to door',
      'Exercise': 'Walked a lot, 12,576 steps',
    },
  ],
};

Future<AppHarness> seeded(WidgetTester tester) async {
  final h = await AppHarness.create();
  await tester.runAsync(() async {
    await h.deps.events.mergeServerRows(events);
    await h.deps.legacy.applyTabs(legacyTabs);
  });
  return h;
}

void main() {
  testWidgets('Week: bars with gaps, sleep, weight, not logged, data flags', (
    tester,
  ) async {
    final h = await seeded(tester);
    await h.pump(tester, '/week');

    expect(find.text('Week'), findsWidgets);
    expect(
      find.text('Wed 11 – Tue 17 Nov · 5 of 7 days logged'),
      findsOneWidget,
    );
    // 13 + 6 (legacy) + 4.5 (legacy, approx) + 4 = 27.5
    expect(find.text('27.5 total · ≈ ₹688 at ₹25 each'), findsOneWidget);
    expect(find.text('Down from 13 on Thu to 4 on Tue.'), findsOneWidget);
    expect(find.text('—'), findsWidgets); // missing days are gaps
    expect(find.text('7.5h'), findsOneWidget); // Tue, from bed/wake
    expect(find.text('~6.1h'), findsOneWidget); // Mon, legacy hours
    expect(find.text('Sheet data to check'), findsOneWidget);
    expect(
      find.text('Mon 16: Commute: 90 min in the column, 175 in Work'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Mon 16: Steps (12,576) are in Exercise, not in the Steps column',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Not logged'), 200);
    expect(
      find.text('Axis 86–90 kg. Daily swing 0.6 kg is noise; watch the line.'),
      findsOneWidget,
    );
    expect(find.text('Study sessions'), findsOneWidget);

    await h.dispose(tester);
  });

  testWidgets('Money: burn excludes bills, pay later, today list', (
    tester,
  ) async {
    final h = await seeded(tester);
    await h.pump(tester, '/money');

    // Day-to-day = 25 + 130 + 612.5 = 767.5 → ₹110/day over 7 days.
    expect(find.text('₹110/day'), findsOneWidget);
    expect(find.text('₹768 this week\n₹2,218 incl. one-offs'), findsOneWidget);
    expect(find.text('One-offs: Electricity'), findsOneWidget);
    expect(find.text('Delivery apps · 1 order'), findsOneWidget);
    expect(find.text('₹613'), findsWidgets); // pay later (and the legend)
    expect(find.text('1 charge this week.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Today · ₹155'), 200);
    expect(find.text('Canteen lunch'), findsOneWidget);
    expect(find.textContaining('9,999'), findsNothing); // dev row ignored

    await h.dispose(tester);
  });

  testWidgets('Week and Money with no data: dashes, no zeros', (tester) async {
    final h = await AppHarness.create();
    await h.pump(tester, '/week');
    expect(find.text('Not logged this week'), findsWidgets);
    expect(find.text('Not logged this week.'), findsOneWidget);
    await h.dispose(tester);

    final m = await AppHarness.create();
    await m.pump(tester, '/money');
    expect(find.text('—'), findsWidgets);
    expect(find.text('Nothing spent\nthis week'), findsOneWidget);
    expect(find.text('Nothing spent today.'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);
    await m.dispose(tester);
  });
}
