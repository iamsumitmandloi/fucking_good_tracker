import '../core/ids.dart';
import 'event.dart';
import 'event_type.dart';

/// The events every stat is computed from:
/// no `dev-` ids, no `void` rows, no events a `void` cancelled.
List<Event> effectiveEvents(Iterable<Event> all) {
  final voided = <String>{
    for (final e in all)
      if (e.type == EventType.voidEvent && !isDevId(e.id) && e.label != null)
        e.label!,
  };
  final out = [
    for (final e in all)
      if (!isDevId(e.id) &&
          e.type != EventType.voidEvent &&
          !voided.contains(e.id))
        e,
  ]..sort(compareEvents);
  return out;
}
