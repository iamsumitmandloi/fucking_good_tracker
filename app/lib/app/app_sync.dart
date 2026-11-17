import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/result.dart';
import '../data/sync/sync_service.dart';

typedef Refresher = Future<Result<Object?>> Function();

/// Wires the sync triggers: app resume, connectivity regained,
/// pull-to-refresh. (The 10 s debounce lives in [SyncService].)
class AppSync {
  AppSync({required this.sync, required this.refreshers, this._connectivity});

  final SyncService sync;

  /// What to GET on resume / reconnect. Each fetches only its own tabs.
  final List<Refresher> refreshers;
  final Connectivity? _connectivity;

  final online = ValueNotifier<bool>(true);
  final lastFailure = ValueNotifier<Failure?>(null);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  AppLifecycleListener? _lifecycle;

  void start() {
    final conn = _connectivity;
    if (conn != null) {
      unawaited(
        conn.checkConnectivity().then(_onConnectivity, onError: (_) {}),
      );
      _sub = conn.onConnectivityChanged.listen(_onConnectivity);
    }
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(syncNow()));
    unawaited(syncNow());
  }

  void _onConnectivity(List<ConnectivityResult> r) {
    final on = r.any((x) => x != ConnectivityResult.none);
    final regained = on && !online.value;
    online.value = on;
    if (regained) unawaited(syncNow());
  }

  /// Flush first so a refresh never shows the server without our writes.
  Future<Failure?> syncNow([List<Refresher>? only]) async {
    await sync.flushNow();
    Failure? failure;
    for (final r in only ?? refreshers) {
      final res = await r();
      if (res case Err(failure: final f)) {
        failure ??= f;
        if (f is! NetworkFailure && f is! TimeoutFailure) break;
      }
    }
    lastFailure.value = failure;
    if (failure is NetworkFailure) online.value = false;
    if (failure == null) online.value = true;
    return failure;
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _lifecycle?.dispose();
    sync.dispose();
  }
}
