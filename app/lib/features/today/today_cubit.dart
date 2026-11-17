import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/streams.dart';
import '../../data/local/db.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../data/repo/study_repository.dart';
import '../../domain/derivations/commute.dart';
import '../../domain/derivations/daily_stats.dart';
import '../../domain/derivations/sleep.dart';
import '../../domain/effective_events.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';
import '../../domain/focus.dart';
import '../../domain/quicklog/build_events.dart';
import '../../domain/start_here.dart';
import '../../domain/study_question.dart';

/// The 6 s "Logged … · Undo" line.
class UndoInfo extends Equatable {
  const UndoInfo({required this.ids, required this.text});

  final List<String> ids;
  final String text;

  @override
  List<Object?> get props => [ids, text];
}

/// What the bus button does next.
enum BusAction { board, arrive, done }

class TodayState extends Equatable {
  const TodayState({
    this.loaded = false,
    this.today = '',
    this.dayN,
    this.summary = const DaySummary(date: ''),
    this.yesterday = const DaySummary(date: ''),
    this.todayEvents = const [],
    this.commute = const CommuteDay([]),
    this.night,
    this.weekSpend,
    this.everLogged = const {},
    this.everProtein = false,
    this.focus = const FocusInfo(),
    this.daysLeft,
    this.settings = const AppSettings(),
    this.undo,
  });

  final bool loaded;
  final String today;

  /// Days since the first logged date (11 Nov = Day 1). Null with no data.
  final int? dayN;
  final DaySummary summary;
  final DaySummary yesterday;

  /// Today's effective events, oldest first.
  final List<Event> todayEvents;
  final CommuteDay commute;

  /// The night that ended this morning.
  final SleepWindow? night;
  final double? weekSpend;

  /// Types logged at least once, ever (a dashed tile means "never").
  final Set<EventType> everLogged;
  final bool everProtein;
  final FocusInfo focus;
  final int? daysLeft;
  final AppSettings settings;
  final UndoInfo? undo;

  bool get overCigBudget => (summary.cigs ?? 0) > settings.cigBudget;

  Event? get lastEvent => todayEvents.isEmpty ? null : todayEvents.last;

  BusAction get busAction {
    if (commute.riding) return BusAction.arrive;
    if (commute.completedCount >= 2) return BusAction.done;
    return BusAction.board;
  }

  int get suppsTaken =>
      settings.supplements.where(summary.supplements.contains).length;

  TodayState copyWith({
    bool? loaded,
    String? today,
    int? Function()? dayN,
    DaySummary? summary,
    DaySummary? yesterday,
    List<Event>? todayEvents,
    CommuteDay? commute,
    SleepWindow? Function()? night,
    double? Function()? weekSpend,
    Set<EventType>? everLogged,
    bool? everProtein,
    FocusInfo? focus,
    int? Function()? daysLeft,
    AppSettings? settings,
    UndoInfo? Function()? undo,
  }) => TodayState(
    loaded: loaded ?? this.loaded,
    today: today ?? this.today,
    dayN: dayN != null ? dayN() : this.dayN,
    summary: summary ?? this.summary,
    yesterday: yesterday ?? this.yesterday,
    todayEvents: todayEvents ?? this.todayEvents,
    commute: commute ?? this.commute,
    night: night != null ? night() : this.night,
    weekSpend: weekSpend != null ? weekSpend() : this.weekSpend,
    everLogged: everLogged ?? this.everLogged,
    everProtein: everProtein ?? this.everProtein,
    focus: focus ?? this.focus,
    daysLeft: daysLeft != null ? daysLeft() : this.daysLeft,
    settings: settings ?? this.settings,
    undo: undo != null ? undo() : this.undo,
  );

  @override
  List<Object?> get props => [
    loaded,
    today,
    dayN,
    summary,
    yesterday,
    todayEvents,
    commute,
    night,
    weekSpend,
    everLogged,
    everProtein,
    focus.questionId,
    focus.focusText,
    focus.nextAction,
    focus.question?.topic,
    daysLeft,
    settings,
    undo,
  ];
}

