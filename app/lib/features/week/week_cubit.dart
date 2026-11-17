import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/legacy_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../domain/derivations/week.dart';
import '../../domain/derivations/weight.dart';
import '../../domain/legacy/legacy_adapter.dart';
import '../shared/merged_events.dart';

class WeekState extends Equatable {
  const WeekState({
    this.loaded = false,
    this.stats,
    this.weight,
    this.flags = const [],
    this.settings = const AppSettings(),
  });

  final bool loaded;
  final WeekStats? stats;
  final WeightWeek? weight;

  /// Legacy data bugs that fall inside this week.
  final List<LegacyFlag> flags;
  final AppSettings settings;

  @override
  List<Object?> get props => [loaded, stats, weight, flags, settings];
}

class WeekCubit extends Cubit<WeekState> {
  WeekCubit({
    required EventsRepository events,
    required this._legacy,
    required SettingsRepository settings,
    required Clock clock,
  }) : super(const WeekState()) {
    _sub =
        watchMerged(
          events: events,
          legacy: _legacy,
          settings: settings,
          clock: clock,
        ).listen((m) {
          final days = weekDays(m.today);
          emit(
            WeekState(
              loaded: true,
              stats: weekStats(
                m.events,
                days,
                legacySleepHours: m.legacy.sleepHours,
              ),
              weight: weightWeek(m.events, days),
              flags: [
                for (final f in m.legacy.flags)
                  if (days.contains(f.date)) f,
              ],
              settings: m.settings,
            ),
          );
        });
    // History rarely changes: refetch the legacy tabs at most every 12 h.
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
