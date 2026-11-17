import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../../domain/start_here.dart';
import '../../domain/study_question.dart';
import '../local/db.dart';
import 'events_repository.dart';
import '../remote/sheet_api.dart';

class StudyRepository {
  StudyRepository({
    required this._db,
    required this._api,
    required this._events,
    required this._clock,
  });

  final AppDatabase _db;
  final SheetApi _api;
  final EventsRepository _events;
  final Clock _clock;

  static const tabs = ['Study Bank', 'Start Here', 'Events'];

  Stream<List<StudyQuestion>> watchBank() =>
      (_db.select(_db.studyBank)..orderBy([(q) => OrderingTerm.asc(q.row)]))
          .watch()
          .map((rows) => [for (final r in rows) ?_decode(r.json)]);

  Stream<StartHere> watchStartHere() =>
      (_db.select(_db.startHereTable)
            ..orderBy([(s) => OrderingTerm.asc(s.row)]))
          .watch()
          .map((rows) => StartHere({for (final r in rows) r.key: r.value}));

  StudyQuestion? _decode(String json) {
    try {
      final j = jsonDecode(json);
      return j is Map<String, dynamic> ? StudyQuestion.fromRow(j) : null;
    } on FormatException {
      return null;
    }
  }

  /// One GET for the three tabs the Study and Bus screens need.
  Future<Result<void>> refresh() async {
    final res = await _api.fetchTabs(tabs);
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        await applyTabs(value);
        return const Ok(null);
    }
  }

  Future<void> applyTabs(SheetTabs tabs) async {
    final bank = tabs['Study Bank'];
    final start = tabs['Start Here'];
    await _db.transaction(() async {
      if (bank != null && bank.isNotEmpty) {
        await _db.delete(_db.studyBank).go();
        final seen = <String>{};
        for (final r in bank) {
          final q = StudyQuestion.fromRow(r);
          if (q == null || !seen.add(q.id)) continue;
          await _db
              .into(_db.studyBank)
              .insert(
                StudyBankCompanion.insert(
                  questionId: q.id,
                  row: q.row,
                  json: jsonEncode(r),
                ),
              );
        }
      }
      if (start != null && start.isNotEmpty) {
        await _db.delete(_db.startHereTable).go();
        var i = 0;
        for (final p in startHerePairs(start)) {
          await _db
              .into(_db.startHereTable)
              .insertOnConflictUpdate(
                StartHereTableCompanion.insert(
                  key: p.key,
                  value: p.value,
                  row: i++,
                ),
              );
        }
      }
      await _db.writeMeta(
        MetaKeys.lastStudyRefresh,
        _clock.nowUtc().toIso8601String(),
      );
    });
    await _events.mergeServerRows(tabs['Events']);
  }
}
