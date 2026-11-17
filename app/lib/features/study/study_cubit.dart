import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../../data/local/db.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../data/repo/study_repository.dart';
import '../../domain/derivations/leitner.dart';
import '../../domain/derivations/study_progress.dart';
import '../../domain/effective_events.dart';
import '../../domain/event.dart';
import '../../domain/focus.dart';
import '../../domain/start_here.dart';
import '../../domain/study_question.dart';

class StudyState extends Equatable {
  const StudyState({
    this.loaded = false,
    this.bank = const [],
    this.focus = const FocusInfo(),
    this.progress,
    this.dueToday = 0,
    this.targetDate = '2026-11-30',
    this.refreshing = false,
    this.failure,
  });

  final bool loaded;
  final List<StudyQuestion> bank;
  final FocusInfo focus;
  final StudyProgress? progress;
  final int dueToday;
  final String targetDate;
  final bool refreshing;
  final Failure? failure;

  StudyState copyWith({
    bool? loaded,
    List<StudyQuestion>? bank,
    FocusInfo? focus,
    StudyProgress? progress,
    int? dueToday,
    String? targetDate,
    bool? refreshing,
    Failure? Function()? failure,
  }) => StudyState(
    loaded: loaded ?? this.loaded,
    bank: bank ?? this.bank,
    focus: focus ?? this.focus,
    progress: progress ?? this.progress,
    dueToday: dueToday ?? this.dueToday,
    targetDate: targetDate ?? this.targetDate,
    refreshing: refreshing ?? this.refreshing,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [
    loaded,
    bank,
    focus.questionId,
    focus.focusText,
    focus.nextAction,
    progress,
    dueToday,
    targetDate,
    refreshing,
    failure,
  ];
}

class StudyCubit extends Cubit<StudyState> {
  StudyCubit({
    required this._study,
    required this._events,
    required this._settings,
    required this._clock,
    required this._db,
  }) : super(const StudyState()) {
    _sub =
        combineLatest([
          _study.watchBank(),
          _study.watchStartHere(),
          _events.watchAll(),
          _settings.watch(),
        ]).listen((v) {
          final bank = v[0]! as List<StudyQuestion>;
          final sh = v[1]! as StartHere;
          final effective = effectiveEvents(v[2]! as List<Event>);
          final settings = v[3]! as AppSettings;
          final today = _clock.todayIst();
          final target = settings.targetDate;
          emit(
            state.copyWith(
              loaded: true,
              bank: bank,
              focus: FocusInfo.resolve(sh, bank),
              targetDate: target,
              progress: computeStudyProgress(
                bank: bank,
                effective: effective,
                today: today,
                targetDate: target,
              ),
              dueToday: busQueue(
                bank: bank,
                states: leitnerStates(effective),
                today: today,
              ).length,
            ),
          );
        });
    unawaited(_refreshIfStale());
  }

  final StudyRepository _study;
  final EventsRepository _events;
  final SettingsRepository _settings;
  final Clock _clock;
  final AppDatabase _db;
  StreamSubscription<List<Object?>>? _sub;

  static const staleAfter = Duration(hours: 6);

  Future<void> _refreshIfStale() async {
    final last = DateTime.tryParse(
      await _db.readMeta(MetaKeys.lastStudyRefresh) ?? '',
    );
    if (last == null || _clock.nowUtc().difference(last) > staleAfter) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    if (isClosed) return;
    emit(state.copyWith(refreshing: true));
    final res = await _study.refresh();
    if (isClosed) return;
    emit(
      state.copyWith(
        refreshing: false,
        failure: () => res is Err<void> ? res.failure : null,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
