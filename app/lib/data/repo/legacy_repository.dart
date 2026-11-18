import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../local/db.dart';
import '../remote/sheet_api.dart';

/// Read-only cache of the pre-Events tabs (PRD §6.4). Never written back.
class LegacyRepository {
  LegacyRepository({
    required this._db,
    required this._api,
    required this._clock,
  });

  final AppDatabase _db;
  final SheetApi _api;
  final Clock _clock;

  // Timeline is not read: Daily Summary has the sleep times and Timeline
  // carries no costs (checked on the live sheet, DECISIONS 32).
  static const tabs = ['Daily Summary', 'Spending'];

  /// Legacy data is history; refetch at most every 12 h unless forced.
  static const staleAfter = Duration(hours: 12);

  /// Rows per tab, in sheet order.
  Stream<Map<String, List<Map<String, dynamic>>>> watchRows() =>
      (_db.select(_db.legacyRows)..orderBy([
            (r) => OrderingTerm.asc(r.tab),
            (r) => OrderingTerm.asc(r.row),
          ]))
          .watch()
          .map((rows) {
            final out = <String, List<Map<String, dynamic>>>{};
            for (final r in rows) {
              final j = _decode(r.json);
              if (j != null) (out[r.tab] ??= []).add(j);
            }
            return out;
          });

  Map<String, dynamic>? _decode(String s) {
    try {
      final j = jsonDecode(s);
      return j is Map<String, dynamic> ? j : null;
    } on FormatException {
      return null;
    }
  }

  Future<Result<void>> refresh({bool force = false}) async {
    if (!force) {
      final last = DateTime.tryParse(
        await _db.readMeta(MetaKeys.lastLegacyRefresh) ?? '',
      );
      if (last != null && _clock.nowUtc().difference(last) < staleAfter) {
        return const Ok(null);
      }
    }
    final res = await _api.fetchTabs(tabs);
    switch (res) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        await applyTabs(value);
        return const Ok(null);
    }
  }

  Future<void> applyTabs(SheetTabs tabsData) async {
    await _db.transaction(() async {
      for (final name in tabs) {
        final rows = tabsData[name];
        if (rows == null) continue;
        await (_db.delete(
          _db.legacyRows,
        )..where((r) => r.tab.equals(name))).go();
        var i = 0;
        for (final r in rows) {
          final rowNum = r['_row'] is int ? r['_row'] as int : i + 2;
          i++;
          await _db
              .into(_db.legacyRows)
              .insertOnConflictUpdate(
                LegacyRowsCompanion.insert(
                  tab: name,
                  row: rowNum,
                  json: jsonEncode(r),
                ),
              );
        }
      }
      await _db.writeMeta(
        MetaKeys.lastLegacyRefresh,
        _clock.nowUtc().toIso8601String(),
      );
    });
  }
}
