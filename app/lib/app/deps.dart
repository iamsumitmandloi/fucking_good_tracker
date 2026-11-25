import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/clock.dart';
import '../data/local/db.dart';
import '../data/remote/sheet_api.dart';
import '../data/remote/sheet_config.dart';
import '../data/repo/events_repository.dart';
import '../data/repo/legacy_repository.dart';
import '../data/repo/settings_repository.dart';
import '../data/repo/study_repository.dart';
import '../data/sync/sync_service.dart';
import '../data/voice/sherpa_stt_engine.dart';
import '../data/voice/voice_model_store.dart';
import '../domain/voice/voice_contracts.dart';
import '../domain/voice/voice_draft.dart';
import 'app_sync.dart';

/// Everything the widget tree needs, built once at startup.
class AppDeps {
  AppDeps._({
    required this.clock,
    required this.db,
    required this.config,
    required this.api,
    required this.sync,
    required this.events,
    required this.study,
    required this.legacy,
    required this.settings,
    required this.appSync,
    required this.voiceModels,
    required this.createSttEngine,
    required this.voiceDraftParser,
  });

  final Clock clock;
  final AppDatabase db;
  final SheetConfigStore config;
  final SheetApi api;
  final SyncService sync;
  final EventsRepository events;
  final StudyRepository study;
  final LegacyRepository legacy;
  final SettingsRepository settings;
  final AppSync appSync;
  final VoiceModelRepository voiceModels;
  final SttEngine Function() createSttEngine;
  final VoiceDraftParser voiceDraftParser;

  static Future<AppDeps> create({
    Clock clock = const SystemClock(),
    AppDatabase? db,
    SheetConfigStore? config,
    http.Client? client,
    Connectivity? connectivity,
    bool startSync = true,
    VoiceModelRepository? voiceModels,
    SttEngine Function()? createSttEngine,
    VoiceDraftParser voiceDraftParser = const VoiceDraftBuilder(),
  }) async {
    final database = db ?? AppDatabase(driftDatabase(name: 'starting_again'));
    final cfg = config ?? SecureSheetConfigStore();
    await cfg.seedFromEnvironment();
    final api = SheetApi(client: client ?? http.Client(), config: cfg);
    final sync = SyncService(db: database, api: api, clock: clock);
    final events = EventsRepository(db: database, api: api, clock: clock)
      ..onLocalWrite = sync.scheduleFlush;
    final study = StudyRepository(
      db: database,
      api: api,
      events: events,
      clock: clock,
    );
    final legacy = LegacyRepository(db: database, api: api, clock: clock);
    final appSync = AppSync(
      sync: sync,
      // Resume / reconnect refresh: Events only. Study and legacy tabs are
      // refreshed by their screens (pull-to-refresh or when stale).
      refreshers: [events.refresh],
      connectivity: connectivity,
    );
    final deps = AppDeps._(
      clock: clock,
      db: database,
      config: cfg,
      api: api,
      sync: sync,
      events: events,
      study: study,
      legacy: legacy,
      settings: SettingsRepository(database),
      appSync: appSync,
      voiceModels:
          voiceModels ??
          VoiceModelStore(dirProvider: getApplicationDocumentsDirectory),
      createSttEngine: createSttEngine ?? SherpaSttEngine.new,
      voiceDraftParser: voiceDraftParser,
    );
    if (startSync) appSync.start();
    return deps;
  }

  Future<void> dispose() async {
    appSync.dispose();
    await db.close();
  }
}
