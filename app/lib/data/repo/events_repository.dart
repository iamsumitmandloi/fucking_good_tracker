import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';
import '../local/db.dart';
import '../remote/sheet_api.dart';

/// Cache-first access to events. The UI only ever reads from drift.
class EventsRepository {
  EventsRepository({
    required this._db,
    required this._api,
    required this._clock,
    this._onLocalWrite,
  });

  final AppDatabase _db;
  final SheetApi _api;
  final Clock _clock;
  void Function()? _onLocalWrite;

  /// Wired after construction to avoid a repo ↔ sync cycle.
  set onLocalWrite(void Function()? f) => _onLocalWrite = f;

  static Event toEvent(EventRow r) => Event(
    id: r.id,
    date: r.date,
    time: r.time,
    endTime: r.endTime,
    type: EventType.fromWire(r.type) ?? EventType.note,
    qty: r.qty,
    unit: r.unit,
    label: r.label,
    amountInr: r.amountInr,
    category: r.category,
    approx: r.approx,
    source: r.source,
    note: r.note,
    createdAt: r.createdAt,
  );

  static EventsCompanion _companion(Event e, {required bool synced}) =>
      EventsCompanion.insert(
        id: e.id,
        date: e.date,
        time: Value(e.time),
        endTime: Value(e.endTime),
        type: e.type.wire,
        qty: Value(e.qty),
        unit: Value(e.unit),
        label: Value(e.label),
        amountInr: Value(e.amountInr),
        category: Value(e.category),
        approx: Value(e.approx),
        source: Value(e.source),
        note: Value(e.note),
        createdAt: Value(e.createdAt),
        syncState: Value(synced ? 1 : 0),
      );

  /// Every event in `[from, to]` (inclusive, `yyyy-MM-dd`), including voids
  /// and dev rows. Run [effectiveEvents] before computing stats.
  Stream<List<Event>> watchRange(String from, String to) =>
      (_db.select(_db.events)..where((e) => e.date.isBetweenValues(from, to)))
          .watch()
          .map((rows) => rows.map(toEvent).toList()..sort(compareEvents));

  Stream<List<Event>> watchAll() => _db
      .select(_db.events)
      .watch()
      .map((rows) => rows.map(toEvent).toList()..sort(compareEvents));

  Future<List<Event>> all() async =>
      (await _db.select(_db.events).get()).map(toEvent).toList()
        ..sort(compareEvents);

  /// Ids still waiting for the server.
  Stream<Set<String>> watchPendingIds() =>
      _db.select(_db.outbox).watch().map((r) => {for (final o in r) o.id});

  /// Optimistic write: event + outbox row in one transaction.
  Future<void> log(List<Event> events) async {
    if (events.isEmpty) return;
    final now = _clock.nowUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final e in events) {
        await _db
            .into(_db.events)
            .insertOnConflictUpdate(_companion(e, synced: false));
        await _db
            .into(_db.outbox)
            .insertOnConflictUpdate(
              OutboxCompanion.insert(
                id: e.id,
                payload: jsonEncode(e.toJson()),
                enqueuedAt: now,
              ),
            );
      }
    });
    _onLocalWrite?.call();
  }

  /// Before sync: drop it locally. After sync: post a `void` event.
  /// Returns the void event when one was written.
  Future<Event?> undo(String id) async {
    final pending = await (_db.select(
      _db.outbox,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
    if (pending != null) {
      await _db.transaction(() async {
        await (_db.delete(_db.outbox)..where((o) => o.id.equals(id))).go();
        await (_db.delete(_db.events)..where((e) => e.id.equals(id))).go();
      });
      return null;
    }
    final now = _clock.nowIst();
    final v = Event(
      id: isDevId(id) ? '$devIdPrefix${newEventId()}' : newEventId(),
      date: formatDate(now),
      time: formatTime(now),
      type: EventType.voidEvent,
      label: id,
    );
    await log([v]);
    return v;
  }

  /// GET the Events tab and merge it into the cache.
  Future<Result<int>> refresh() async {
    final res = await _api.fetchTabs(const ['Events']);
    return switch (res) {
      Ok(:final value) => Ok(await mergeServerRows(value['Events'])),
      Err(:final failure) => Err(failure),
    };
  }

  /// Server rows win for synced data; pending local rows are kept.
  /// A pending row that already exists on the server is marked synced and
  /// leaves the outbox (its POST landed but the reply was lost).
  /// Returns the number of server rows applied.
  Future<int> mergeServerRows(List<SheetRow>? rows) async {
    if (rows == null) return 0; // tab absent: leave the cache alone.
    final server = [for (final r in rows) ?Event.fromSheetRow(r)];
    final serverIds = {for (final e in server) e.id};
    await _db.transaction(() async {
      for (final e in server) {
        await _db
            .into(_db.events)
            .insertOnConflictUpdate(_companion(e, synced: true));
      }
      if (serverIds.isNotEmpty) {
        await (_db.delete(_db.outbox)..where((o) => o.id.isIn(serverIds))).go();
      }
      // Synced rows that vanished from the sheet (e.g. deleted dev rows).
      await (_db.delete(
        _db.events,
      )..where((e) => e.syncState.equals(1) & e.id.isNotIn(serverIds))).go();
      await _db.writeMeta(
        MetaKeys.lastEventsRefresh,
        _clock.nowUtc().toIso8601String(),
      );
    });
    return server.length;
  }
}
