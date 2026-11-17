import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../data/repo/study_repository.dart';
import '../../domain/derivations/commute.dart';
import '../../domain/derivations/leitner.dart';
import '../../domain/effective_events.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';
import '../../domain/study_question.dart';

enum BusStatus { loading, empty, running, done }

class BusState extends Equatable {
  const BusState({
    this.status = BusStatus.loading,
    this.cards = const [],
    this.index = 0,
    this.revealed = false,
    this.ratings = const [],
    this.boardedAt,
    this.bankEmpty = false,
  });

  final BusStatus status;
  final List<StudyQuestion> cards;
  final int index;
  final bool revealed;

  /// One entry per rated card, in order.
  final List<String> ratings;

  /// `HH:mm` of today's open bus leg, if riding.
  final String? boardedAt;
  final bool bankEmpty;

  StudyQuestion? get current =>
      status == BusStatus.running && index < cards.length ? cards[index] : null;

  int count(String rating) => ratings.where((r) => r == rating).length;

  BusState copyWith({
    BusStatus? status,
    List<StudyQuestion>? cards,
    int? index,
    bool? revealed,
    List<String>? ratings,
    String? Function()? boardedAt,
    bool? bankEmpty,
  }) => BusState(
    status: status ?? this.status,
    cards: cards ?? this.cards,
    index: index ?? this.index,
    revealed: revealed ?? this.revealed,
    ratings: ratings ?? this.ratings,
    boardedAt: boardedAt != null ? boardedAt() : this.boardedAt,
    bankEmpty: bankEmpty ?? this.bankEmpty,
  );

  @override
  List<Object?> get props => [
    status,
    cards,
    index,
    revealed,
    ratings,
    boardedAt,
    bankEmpty,
  ];
}

/// Reads only from the local cache, so it works in airplane mode.
/// Each rating is its own `study` event, written the moment it's tapped.
class BusModeCubit extends Cubit<BusState> {
  BusModeCubit({
    required this._events,
    required this._study,
    required this._settings,
    required this._clock,
    this.idFactory = newEventId,
  }) : super(const BusState());

  final EventsRepository _events;
  final StudyRepository _study;
  final SettingsRepository _settings;
  final Clock _clock;
  final String Function() idFactory;

  Future<void> start() async {
    emit(const BusState());
    final bank = await _study.watchBank().first;
    final all = await _events.all();
    final settings = await _settings.load();
    final today = _clock.todayIst();
    final effective = effectiveEvents(all);
    final queue = busQueue(
      bank: bank,
      states: leitnerStates(effective),
      today: today,
    ).take(settings.busRunSize).toList();
    final legs = commuteFor(effective, today);
    if (isClosed) return;
    emit(
      BusState(
        status: queue.isEmpty ? BusStatus.empty : BusStatus.running,
        cards: queue,
        boardedAt: legs.riding ? legs.legs.last.board : null,
        bankEmpty: bank.isEmpty,
      ),
    );
  }

  void reveal() {
    if (state.status != BusStatus.running) return;
    emit(state.copyWith(revealed: true));
  }

  Future<void> rate(String rating) async {
    final card = state.current;
    if (card == null || !state.revealed) return;
    final now = _clock.nowIst();
    final ratings = [...state.ratings, rating];
    final next = state.index + 1;
    emit(
      state.copyWith(
        ratings: ratings,
        index: next,
        revealed: false,
        status: next >= state.cards.length ? BusStatus.done : BusStatus.running,
      ),
    );
    await _events.log([
      Event(
        id: idFactory(),
        date: formatDate(now),
        time: formatTime(now),
        type: EventType.study,
        label: card.id,
        note: rating,
      ),
    ]);
  }
}
