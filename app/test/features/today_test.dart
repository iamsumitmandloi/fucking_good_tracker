import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/core/clock.dart';
import 'package:starting_again/core/ids.dart';
import 'package:starting_again/data/local/db.dart';
import 'package:starting_again/data/repo/events_repository.dart';
import 'package:starting_again/data/repo/settings_repository.dart';
import 'package:starting_again/data/repo/study_repository.dart';
import 'package:starting_again/data/sync/sync_service.dart';
import 'package:starting_again/features/quicklog/quicklog_cubit.dart';
import 'package:starting_again/features/today/today_cubit.dart';

import '../support/fake_sheet_server.dart';

Future<void> tick([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<TodayState> until(TodayCubit c, bool Function(TodayState) p) async {
  if (p(c.state)) return c.state;
  return c.stream.firstWhere(p).timeout(const Duration(seconds: 2));
}

Map<String, dynamic> row(
  String id,
  String date,
  String time,
  String type, {
  String amount = '',
  String approx = 'FALSE',
}) => {
  '_row': 2,
  'id': id,
  'date': date,
  'time': time,
  'end_time': '',
  'type': type,
  'qty': '',
  'unit': '',
  'label': '',
  'amount_inr': amount,
  'category': '',
  'approx': approx,
  'source': 'app',
  'note': '',
  'created_at': '2026-11-17T00:00:00.000Z',
};

void main() {
  late FakeSheetServer server;
  late AppDatabase db;
  late FixedClock clock;
  late EventsRepository events;
  late StudyRepository study;
  late SettingsRepository settings;
  late SyncService sync;
  late TodayCubit cubit;

  Future<TodayCubit> makeCubit({
    String Function() idFactory = newEventId,
    Duration undoFor = const Duration(seconds: 6),
  }) async {
    cubit = TodayCubit(
      events: events,
      settings: settings,
      study: study,
      clock: clock,
      idFactory: idFactory,
      undoFor: undoFor,
    );
    await until(cubit, (s) => s.loaded);
    return cubit;
  }

  Future<List<OutboxRow>> outbox() => db.select(db.outbox).get();

  setUp(() {
    server = FakeSheetServer();
    db = memoryDb();
    clock = testClock(); // Tue 17 Nov 2026, 18:02 IST
    final api = server.api();
    events = EventsRepository(db: db, api: api, clock: clock);
    study = StudyRepository(db: db, api: api, events: events, clock: clock);
    settings = SettingsRepository(db);
    sync = SyncService(db: db, api: api, clock: clock);
  });

  tearDown(() async {
    await cubit.close();
    sync.dispose();
    await db.close();
  });

  group('Today tiles', () {
    test('cig tap → event + outbox row; count updates at once', () async {
      await makeCubit();
      expect(cubit.state.summary.cigs, isNull); // "—", never 0
      await cubit.addCig();
      final s = await until(cubit, (s) => s.summary.cigs == 1);
      expect(s.undo!.text, 'Logged 1 cigarette · 18:02 · ₹25');
      final o = await outbox();
      expect(o, hasLength(1));
      final body = jsonDecode(o.single.payload) as Map<String, dynamic>;
      expect(body['type'], 'cigarette');
      expect(body['qty'], 1);
      expect(body['amount_inr'], 25);
      expect(body['category'], 'tobacco');
      expect(body['date'], '2026-11-17');
      expect(body['time'], '18:02');
    });

    test('tea and water tiles', () async {
      await makeCubit();
      await cubit.addTea();
      await cubit.addWater();
      await cubit.addWater();
      final s = await until(cubit, (s) => s.summary.waterMl == 500);
      expect(s.summary.teas, 1);
      expect(s.summary.spend, 20);
      expect(s.undo!.text, 'Logged 250 ml water · 18:02');
    });

    test('undo before sync: removed locally, nothing is posted', () async {
      await makeCubit();
      await cubit.addCig();
      await until(cubit, (s) => s.summary.cigs == 1);
      await cubit.undo();
      final s = await until(cubit, (s) => s.summary.cigs == null);
      expect(s.undo, isNull);
      expect(await outbox(), isEmpty);
      expect(await sync.flush(), FlushOutcome.empty);
      expect(server.posts, 0);
    });

    test('undo after sync: a void is posted for the id', () async {
      await makeCubit();
      await cubit.addCig();
      await until(cubit, (s) => s.summary.cigs == 1);
      final id = cubit.state.undo!.ids.single;
      expect(await sync.flush(), FlushOutcome.sent);
      await cubit.undo();
      await until(cubit, (s) => s.summary.cigs == null);
      expect(await sync.flush(), FlushOutcome.sent);
      final voidRow = server.events.singleWhere((r) => r['type'] == 'void');
      expect(voidRow['label'], id);
    });

    test('undo line disappears after its timeout', () async {
      await makeCubit(undoFor: const Duration(milliseconds: 40));
      await cubit.addTea();
      expect(cubit.state.undo, isNotNull);
      await tick(100);
      expect(cubit.state.undo, isNull);
    });

    test('cigarettes above budget turn warn', () async {
      await settings.save(const AppSettings(cigBudget: 1));
      await makeCubit();
      await cubit.addCig();
      await until(cubit, (s) => s.summary.cigs == 1);
      expect(cubit.state.overCigBudget, isFalse);
      await cubit.addCig();
      await until(cubit, (s) => s.summary.cigs == 2);
      expect(cubit.state.overCigBudget, isTrue);
    });

    test('supplement checklist: tick logs, untick undoes', () async {
      await settings.save(const AppSettings(supplements: ['D3', 'Omega 3']));
      await makeCubit();
      await until(cubit, (s) => s.settings.supplements.length == 2);
      await cubit.toggleSupplement('D3');
      await until(cubit, (s) => s.suppsTaken == 1);
      await cubit.toggleSupplement('D3');
      await until(cubit, (s) => s.suppsTaken == 0);
      expect(await outbox(), isEmpty);
    });
  });

  group('bus legs', () {
    test('Board → Arrived → Board home → Arrived → Done', () async {
      clock = FixedClock.ist(2026, 11, 17, 9, 20);
      await makeCubit();
      expect(cubit.state.busAction, BusAction.board);

      await cubit.busTap(); // board 09:20
      await until(cubit, (s) => s.commute.riding);
      expect(cubit.state.busAction, BusAction.arrive);

      clock.advance(const Duration(minutes: 80));
      await cubit.busTap(); // arrive 10:40
      var s = await until(cubit, (s) => s.commute.completedCount == 1);
      expect(s.commute.lastCompleted!.minutes, 80);
      expect(s.busAction, BusAction.board); // "Board home"

      clock.advance(const Duration(hours: 7, minutes: 22));
      await cubit.busTap(); // board 18:02
      await until(cubit, (s) => s.commute.riding);
      clock.advance(const Duration(minutes: 86));
      await cubit.busTap(); // arrive 19:28
      s = await until(cubit, (s) => s.commute.completedCount == 2);
      expect(s.commute.totalMinutes, 166);
      expect(s.busAction, BusAction.done);

      await cubit.busTap(); // Done: writes nothing
      await tick();
      final types = (await outbox())
          .map((o) => (jsonDecode(o.payload) as Map)['type'])
          .toList();
      expect(types, ['bus_board', 'bus_arrive', 'bus_board', 'bus_arrive']);
    });
  });

  group('cards', () {
    test('Day N, last night, spend today and this week', () async {
      await events.mergeServerRows([
        row('a', '2026-11-11', '10:00', 'tea', amount: '20'),
        row('b', '2026-11-16', '22:30', 'sleep', approx: 'TRUE'),
        row('c', '2026-11-17', '06:00', 'wake'),
        row('d', '2026-11-17', '13:00', 'spend', amount: '278'),
        row('dev-e', '2026-11-17', '13:05', 'spend', amount: '999'),
      ]);
      await makeCubit();
      final s = cubit.state;
      expect(s.dayN, 7);
      expect(s.night!.hours, 7.5);
      expect(s.night!.approx, isTrue);
      expect(s.summary.spend, 278); // dev row ignored
      expect(s.summary.spendEntries, 1);
      expect(s.weekSpend, 298);
      expect(s.daysLeft, 13);
      expect(s.lastEvent!.id, 'd');
    });

    test('no data at all: everything is null, not 0', () async {
      await makeCubit();
      final s = cubit.state;
      expect(s.dayN, isNull);
      expect(s.night, isNull);
      expect(s.weekSpend, isNull);
      expect(s.summary.spend, isNull);
      expect(s.everLogged, isEmpty);
    });
  });

  group('Phase 3 gate', () {
    test('5 mixed entries offline → reconnect → 5 dev- rows, once', () async {
      var n = 0;
      String devId() => '${devIdPrefix}phase3-${n++}';
      await makeCubit(idFactory: devId);
      server.offline = true;

      final ql = QuickLogCubit(
        events: events,
        settings: settings,
        clock: clock,
        idFactory: devId,
      );
      await tick();
      ql.setText('1 cig + tea 45, lunch 130, water 500 ml, weight 87.9');
      expect(ql.state.entries, hasLength(5));
      await cubit.logAll(ql.build());
      await ql.close();
      expect(cubit.state.undo!.text, 'Logged 5 entries · 18:02 · ₹175');

      // Offline: nothing leaves the phone.
      expect(await sync.flush(), FlushOutcome.failed);
      expect(await outbox(), hasLength(5));
      sync.cancelTimers();

      // Reconnect: all 5 go up in one POST.
      server.offline = false;
      expect(await sync.flush(), FlushOutcome.sent);
      expect(await outbox(), isEmpty);
      expect(server.events, hasLength(5));
      expect(
        server.events.every((r) => (r['id'] as String).startsWith('dev-')),
        isTrue,
      );
      expect(server.events.map((r) => r['type']), [
        'cigarette',
        'tea',
        'meal',
        'water_ml',
        'weight',
      ]);
      expect(server.events.map((r) => r['amount_inr']), [
        '25.0',
        '20.0',
        '130.0',
        '',
        '',
      ]);

      // A second flush and a refresh don't duplicate anything.
      expect(await sync.flush(), FlushOutcome.empty);
      await events.refresh();
      expect(server.events, hasLength(5));
      expect(server.posts, 1); // the offline try never reached the server
      expect((await events.all()).length, 5);
    });
  });
}
