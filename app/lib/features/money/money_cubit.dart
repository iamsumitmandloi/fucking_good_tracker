import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/legacy_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../domain/derivations/burn.dart';
import '../../domain/derivations/week.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';
import '../shared/merged_events.dart';

class MoneyState extends Equatable {
  const MoneyState({
    this.loaded = false,
    this.days = const [],
    this.burn,
    this.cigsWeek,
    this.todayEntries = const [],
    this.settings = const AppSettings(),
  });

  final bool loaded;
  final List<String> days;
  final Burn? burn;

  /// Cigarettes this week (for the smoking estimate). Null if none logged.
  final double? cigsWeek;

  /// Today's paid entries, oldest first.
  final List<Event> todayEntries;
  final AppSettings settings;

  double? get todaySpend => todayEntries.isEmpty
      ? null
      : todayEntries.fold<double>(0, (a, e) => a + e.amountInr!);

  /// Smoking cost per 30 days at this week's rate.
  double? get smokingPerMonth {
    if (cigsWeek == null || days.isEmpty) return null;
    return cigsWeek! * settings.cigPrice * 30 / days.length;
  }

  @override
  List<Object?> get props => [
    loaded,
    days,
    burn,
    cigsWeek,
    todayEntries,
    settings,
  ];
}

class MoneyCubit extends Cubit<MoneyState> {
  MoneyCubit({
    required EventsRepository events,
    required this._legacy,
    required SettingsRepository settings,
    required Clock clock,
  }) : super(const MoneyState()) {
    _sub =
        watchMerged(
          events: events,
          legacy: _legacy,
          settings: settings,
          clock: clock,
        ).listen((m) {
          final days = weekDays(m.today);
          final cigs = m.events.where(
            (e) => e.type == EventType.cigarette && days.contains(e.date),
          );
          emit(
            MoneyState(
              loaded: true,
              days: days,
              burn: burn(m.events, from: days.first, to: days.last),
              cigsWeek: cigs.isEmpty
                  ? null
                  : cigs.fold<double>(0, (a, e) => a + e.count),
              todayEntries: [
                for (final e in m.events)
                  if (e.date == m.today && e.amountInr != null) e,
              ],
              settings: m.settings,
            ),
          );
        });
    unawaited(_legacy.refresh());
  }

  final LegacyRepository _legacy;
  StreamSubscription<MergedData>? _sub;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
