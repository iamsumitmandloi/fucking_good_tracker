import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../domain/effective_events.dart';
import '../../domain/event.dart';
import '../../domain/quicklog/build_events.dart';
import '../../domain/quicklog/parser.dart';

class QuickLogState extends Equatable {
  const QuickLogState({
    this.text = '',
    this.parsed = const ParseResult([]),
    this.extras = const [],
    this.mode = WhenMode.now,
    this.pickedTime,
    this.usuals = const [],
    required this.nowIst,
  });

  final String text;
  final ParseResult parsed;

  /// Entries added from "Repeat a usual" chips.
  final List<ParsedEntry> extras;
  final WhenMode mode;
  final String? pickedTime;
  final List<Usual> usuals;
  final DateTime nowIst;

  List<ParsedEntry> get entries => [...parsed.entries, ...extras];

  /// What will be written, with placeholder ids.
  List<Event> get preview => buildEvents(
    entries,
    nowIst: nowIst,
    mode: mode,
    pickedTime: pickedTime,
    idFactory: () => 'preview',
  );

  String get today => formatDate(nowIst);

  double? get total {
    final paid = entries.where((e) => e.amount != null);
    if (paid.isEmpty) return null;
    return paid.fold<double>(0, (a, e) => a + e.amount!);
  }

  QuickLogState copyWith({
    String? text,
    ParseResult? parsed,
    List<ParsedEntry>? extras,
    WhenMode? mode,
    String? Function()? pickedTime,
    List<Usual>? usuals,
    DateTime? nowIst,
  }) => QuickLogState(
    text: text ?? this.text,
    parsed: parsed ?? this.parsed,
    extras: extras ?? this.extras,
    mode: mode ?? this.mode,
    pickedTime: pickedTime != null ? pickedTime() : this.pickedTime,
    usuals: usuals ?? this.usuals,
    nowIst: nowIst ?? this.nowIst,
  );

  @override
  List<Object?> get props => [
    text,
    parsed.entries,
    parsed.splitTotal,
    extras,
    mode,
    pickedTime,
    usuals,
    nowIst,
  ];
}

/// Parses as you type; builds the events on confirm. Writes nothing itself:
/// the caller logs the result (so Today can show its undo line).
class QuickLogCubit extends Cubit<QuickLogState> {
  QuickLogCubit({
    required this._events,
    required this._settings,
    required this._clock,
    String prefill = '',
    this.idFactory = newEventId,
  }) : super(QuickLogState(nowIst: _clock.nowIst())) {
    unawaited(_init(prefill));
  }

  final EventsRepository _events;
  final SettingsRepository _settings;
  final Clock _clock;
  final String Function() idFactory;

  AppSettings _s = const AppSettings();

  Future<void> _init(String prefill) async {
    _s = await _settings.load();
    final all = await _events.all();
    if (isClosed) return;
    emit(
      state.copyWith(
        usuals: usuals(effectiveEvents(all), today: _clock.todayIst()),
      ),
    );
    // Re-parse with the loaded prices (the user may have typed already).
    setText(state.text.isEmpty ? prefill : state.text);
  }

  void setText(String text) {
    if (isClosed) return;
    emit(
      state.copyWith(
        text: text,
        parsed: parseQuickLog(
          text,
          cigPrice: _s.cigPrice,
          teaPrice: _s.teaPrice,
        ),
        nowIst: _clock.nowIst(),
      ),
    );
  }

  void setMode(WhenMode mode) =>
      emit(state.copyWith(mode: mode, nowIst: _clock.nowIst()));

  void pickTime(String hhmm) => emit(
    state.copyWith(
      mode: WhenMode.pick,
      pickedTime: () => hhmm,
      nowIst: _clock.nowIst(),
    ),
  );

  void addUsual(Usual u) =>
      emit(state.copyWith(extras: [...state.extras, u.entry]));

  void removeExtra(int index) {
    final list = [...state.extras]..removeAt(index);
    emit(state.copyWith(extras: list));
  }

  /// The events to write, with real ids and the current time.
  List<Event> build() => buildEvents(
    state.entries,
    nowIst: _clock.nowIst(),
    mode: state.mode,
    pickedTime: state.pickedTime,
    idFactory: idFactory,
  );
}
