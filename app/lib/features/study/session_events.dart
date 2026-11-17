import 'dart:math' as math;

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';

/// A `study` session event: qty = minutes, note = "session", label = question id.
Event sessionEvent({
  required DateTime startIst,
  required DateTime endIst,
  String? questionId,
  String Function() idFactory = newEventId,
}) {
  final minutes = math.max(1, endIst.difference(startIst).inMinutes);
  return Event(
    id: idFactory(),
    date: formatDate(startIst),
    time: formatTime(startIst),
    endTime: formatTime(endIst),
    type: EventType.study,
    qty: minutes.toDouble(),
    unit: 'min',
    label: questionId,
    note: Rating.session,
  );
}
