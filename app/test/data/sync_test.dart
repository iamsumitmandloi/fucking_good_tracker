import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/core/feature_flags.dart';
import 'package:starting_again/core/result.dart';
import 'package:starting_again/data/local/db.dart';
import 'package:starting_again/data/repo/events_repository.dart';
import 'package:starting_again/data/sync/backoff.dart';
import 'package:starting_again/data/sync/sync_service.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';

import '../support/fake_sheet_server.dart';

Event ev(String id, {EventType type = EventType.note}) =>
    Event(id: id, date: '2026-11-17', time: '18:02', type: type);

void main() {
  // Exercises the write paths, which Phase 7 keeps behind the flag.
  setUpAll(() => FeatureFlags.logging = true);
  tearDownAll(() => FeatureFlags.logging = false);

  late FakeSheetServer server;
  late AppDatabase db;
  late EventsRepository repo;
  late SyncService sync;

  setUp(() {
    server = FakeSheetServer();
    db = memoryDb();
    final api = server.api();
    final clock = testClock();
    sync = SyncService(db: db, api: api, clock: clock);
    repo = EventsRepository(db: db, api: api, clock: clock);
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  Future<int> outboxCount() async => (await db.select(db.outbox).get()).length;

  test('log writes event + outbox row; flush sends and clears', () async {
    await repo.log([ev('dev-1'), ev('dev-2')]);
    expect(await outboxCount(), 2);
    expect((await repo.all()).length, 2);

    expect(await sync.flush(), FlushOutcome.sent);

    expect(await outboxCount(), 0);
    expect(server.events.map((r) => r['id']), ['dev-1', 'dev-2']);
    final rows = await db.select(db.events).get();
    expect(rows.every((r) => r.syncState == 1), isTrue);
    expect(await db.readMeta(MetaKeys.lastSyncAt), isNotNull);
  });

  test('offline: rows stay queued, attempts counted, then sent once', () async {
    server.offline = true;
    await repo.log([ev('dev-1')]);
    expect(await sync.flush(), FlushOutcome.failed);
    expect(await outboxCount(), 1);
    final row = await db.select(db.outbox).getSingle();
    expect(row.attempts, 1);
    expect(row.lastError, 'offline');
    expect(sync.attempt, 1);
    sync.cancelTimers();

    server.offline = false;
    expect(await sync.flushNow(), FlushOutcome.sent);
    expect(await outboxCount(), 0);
    expect(server.events, hasLength(1));
    expect(sync.attempt, 0);
  });

  test('re-sending an id the server already has is a success', () async {
    await repo.log([ev('dev-1')]);
    await sync.flush();
    // Simulate a lost reply: same id queued again.
    await repo.log([ev('dev-1')]);
    expect(await sync.flush(), FlushOutcome.sent);
    expect(server.events, hasLength(1));
    expect(await outboxCount(), 0);
  });

  test('unauthorised blocks retries until reset', () async {
    final s2 = SyncService(
      db: db,
      api: server.api(token: 'wrong'),
      clock: testClock(),
    );
    await repo.log([ev('dev-1')]);
    expect(await s2.flush(), FlushOutcome.failed);
    expect(s2.authBlocked, isTrue);
    expect(s2.retryScheduled, isFalse);
    expect(await s2.flush(), FlushOutcome.blocked);
    s2.dispose();
  });

  test('backoff doubles and caps at 5 minutes', () {
    expect(backoffFor(1), const Duration(seconds: 2));
    expect(backoffFor(2), const Duration(seconds: 4));
    expect(backoffFor(5), const Duration(seconds: 32));
    expect(backoffFor(8), const Duration(seconds: 256));
    expect(backoffFor(9), const Duration(minutes: 5));
    expect(backoffFor(40), const Duration(minutes: 5));
  });

  test(
    'debounce: flush fires 10 s after the last write, retries on failure',
    () {
      fakeAsync((fa) {
        final s = SyncService(db: db, api: server.api(), clock: testClock());
        repo.onLocalWrite = s.scheduleFlush;
        server.offline = true;

        repo.log([ev('dev-1')]);
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 5));
        repo.log([ev('dev-2')]); // restarts the 10 s window
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 9));
        expect(server.posts + server.requested.length, 0);
        fa.elapse(const Duration(seconds: 2));
        fa.flushMicrotasks();
        expect(server.requested, hasLength(1)); // failed, offline
        expect(s.retryScheduled, isTrue);

        server.offline = false;
        fa.elapse(const Duration(seconds: 3)); // 2 s backoff
        fa.flushMicrotasks();
        expect(server.events.map((r) => r['id']), ['dev-1', 'dev-2']);
        s.dispose();
      });
    },
  );

  group('undo', () {
    test(
      'before sync: removed from outbox and cache, nothing posted',
      () async {
        await repo.log([ev('dev-1', type: EventType.cigarette)]);
        final v = await repo.undo('dev-1');
        expect(v, isNull);
        expect(await outboxCount(), 0);
        expect(await repo.all(), isEmpty);
        expect(await sync.flush(), FlushOutcome.empty);
        expect(server.posts, 0);
      },
    );

    test('after sync: posts a void event pointing at the id', () async {
      await repo.log([ev('dev-1', type: EventType.cigarette)]);
      await sync.flush();
      final v = await repo.undo('dev-1');
      expect(v!.type, EventType.voidEvent);
      expect(v.label, 'dev-1');
      expect(v.id, startsWith('dev-')); // dev rows stay deletable
      await sync.flush();
      expect(server.events.last['type'], 'void');
      expect(server.events.last['label'], 'dev-1');
    });
  });

  group('refresh merge', () {
    test('server rows land as synced; pending local rows survive', () async {
      server.events.add({
        '_row': 2,
        'id': 'srv-1',
        'date': '2026-11-17',
        'type': 'tea',
        'approx': 'FALSE',
      });
      server.offline = true;
      await repo.log([ev('dev-local')]);
      server.offline = false;

      final res = await repo.refresh();
      expect(res, isA<Ok<int>>());
      final ids = (await repo.all()).map((e) => e.id).toSet();
      expect(ids, {'srv-1', 'dev-local'});
      expect(await outboxCount(), 1);
    });

    test('pending row already on the server leaves the outbox', () async {
      await repo.log([ev('dev-1')]);
      server.events.add({'id': 'dev-1', 'date': '2026-11-17', 'type': 'note'});
      await repo.refresh();
      expect(await outboxCount(), 0);
    });

    test('synced rows deleted on the sheet disappear locally', () async {
      await repo.log([ev('dev-1')]);
      await sync.flush();
      server.events.clear();
      await repo.refresh();
      expect(await repo.all(), isEmpty);
    });

    test('Events tab absent → cache untouched', () async {
      await repo.log([ev('dev-1')]);
      await sync.flush();
      server.tabs.remove('Events');
      await repo.refresh();
      expect((await repo.all()).single.id, 'dev-1');
    });
  });
}