class TodayCubit extends Cubit<TodayState> {
  TodayCubit({
    required this._events,
    required this._settings,
    required this._study,
    required this._clock,
    this._db,
    this.idFactory = newEventId,
    this.undoFor = const Duration(seconds: 6),
  }) : super(const TodayState()) {
    _sub =
        combineLatest([
          _events.watchAll(),
          _settings.watch(),
          _study.watchBank(),
          _study.watchStartHere(),
        ]).listen((v) {
          _all = v[0]! as List<Event>;
          _settingsValue = v[1]! as AppSettings;
          _bank = v[2]! as List<StudyQuestion>;
          _startHere = v[3]! as StartHere;
          _recompute();
        });
    // Date rollover while the app stays open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_clock.todayIst() != state.today) _recompute();
    });
    if (_db != null) unawaited(_refreshStudyIfStale());
  }

  final EventsRepository _events;
  final SettingsRepository _settings;
  final StudyRepository _study;
  final Clock _clock;
  final AppDatabase? _db;
  final String Function() idFactory;
  final Duration undoFor;

  StreamSubscription<List<Object?>>? _sub;
  Timer? _tick;
  Timer? _undoTimer;

  List<Event> _all = const [];
  AppSettings _settingsValue = const AppSettings();
  List<StudyQuestion> _bank = const [];
  StartHere _startHere = const StartHere({});

  void _recompute() {
    if (isClosed) return;
    final today = _clock.todayIst();
    final eff = effectiveEvents(_all);
    final first = firstDate(eff);
    final weekFrom = addDays(today, -6);
    final week = eff.where(
      (e) =>
          e.amountInr != null &&
          e.date.compareTo(weekFrom) >= 0 &&
          e.date.compareTo(today) <= 0,
    );
    final target = parseDate(_settingsValue.targetDate);
    emit(
      state.copyWith(
        loaded: true,
        today: today,
        dayN: () => first == null ? null : daysBetween(first, today) + 1,
        summary: summarize(eff, today),
        yesterday: summarize(eff, addDays(today, -1)),
        todayEvents: [
          for (final e in eff)
            if (e.date == today) e,
        ],
        commute: commuteFor(eff, today),
        night: () => nightEndingOn(sleepWindows(eff), today),
        weekSpend: () => week.isEmpty
            ? null
            : week.fold<double>(0, (a, e) => a + e.amountInr!),
        everLogged: {for (final e in eff) e.type},
        everProtein: eff.any(isProtein),
        focus: FocusInfo.resolve(_startHere, _bank),
        daysLeft: () => target == null
            ? null
            : daysBetween(today, _settingsValue.targetDate),
        settings: _settingsValue,
      ),
    );
  }

  static const _studyStale = Duration(hours: 6);

  Future<void> _refreshStudyIfStale() async {
    final last = DateTime.tryParse(
      await _db!.readMeta(MetaKeys.lastStudyRefresh) ?? '',
    );
    if (isClosed) return;
    if (last == null || _clock.nowUtc().difference(last) > _studyStale) {
      await _study.refresh();
    }
  }

  // ------------------------------------------------------------ actions --

  Event _now(
    EventType type, {
    double? qty,
    String? unit,
    String? label,
    double? amount,
    String? category,
  }) {
    final now = _clock.nowIst();
    return Event(
      id: idFactory(),
      date: formatDate(now),
      time: formatTime(now),
      type: type,
      qty: qty,
      unit: unit,
      label: label,
      amountInr: amount,
      category: category,
    );
  }

  Future<void> addCig() => logAll([
    _now(
      EventType.cigarette,
      qty: 1,
      unit: 'cig',
      amount: state.settings.cigPrice,
      category: SpendCategory.tobacco,
    ),
  ]);

  Future<void> addTea() => logAll([
    _now(
      EventType.tea,
      qty: 1,
      unit: 'cup',
      amount: state.settings.teaPrice,
      category: SpendCategory.tea,
    ),
  ]);

  Future<void> addWater() =>
      logAll([_now(EventType.waterMl, qty: 250, unit: 'ml')]);

  /// Board → Arrived → (Board home → Arrived) → Done.
  Future<void> busTap() async {
    switch (state.busAction) {
      case BusAction.board:
        await logAll([_now(EventType.busBoard)]);
      case BusAction.arrive:
        await logAll([_now(EventType.busArrive)]);
      case BusAction.done:
        return;
    }
  }

  /// Ticks a supplement; unticking undoes today's entries for it.
  Future<void> toggleSupplement(String name) async {
    final taken = [
      for (final e in state.todayEvents)
        if (e.type == EventType.supplement && e.label == name) e.id,
    ];
    if (taken.isEmpty) {
      await logAll([_now(EventType.supplement, label: name)]);
    } else {
      for (final id in taken) {
        await _events.undo(id);
      }
    }
  }

  /// Writes events (drift + outbox) and shows the undo line for 6 s.
  Future<void> logAll(List<Event> events) async {
    if (events.isEmpty) return;
    await _events.log(events);
    if (isClosed) return;
    _undoTimer?.cancel();
    emit(
      state.copyWith(
        undo: () => UndoInfo(
          ids: [for (final e in events) e.id],
          text: loggedText(events),
        ),
      ),
    );
    _undoTimer = Timer(undoFor, clearUndo);
  }

  /// Before sync: removed from the outbox. After: a `void` is posted.
  Future<void> undo() async {
    final u = state.undo;
    if (u == null) return;
    _undoTimer?.cancel();
    emit(state.copyWith(undo: () => null));
    for (final id in u.ids) {
      await _events.undo(id);
    }
  }

  void clearUndo() {
    if (isClosed) return;
    _undoTimer?.cancel();
    emit(state.copyWith(undo: () => null));
  }

  @override
  Future<void> close() async {
    _tick?.cancel();
    _undoTimer?.cancel();
    await _sub?.cancel();
    return super.close();
  }
}
