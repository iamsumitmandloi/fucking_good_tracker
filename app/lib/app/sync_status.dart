import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/clock.dart';
import '../core/failure_text.dart';
import '../core/result.dart';
import '../data/local/db.dart';
import 'app_sync.dart';
import 'theme/app_theme.dart';

class SyncStatus extends Equatable {
  const SyncStatus({
    this.pending = 0,
    this.lastSyncAt,
    this.lastError,
    this.online = true,
    this.failure,
  });

  final int pending;
  final DateTime? lastSyncAt;
  final String? lastError;
  final bool online;
  final Failure? failure;

  SyncStatus copyWith({
    int? pending,
    DateTime? Function()? lastSyncAt,
    String? Function()? lastError,
    bool? online,
    Failure? Function()? failure,
  }) => SyncStatus(
    pending: pending ?? this.pending,
    lastSyncAt: lastSyncAt != null ? lastSyncAt() : this.lastSyncAt,
    lastError: lastError != null ? lastError() : this.lastError,
    online: online ?? this.online,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [pending, lastSyncAt, lastError, online, failure];
}

class SyncStatusCubit extends Cubit<SyncStatus> {
  SyncStatusCubit({required AppDatabase db, required AppSync appSync})
    : _appSync = appSync,
      super(const SyncStatus()) {
    _subs.addAll([
      db.watchOutboxCount().listen((n) => emit(state.copyWith(pending: n))),
      db
          .watchMeta(MetaKeys.lastSyncAt)
          .listen(
            (v) => emit(
              state.copyWith(
                lastSyncAt: () => v == null ? null : DateTime.tryParse(v),
              ),
            ),
          ),
      db
          .watchMeta(MetaKeys.lastError)
          .listen((v) => emit(state.copyWith(lastError: () => v))),
    ]);
    appSync.online.addListener(_onOnline);
    appSync.lastFailure.addListener(_onFailure);
    _onOnline();
  }

  final AppSync _appSync;
  final _subs = <StreamSubscription<Object?>>[];

  void _onOnline() => emit(state.copyWith(online: _appSync.online.value));
  void _onFailure() =>
      emit(state.copyWith(failure: () => _appSync.lastFailure.value));

  @override
  Future<void> close() async {
    _appSync.online.removeListener(_onOnline);
    _appSync.lastFailure.removeListener(_onFailure);
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}

/// "● Synced 17:58" (lime) or "● 3 pending" (orange). Tap → Settings.
class SyncDot extends StatelessWidget {
  const SyncDot({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncStatusCubit>().state;
    final c = context.colors;
    final synced = s.pending == 0;
    final String label;
    if (!synced) {
      label = '${s.pending} pending';
    } else if (s.lastSyncAt != null) {
      final ist = s.lastSyncAt!.toUtc().add(istOffset);
      label = 'Synced ${formatTime(ist)}';
    } else {
      label = 'Not synced yet';
    }
    return Semantics(
      button: true,
      label: '$label. Open settings',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.push('/settings'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: synced ? c.accent : c.warn,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: context.text.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown above content when offline or when the sheet rejects us.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncStatusCubit>().state;
    final c = context.colors;
    final f = s.failure;
    final String? text;
    if (f is UnauthorisedFailure || f is NotConfiguredFailure) {
      text = describeFailure(f!);
    } else if (!s.online) {
      text = s.pending > 0
          ? 'Offline · ${s.pending} saved, will sync when back'
          : 'Offline · showing saved data';
    } else if (f is ServerFailure || f is ParseFailure) {
      text = describeFailure(f!);
    } else {
      text = null;
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.warnWell,
        border: Border.all(color: c.warnBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: context.text.caption.copyWith(color: c.warn)),
    );
  }
}
