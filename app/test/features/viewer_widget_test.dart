import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:starting_again/core/feature_flags.dart';
import 'package:starting_again/data/local/db.dart';
import 'package:starting_again/data/sync/sync_service.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/viewer/day_view.dart';
import 'package:starting_again/features/busmode/busmode_screen.dart';
import 'package:starting_again/features/quicklog/quicklog_sheet.dart';
import 'package:starting_again/features/study/study_screen.dart';
import 'package:starting_again/features/today/today_screen.dart';
import 'package:starting_again/features/today/today_widgets.dart';
import 'package:starting_again/features/viewer/day/day_screen.dart';
import 'package:starting_again/features/viewer/widgets/day_ribbon.dart';

import '../support/app_harness.dart';

Map<String, dynamic> row(
  String id,
  String date,
  String type, {
  String time = '',
  String end = '',
  String qty = '',
  String amount = '',
  String category = '',
  String label = '',
  String approx = 'FALSE',
  String source = 'chat',
}) => {
  '_row': 2,
  'id': id,
  'date': date,
  'time': time,
  'end_time': end,
  'type': type,
  'qty': qty,
  'unit': '',
  'label': label,
  'amount_inr': amount,
  'category': category,
  'approx': approx,
  'source': source,
  'note': '',
  'created_at': '2026-11-17T00:00:00.000Z',
};

final synthetic = [
  row(
    's',
    '2026-11-16',
    'sleep',
    time: '22:30',
    end: '06:00',
    qty: '7.5',
    approx: 'TRUE',
  ),
  row('c1', '2026-11-17', 'cigarette', time: '14:00', qty: '2'),
  row('t1', '2026-11-17', 'tea', time: '14:00', qty: '1', label: 'Tea'),
  row(
    'p1',
    '2026-11-17',
    'spend',
    time: '14:00',
    amount: '45',
    category: 'tobacco',
    label: '2 cigarettes + tea',
  ),
  row('b1', '2026-11-17', 'bus_board', time: '09:20'),
  row('a1', '2026-11-17', 'bus_arrive', time: '10:40'),
  row('c2', '2026-11-17', 'cigarette', qty: '1'),
  row('c3', '2026-11-16', 'cigarette', qty: '3'),
  row('test-1', '2026-11-17', 'cigarette', qty: '40'),
];

Future<AppHarness> seeded(
  WidgetTester tester,
  List<Map<String, dynamic>> rows,
) async {
  final h = await AppHarness.create();
  await tester.runAsync(() => h.deps.events.mergeServerRows(rows));
  return h;
}

final _fixture = File('fixtures/events_backfill.json');

