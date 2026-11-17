import '../../core/clock.dart';
import '../../core/streams.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/legacy_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../domain/effective_events.dart';
import '../../domain/event.dart';
import '../../domain/legacy/legacy_adapter.dart';

/// Events tab (effective) + legacy tabs, merged with the Events tab winning.
class MergedData {
  const MergedData({
    required this.events,
    required this.legacy,
    required this.settings,
    required this.today,
  });

  final List<Event> events;
  final LegacyImport legacy;
  final AppSettings settings;
  final String today;
}

/// Week and Money read from this; both only ever read drift.
Stream<MergedData> watchMerged({
  required EventsRepository events,
  required LegacyRepository legacy,
  required SettingsRepository settings,
  required Clock clock,
}) =>
    combineLatest([events.watchAll(), legacy.watchRows(), settings.watch()])
        .map((v) {
          final s = v[2]! as AppSettings;
          final now = clock.nowIst();
          final imp = adaptLegacy(
            v[1]! as Map<String, List<Map<String, dynamic>>>,
            year: now.year,
            cigPrice: s.cigPrice,
            teaPrice: s.teaPrice,
          );
          return MergedData(
            events: withLegacy(effectiveEvents(v[0]! as List<Event>), imp),
            legacy: imp,
            settings: s,
            today: formatDate(now),
          );
        });
