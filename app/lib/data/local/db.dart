import 'package:drift/drift.dart';

part 'db.g.dart';

/// Local copy of the `Events` tab plus rows not yet sent.
@DataClassName('EventRow')
class Events extends Table {
  TextColumn get id => text()();
  TextColumn get date => text()();
  TextColumn get time => text().nullable()();
  TextColumn get endTime => text().nullable()();
  TextColumn get type => text()();
  RealColumn get qty => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get label => text().nullable()();
  RealColumn get amountInr => real().nullable()();
  TextColumn get category => text().nullable()();
  BoolColumn get approx => boolean().withDefault(const Constant(false))();
  TextColumn get source => text().withDefault(const Constant('app'))();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text().nullable()();

  /// 0 = pending (in outbox), 1 = confirmed on the server.
  IntColumn get syncState => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One row per event waiting to be POSTed. Keyed by event id (idempotent).
@DataClassName('OutboxRow')
class Outbox extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  IntColumn get enqueuedAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Study Bank rows, stored whole (headers may change; parsing is in domain).
@DataClassName('StudyBankRow')
class StudyBank extends Table {
  TextColumn get questionId => text()();
  IntColumn get row => integer()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {questionId};
}

/// `Start Here` key/value pairs.
@DataClassName('StartHereRow')
class StartHereTable extends Table {
  @override
  String get tableName => 'start_here';

  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get row => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Read-only legacy tabs (`Daily Summary`, `Timeline`, `Spending`).
@DataClassName('LegacyRow')
class LegacyRows extends Table {
  TextColumn get tab => text()();
  IntColumn get row => integer()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {tab, row};
}

/// Settings, last sync time, last error.
@DataClassName('MetaRow')
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [Events, Outbox, StudyBank, StartHereTable, LegacyRows, Meta],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  // ---- meta ----

  Future<String?> readMeta(String key) async => (await (select(
    meta,
  )..where((m) => m.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchMeta(String key) => (select(
    meta,
  )..where((m) => m.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> writeMeta(String key, String? value) async {
    if (value == null) {
      await (delete(meta)..where((m) => m.key.equals(key))).go();
    } else {
      await into(meta)
          .insertOnConflictUpdate(MetaCompanion.insert(key: key, value: value));
    }
  }

  Stream<int> watchOutboxCount() {
    final c = outbox.id.count();
    return (selectOnly(
      outbox,
    )..addColumns([c])).map((r) => r.read(c) ?? 0).watchSingle();
  }
}

abstract final class MetaKeys {
  static const lastSyncAt = 'last_sync_at';
  static const lastError = 'last_error';
  static const lastEventsRefresh = 'last_events_refresh';
  static const lastStudyRefresh = 'last_study_refresh';
  static const lastLegacyRefresh = 'last_legacy_refresh';
  static const settings = 'settings';
  static const syncLog = 'sync_log';
}
