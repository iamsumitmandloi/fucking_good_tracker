import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../../domain/event.dart';
import '../local/db.dart';
import '../remote/sheet_api.dart';
import 'backoff.dart';

enum FlushOutcome { empty, sent, failed, busy, blocked }

/// Flushes the outbox. Triggers: app resume, connectivity regained,
/// pull-to-refresh, and [debounce] after the last local write.
/// Failures back off 2^n s up to 5 min. Idempotent by event id.
class SyncService {
  SyncService({
    required this._db,
    required this._api,
    required this._clock,
    this.debounce = const Duration(seconds: 10),
    this.batchSize = 50,
  });

  final AppDatabase _db;
  final SheetApi _api;
  final Clock _clock;
  final Duration debounce;
  final int batchSize;

  Timer? _debounceTimer;
  Timer? _retryTimer;
  int _attempt = 0;
  Future<FlushOutcome>? _inflight;

  /// Set when the server said "unauthorised". Cleared by [resetAuthBlock]
  /// (Settings saves a new token).
  bool _authBlocked = false;

  int get attempt => _attempt;
  bool get authBlocked => _authBlocked;
  bool get retryScheduled => _retryTimer?.isActive ?? false;

  /// Call after every local write.
  void scheduleFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(flush()));
  }

  /// Resume / connectivity regained / pull-to-refresh: flush now.
  Future<FlushOutcome> flushNow() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    return flush();
  }

  void resetAuthBlock() {
    _authBlocked = false;
    _attempt = 0;
  }

  Future<FlushOutcome> flush() {
    if (_inflight != null) return Future.value(FlushOutcome.busy);
    final f = _flush().whenComplete(() => _inflight = null);
    _inflight = f;
    return f;
  }

  Future<FlushOutcome> _flush() async {
    if (_authBlocked) return FlushOutcome.blocked;
    var sentAny = false;
    while (true) {
      final batch =
          await (_db.select(_db.outbox)
                ..orderBy([(o) => OrderingTerm.asc(o.enqueuedAt)])
                ..limit(batchSize))
              .get();
      if (batch.isEmpty) {
        _attempt = 0;
        if (sentAny) await _recordSuccess();
        return sentAny ? FlushOutcome.sent : FlushOutcome.empty;
      }
      final events = <Event>[];
      final badIds = <String>[];
      for (final row in batch) {
        final e = _decode(row.payload);
        e == null ? badIds.add(row.id) : events.add(e);
      }
      if (badIds.isNotEmpty) {
        // Corrupt payload can never succeed; drop it rather than block the queue.
        await (_db.delete(_db.outbox)..where((o) => o.id.isIn(badIds))).go();
      }
      if (events.isEmpty) continue;

      final res = await _api.postEvents(events);
      switch (res) {
        case Ok(:final value):
          final confirmed = value.confirmed;
          await _db.transaction(() async {
            await (_db.delete(
              _db.outbox,
            )..where((o) => o.id.isIn(confirmed))).go();
            await (_db.update(_db.events)..where((e) => e.id.isIn(confirmed)))
                .write(const EventsCompanion(syncState: Value(1)));
          });
          sentAny = true;
          final unconfirmed = events.where((e) => !confirmed.contains(e.id));
          if (unconfirmed.isNotEmpty) {
            // Server neither added nor skipped them: treat as a failure.
            await _recordFailure(
              const ServerFailure('server did not confirm all ids'),
              [for (final e in unconfirmed) e.id],
            );
            return FlushOutcome.failed;
          }
        case Err(:final failure):
          await _recordFailure(failure, [for (final e in events) e.id]);
          return FlushOutcome.failed;
      }
    }
  }

  Event? _decode(String payload) {
    try {
      final j = jsonDecode(payload);
      return j is Map<String, dynamic> ? Event.fromJson(j) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _recordSuccess() async {
    await _db.writeMeta(MetaKeys.lastSyncAt, _clock.nowUtc().toIso8601String());
    await _db.writeMeta(MetaKeys.lastError, null);
    await _log('sent');
  }

  Future<void> _recordFailure(Failure f, List<String> ids) async {
    await _db.transaction(() async {
      await _db.customUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_error = ? '
        'WHERE id IN (${List.filled(ids.length, '?').join(',')})',
        variables: [
          Variable.withString(f.message),
          for (final id in ids) Variable.withString(id),
        ],
        updates: {_db.outbox},
      );
      await _db.writeMeta(MetaKeys.lastError, f.message);
    });
    await _log('failed: ${f.message}');
    if (f is UnauthorisedFailure) {
      _authBlocked = true;
      return;
    }
    if (!f.retryable) return;
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(backoffFor(_attempt), () => unawaited(flush()));
  }

  /// Last 20 sync results for the Settings screen. Never contains the token.
  Future<void> _log(String msg) async {
    final raw = await _db.readMeta(MetaKeys.syncLog);
    final list = <String>[
      if (raw != null)
        for (final s in (jsonDecode(raw) as List)) s.toString(),
    ];
    list.insert(
      0,
      '${_clock.nowIst().toIso8601String().substring(0, 16)} $msg',
    );
    await _db.writeMeta(MetaKeys.syncLog, jsonEncode(list.take(20).toList()));
  }

  @visibleForTesting
  void cancelTimers() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
  }

  void dispose() => cancelTimers();
}
