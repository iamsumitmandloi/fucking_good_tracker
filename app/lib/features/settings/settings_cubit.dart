import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/deps.dart';
import '../../core/failure_text.dart';
import '../../core/result.dart';
import '../../data/local/db.dart';
import '../../data/remote/sheet_config.dart';
import '../../data/repo/settings_repository.dart';

enum TestStatus { idle, running, ok, failed }

class SettingsState extends Equatable {
  const SettingsState({
    this.url = '',
    this.hasToken = false,
    this.settings = const AppSettings(),
    this.test = TestStatus.idle,
    this.testMessage,
    this.log = const [],
  });

  final String url;
  final bool hasToken;
  final AppSettings settings;
  final TestStatus test;
  final String? testMessage;
  final List<String> log;

  SettingsState copyWith({
    String? url,
    bool? hasToken,
    AppSettings? settings,
    TestStatus? test,
    String? Function()? testMessage,
    List<String>? log,
  }) => SettingsState(
    url: url ?? this.url,
    hasToken: hasToken ?? this.hasToken,
    settings: settings ?? this.settings,
    test: test ?? this.test,
    testMessage: testMessage != null ? testMessage() : this.testMessage,
    log: log ?? this.log,
  );

  @override
  List<Object?> get props => [url, hasToken, settings, test, testMessage, log];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._deps) : super(const SettingsState()) {
    _subs.add(
      _deps.settings.watch().listen((s) => emit(state.copyWith(settings: s))),
    );
    _subs.add(
      _deps.db.watchMeta(MetaKeys.syncLog).listen((raw) {
        final list = <String>[];
        if (raw != null) {
          try {
            list.addAll([
              for (final s in jsonDecode(raw) as List) s.toString(),
            ]);
          } on Object {
            // ignore a corrupt log
          }
        }
        emit(state.copyWith(log: list));
      }),
    );
    unawaited(_loadConfig());
  }

  final AppDeps _deps;
  final _subs = <StreamSubscription<Object?>>[];

  Future<void> _loadConfig() async {
    final cfg = await _deps.config.load();
    if (isClosed) return;
    emit(
      state.copyWith(
        url: cfg?.url ?? '',
        hasToken: (cfg?.token ?? '').isNotEmpty,
      ),
    );
  }

  /// [token] null or empty keeps the stored token.
  Future<void> saveConnection({required String url, String? token}) async {
    final current = await _deps.config.load();
    final newToken = (token == null || token.trim().isEmpty)
        ? (current?.token ?? '')
        : token.trim();
    await _deps.config.save(SheetConfig(url: url.trim(), token: newToken));
    _deps.sync.resetAuthBlock();
    emit(
      state.copyWith(
        url: url.trim(),
        hasToken: newToken.isNotEmpty,
        test: TestStatus.idle,
        testMessage: () => null,
      ),
    );
  }

  Future<void> testConnection() async {
    emit(state.copyWith(test: TestStatus.running, testMessage: () => null));
    final res = await _deps.api.fetchTabs(const ['Start Here']);
    if (isClosed) return;
    switch (res) {
      case Ok(:final value):
        final rows = value['Start Here']?.length;
        emit(
          state.copyWith(
            test: TestStatus.ok,
            testMessage: () => rows == null
                ? 'Connected. No "Start Here" tab found.'
                : 'Connected. Start Here has $rows rows.',
          ),
        );
        unawaited(_deps.appSync.syncNow());
      case Err(:final failure):
        emit(
          state.copyWith(
            test: TestStatus.failed,
            testMessage: () => describeFailure(failure),
          ),
        );
    }
  }

  Future<void> syncNow() => _deps.appSync.syncNow();

  Future<void> update(AppSettings s) => _deps.settings.save(s);

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
