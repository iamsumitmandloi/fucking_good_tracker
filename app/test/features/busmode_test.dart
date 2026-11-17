import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/core/ids.dart';
import 'package:starting_again/data/local/db.dart';
import 'package:starting_again/data/repo/events_repository.dart';
import 'package:starting_again/data/repo/settings_repository.dart';
import 'package:starting_again/data/repo/study_repository.dart';
import 'package:starting_again/data/sync/sync_service.dart';
import 'package:starting_again/domain/derivations/leitner.dart';
import 'package:starting_again/domain/effective_events.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/features/busmode/busmode_cubit.dart';

import '../support/app_harness.dart';
import '../support/fake_sheet_server.dart';
import '../support/study_fixtures.dart';

void main() {
  group('Phase 2 gate: Bus mode offline → reconnect', () {
    late FakeSheetServer server;
    late AppDatabase db;
    late EventsRepository events;
    late StudyRepository study;
    late SettingsRepository settings;
    late SyncService sync;

    setUp(() async {
      server = FakeSheetServer(
        tabs: {
          'Events': [],
          'Study Bank': studyBankRows(),
          'Start Here': startHereRows(),
        },
      );
      db = memoryDb();
      final api = server.api();
      final clock = testClock();
      events = EventsRepository(db: db, api: api, clock: clock);
      study = StudyRepository(db: db, api: api, events: events, clock: clock);
      settings = SettingsRepository(db);
      sync = SyncService(db: db, api: api, clock: clock);
      await settings.save(const AppSettings(busRunSize: 3));
      await study.refresh(); // online once: bank cached on the phone
    });

    tearDown(() async {
      sync.dispose();
      await db.close();
    });

    test(
      '3 cards rated in airplane mode → exactly 3 dev- study rows',
      () async {
        server.offline = true;
        var n = 0;
        final cubit = BusModeCubit(
          events: events,
          study: study,
          settings: settings,
          clock: testClock(),
          idFactory: () => 'dev-bus-${n++}',
        );
        await cubit.start();
        expect(cubit.state.status, BusStatus.running);
        expect(cubit.state.cards.map((c) => c.id), ['D1.1', 'D2.1', 'D3.1']);

        for (final r in [Rating.nailed, Rating.shaky, Rating.blank]) {
          cubit.reveal();
          await cubit.rate(r);
        }
        expect(cubit.state.status, BusStatus.done);
        expect(cubit.state.count(Rating.nailed), 1);

        // Still offline: the flush fails, rows wait in the outbox.
        expect(await sync.flush(), FlushOutcome.failed);
        expect((await db.select(db.outbox).get()).length, 3);
        sync.cancelTimers();

        // Reconnect.
        server.offline = false;
        expect(await sync.flushNow(), FlushOutcome.sent);
        expect(await sync.flushNow(), FlushOutcome.empty);

        expect(server.events, hasLength(3));
        for (final row in server.events) {
          expect(row['type'], 'study');
          expect(isDevId(row['id'] as String), isTrue);
        }
        expect(server.events.map((r) => r['note']), [
          'nailed',
          'shaky',
          'blank',
        ]);
        expect(server.events.map((r) => r['label']), ['D1.1', 'D2.1', 'D3.1']);

        // dev- ratings never count toward real progress.
        final effective = effectiveEvents(await events.all());
        expect(leitnerStates(effective), isEmpty);
        await cubit.close();
      },
    );

    test('exit mid-run keeps the cards already rated', () async {
      final cubit = BusModeCubit(
        events: events,
        study: study,
        settings: settings,
        clock: testClock(),
      );
      await cubit.start();
      cubit.reveal();
      await cubit.rate(Rating.blank);
      await cubit.close(); // user taps X

      final rows = await events.all();
      expect(rows.single.label, 'D1.1');
      expect(rows.single.note, 'blank');

      // Next run skips it (due tomorrow).
      final again = BusModeCubit(
        events: events,
        study: study,
        settings: settings,
        clock: testClock(),
      );
      await again.start();
      expect(again.state.cards.first.id, 'D2.1');
      await again.close();
    });

    test('empty bank → empty status, nothing written', () async {
      await db.delete(db.studyBank).go();
      final cubit = BusModeCubit(
        events: events,
        study: study,
        settings: settings,
        clock: testClock(),
      );
      await cubit.start();
      expect(cubit.state.status, BusStatus.empty);
      expect(cubit.state.bankEmpty, isTrue);
      await cubit.close();
    });
  });

  testWidgets('Bus mode widget: reveal → rate → next card', (tester) async {
    final h = await AppHarness.create(
      tabs: {
        'Events': [],
        'Study Bank': studyBankRows(),
        'Start Here': startHereRows(),
      },
    );
    await tester.runAsync(() async {
      await h.deps.settings.save(const AppSettings(busRunSize: 2));
      await h.deps.study.refresh();
    });
    await h.pump(tester, '/bus');

    expect(find.text('Question number 0?'), findsOneWidget);
    expect(find.text('card 1 of 2'), findsOneWidget);
    expect(find.text('Point A0'), findsNothing);

    await tester.tap(find.text('Say it out loud, then reveal'));
    await tester.pumpAndSettle();
    expect(find.text('Point A0'), findsOneWidget);

    await tester.tap(find.text('Nailed it'));
    await h.settle(tester);
    expect(find.text('Question number 1?'), findsOneWidget);
    expect(find.text('card 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Say it out loud, then reveal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank'));
    await h.settle(tester);
    expect(find.text('2 cards done.'), findsOneWidget);

    final rows = await tester.runAsync(h.deps.events.all);
    expect(rows!.map((e) => e.note), ['nailed', 'blank']);
    await h.dispose(tester);
  });

  testWidgets('Study tab shows countdown, assessed and pace from cache', (
    tester,
  ) async {
    final h = await AppHarness.create(
      tabs: {
        'Events': [],
        'Study Bank': studyBankRows(t1: 198, t2: 303),
        'Start Here': startHereRows(),
      },
    );
    await tester.runAsync(h.deps.study.refresh);
    await h.pump(tester, '/study');

    expect(find.text('Study'), findsWidgets);
    expect(find.text('13'), findsOneWidget); // days left to 30 Nov
    expect(find.text('0/198'), findsOneWidget);
    expect(find.text('16/day'), findsOneWidget);
    expect(find.textContaining('Platform channels deep dive'), findsNothing);
    expect(
      find.text('Topic 0'),
      findsOneWidget,
    ); // focus D1.1 resolved via bank
    expect(find.text('Start 25-min session'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await h.dispose(tester);
  });
}