void main() {
  testWidgets('7.1 gate: no write entry point is reachable', (tester) async {
    expect(FeatureFlags.logging, isFalse);
    final h = await seeded(tester, synthetic);
    await h.pump(tester, '/day');

    void noWrites() {
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(QuickTile), findsNothing);
      expect(find.text('+1'), findsNothing);
      expect(find.text('Board'), findsNothing);
      expect(find.text('Arrived'), findsNothing);
      expect(find.byType(QuickLogSheet), findsNothing);
      expect(find.text('Undo'), findsNothing);
    }

    // Five tabs, no Today, no Study.
    for (final t in ['Day', 'Week', 'Trends', 'Money', 'Insights']) {
      expect(find.text(t), findsWidgets);
    }
    expect(find.text('Today'), findsNothing);
    expect(find.text('Study'), findsNothing);

    for (final t in ['Day', 'Week', 'Trends', 'Money', 'Insights']) {
      await tester.tap(find.text(t).last);
      await h.settle(tester);
      noWrites();
      if (t == 'Trends') {
        await tester.tap(find.text('Sleep & body'));
        await h.settle(tester);
        noWrites();
      }
      // Long-press anywhere opened Quick log in v1; nothing here.
      await tester.longPress(find.byType(ListView).first);
      await h.settle(tester);
      noWrites();
    }
    await h.dispose(tester);

    // Write routes don't exist.
    for (final path in ['/today', '/study', '/bus', '/session']) {
      final r = await AppHarness.create();
      await r.pump(tester, path);
      expect(find.byType(TodayScreen), findsNothing);
      expect(find.byType(StudyScreen), findsNothing);
      expect(find.byType(BusModeScreen), findsNothing);
      await r.dispose(tester);
    }
  });

  testWidgets('7.1 gate: repository and outbox refuse to write', (
    tester,
  ) async {
    final h = await AppHarness.create();
    const e = Event(
      id: 'x',
      date: '2026-11-17',
      type: EventType.note,
      label: 'hi',
    );
    await tester.runAsync(() async {
      await expectLater(h.deps.events.log([e]), throwsA(isA<ReadOnlyError>()));
      await expectLater(h.deps.events.undo('x'), throwsA(isA<ReadOnlyError>()));
      // Something left in the outbox by an older build is kept, never sent.
      await h.deps.db
          .into(h.deps.db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: 'old',
              payload: jsonEncode(e.copyWith(id: 'old').toJson()),
              enqueuedAt: 1,
              attempts: const Value(0),
            ),
          );
      expect(await h.deps.sync.flushNow(), FlushOutcome.blocked);
      expect(h.server.posts, 0);
      expect(await h.deps.db.select(h.deps.db.outbox).get(), hasLength(1));
      // Refresh still reads Events, and only Events.
      await h.deps.appSync.syncNow();
    });
    expect(h.server.posts, 0);
    expect(h.server.requested.map((u) => u.queryParameters['tabs']).toSet(), {
      'Events',
    });
    await h.dispose(tester);
  });

  testWidgets('Day: ribbon tap shows the detail line', (tester) async {
    final h = await seeded(tester, synthetic);
    await h.pump(tester, '/day');

    expect(find.text('Tue 17 Nov'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // 2 timed + 1 untimed (test- ignored)
    expect(find.text('~7.5 h'), findsOneWidget);
    expect(find.text('1 cigarette with no time'), findsOneWidget);
    expect(
      find.text('Tap any mark on the ribbon to see what and when.'),
      findsOneWidget,
    );

    final ribbon = find.byType(DayRibbon);
    await tester.ensureVisible(ribbon);
    await tester.pump();
    // Re-read the rect each time: the list may scroll between taps.
    Offset at(Lane lane, int minute) {
      final r = tester.getRect(ribbon);
      final trackW = r.width - DayRibbon.labelW;
      return Offset(
        r.left + DayRibbon.labelW + minute / 1440 * trackW,
        r.top + DayRibbon.laneTop(lane) + DayRibbon.laneH[lane.index] / 2,
      );
    }

    await tester.tapAt(at(Lane.smoke, 14 * 60) + const Offset(4, 0));
    await tester.pump();
    expect(find.text('14:00 · 2 cigarettes'), findsOneWidget);

    await tester.tapAt(at(Lane.bus, 10 * 60));
    await tester.pump();
    expect(find.text('Bus 09:20 → 10:40 · 80 min'), findsOneWidget);

    await tester.tapAt(at(Lane.money, 14 * 60));
    await tester.pump();
    expect(find.text('14:00 · ₹45 · 2 cigarettes + tea'), findsOneWidget);

    await tester.tapAt(at(Lane.sleep, 3 * 60));
    await tester.pump();
    expect(find.text('Asleep 22:30 → 06:00 · ~7.5 h'), findsOneWidget);

    await h.dispose(tester);
  });

  testWidgets('Day: ‹ › switches days; › stops at today', (tester) async {
    final h = await seeded(tester, synthetic);
    await h.pump(tester, '/day');
    expect(find.text('Tue 17 Nov'), findsOneWidget);

    // › is disabled on today.
    await tester.tap(find.byKey(const Key('day-next')));
    await h.settle(tester);
    expect(find.text('Tue 17 Nov'), findsOneWidget);

    await tester.tap(find.byKey(const Key('day-prev')));
    await h.settle(tester);
    expect(find.text('Mon 16 Nov'), findsOneWidget);
    expect(find.text('3 cigarettes with no time'), findsOneWidget);

    // 16 Nov is the first day with data: ‹ stops there.
    await tester.tap(find.byKey(const Key('day-prev')));
    await h.settle(tester);
    expect(find.text('Mon 16 Nov'), findsOneWidget);

    await tester.tap(find.byKey(const Key('day-next')));
    await h.settle(tester);
    expect(find.text('Tue 17 Nov'), findsOneWidget);

    // A Week row opens that day.
    await tester.tap(find.text('Week').last);
    await h.settle(tester);
    await tester.tap(find.textContaining('Mon\n', findRichText: true));
    await h.settle(tester);
    expect(find.byType(DayScreen), findsOneWidget);
    expect(find.text('Mon 16 Nov'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('An empty day and an empty week show dashes, not zeros', (
    tester,
  ) async {
    final h = await AppHarness.create();
    await h.pump(tester, '/day');
    expect(find.text('Nothing logged yet today'), findsOneWidget);
    await tester.tap(find.text('Week').last);
    await h.settle(tester);
    expect(
      find.text('Wed 11 – Tue 17 Nov · 0 of 7 days logged'),
      findsOneWidget,
    );
    expect(find.text('0'), findsNothing);
    await tester.tap(find.text('Money').last);
    await h.settle(tester);
    expect(find.text('No spend rows in these 7 days.'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);
    await tester.tap(find.text('Trends').last);
    await h.settle(tester);
    expect(find.text('No cigarettes logged in these 7 days.'), findsOneWidget);
    await tester.tap(find.text('Insights').last);
    await h.settle(tester);
    expect(
      find.text('Not enough logged this week for a pattern yet.'),
      findsOneWidget,
    );
    await h.dispose(tester);
  });

  final skip = _fixture.existsSync()
      ? false
      : 'fixtures/events_backfill.json missing: run `dart run tool/export_events.dart`';

  testWidgets('Numbers on screen equal the 7.2 table (live backfill)', (
    tester,
  ) async {
    final rows = (jsonDecode(_fixture.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final h = await seeded(tester, rows);

    /// Scroll the current tab until [f] is built and visible.
    Future<Finder> see(Finder f) async {
      await tester.scrollUntilVisible(
        f,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      return f;
    }

    await h.pump(tester, '/week');
    expect(
      find.text('Wed 11 – Tue 17 Nov · 7 of 7 days logged'),
      findsOneWidget,
    );
    expect(await see(find.text('7.1 a day')), findsOneWidget);
    expect(await see(find.text('6.5 h')), findsOneWidget);
    expect(await see(find.text('avg · 2 nights 7h+')), findsOneWidget);
    expect(await see(find.text('₹6,858')), findsOneWidget);
    expect(await see(find.text('₹980 a day')), findsOneWidget);
    expect(await see(find.text('+13 no time')), findsOneWidget); // Wed
    expect(
      find.textContaining(
        'Smoking clusters after lunch and at evening tea.',
        findRichText: true,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Trends').last);
    await h.settle(tester);
    expect(await see(find.text('50')), findsOneWidget);
    expect(
      await see(find.text('7.1 a day\nhigh 13 Wed · low 4 Mon')),
      findsOneWidget,
    );
    expect(await see(find.text('17 timed of 50')), findsOneWidget);
    expect(await see(find.text('8 of 17')), findsOneWidget);
    expect(await see(find.text('47% of timed cigarettes')), findsOneWidget);
    expect(await see(find.text('7.8')), findsOneWidget);
    expect(await see(find.text('5.5')), findsOneWidget);
    expect(await see(find.text('a day · 5 vs 2 days')), findsOneWidget);
    expect(await see(find.text('≈ ₹1,250 / week')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Sleep & body'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sleep & body'));
    await h.settle(tester);
    expect(await see(find.text('6.5 h')), findsOneWidget);
    expect(await see(find.text('±1h 39m')), findsOneWidget);
    expect(await see(find.text('2 of 7')), findsOneWidget);
    expect(
      await see(find.text('Sat not logged. Sun 2,096, the low.')),
      findsOneWidget,
    );

    await tester.tap(find.text('Money').last);
    await h.settle(tester);
    expect(
      await see(find.text('₹6,858 this week\n+ ₹3,885 one-offs')),
      findsOneWidget,
    );
    expect(await see(find.text('Delivery apps')), findsOneWidget);
    expect(
      await see(find.textContaining('₹4,134 60%', findRichText: true)),
      findsOneWidget,
    );
    expect(await see(find.text('₹1,821')), findsOneWidget);
    expect(
      await see(find.text('Zepto, Blink, Zomato · 3 charges')),
      findsOneWidget,
    );

    await tester.tap(find.text('Insights').last);
    await h.settle(tester);
    expect(
      await see(find.text('Tea and cigarettes go together')),
      findsOneWidget,
    );
    expect(
      await see(find.text('More cigarettes on office days')),
      findsOneWidget,
    );
    expect(await see(find.text('17/50 timed')), findsOneWidget);

    await tester.tap(find.text('Day').last);
    await h.settle(tester);
    expect(await see(find.text('▼ 1.1 vs 7-day avg 7.1')), findsOneWidget);
    expect(await see(find.text('~7.5 h')), findsOneWidget);
    expect(await see(find.text('₹404')), findsOneWidget);
    expect(await see(find.text('2h 50m')), findsOneWidget);
    await h.dispose(tester);
  }, skip: skip != false);
}
