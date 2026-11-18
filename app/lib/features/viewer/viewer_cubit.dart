import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../core/streams.dart';
import '../../data/local/db.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../domain/event.dart';
import '../../domain/viewer/metrics.dart';
import '../../domain/viewer/viewer_events.dart';

class ViewerState extends Equatable {
  const ViewerState({
    this.loaded = false,
    this.events = const [],
    this.today = '',
    this.week,
    this.settings = const AppSettings(),
    this.refreshedAt,
    this.focusDay,
  });

  /// False only until drift answers the first time (milliseconds).
  final bool loaded;

  /// [viewerEvents] of everything cached, oldest first.
  final List<Event> events;

  /// IST date.
  final String today;

  /// The 7 days ending [today].
  final WeekMetrics? week;
  final AppSettings settings;

  /// Last successful Events refresh, UTC.
  final DateTime? refreshedAt;

  /// The day the Day tab shows; null = today.
  final String? focusDay;

  String get dayShown => focusDay ?? today;

  ViewerState withFocus(String? day) => ViewerState(
    loaded: loaded,
    events: events,
    today: today,
    week: week,
    settings: settings,
    refreshedAt: refreshedAt,
    focusDay: day == today ? null : day,
  );

  /// Every date with at least one event, oldest first.
  List<String> get dates => {for (final e in events) e.date}.toList()..sort();

  @override
  List<Object?> get props => [
    loaded,
    events,
    today,
    week,
    settings,
    refreshedAt,
    focusDay,
  ];
}

/// Read-only: listens to drift only. Refresh goes through [AppSync].
class ViewerCubit extends Cubit<ViewerState> {
  ViewerCubit({
    required EventsRepository events,
    required SettingsRepository settings,
    required AppDatabase db,
    required Clock clock,
  }) : super(const ViewerState()) {
    _sub =
        combineLatest([
          events.watchAll(),
          settings.watch(),
          db.watchMeta(MetaKeys.lastEventsRefresh),
        ]).listen((v) {
          final all = viewerEvents(v[0]! as List<Event>);
          final today = clock.todayIst();
          final raw = v[2] as String?;
          emit(
            ViewerState(
              loaded: true,
              events: all,
              today: today,
              week: weekMetrics(all, daysEnding(today)),
              settings: v[1]! as AppSettings,
              refreshedAt: raw == null ? null : DateTime.tryParse(raw),
              focusDay: state.focusDay,
            ),
          );
        });
  }

  StreamSubscription<List<Object?>>? _sub;

  /// Day tab: show [date] (‹ › or a tap on a Week row).
  void showDay(String date) => emit(state.withFocus(date));

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
