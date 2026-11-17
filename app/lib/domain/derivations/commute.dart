import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../event.dart';
import '../event_type.dart';

class BusLeg extends Equatable {
  const BusLeg({this.board, this.arrive, this.approx = false});

  /// `HH:mm`; null for an arrive with no matching board.
  final String? board;
  final String? arrive;
  final bool approx;

  bool get complete => board != null && arrive != null;

  /// arrive − board, across midnight if needed. Null when incomplete.
  int? get minutes {
    final b = minutesOf(board);
    final a = minutesOf(arrive);
    if (a == null || b == null) return null;
    final d = a - b;
    return d < 0 ? d + 24 * 60 : d;
  }

  @override
  List<Object?> get props => [board, arrive, approx];
}

class CommuteDay extends Equatable {
  const CommuteDay(this.legs);

  final List<BusLeg> legs;

  /// Last leg boarded but not arrived.
  bool get riding => legs.isNotEmpty && legs.last.arrive == null;

  int get completedCount => legs.where((l) => l.complete).length;

  BusLeg? get lastCompleted {
    for (final l in legs.reversed) {
      if (l.complete) return l;
    }
    return null;
  }

  /// Sum of completed legs; null when none (never 0 for "no data").
  int? get totalMinutes {
    final done = legs.where((l) => l.complete);
    if (done.isEmpty) return null;
    return done.fold<int>(0, (a, l) => a + l.minutes!);
  }

  @override
  List<Object?> get props => [legs];
}

/// Pairs each `bus_board` with the next `bus_arrive` on [date].
CommuteDay commuteFor(Iterable<Event> effective, String date) {
  final bus =
      effective
          .where(
            (e) =>
                e.date == date &&
                (e.type == EventType.busBoard || e.type == EventType.busArrive),
          )
          .toList()
        ..sort(compareEvents);
  final legs = <BusLeg>[];
  for (final e in bus) {
    if (e.type == EventType.busBoard) {
      legs.add(BusLeg(board: e.time, approx: e.approx));
    } else if (legs.isNotEmpty &&
        legs.last.arrive == null &&
        legs.last.board != null) {
      final open = legs.removeLast();
      legs.add(
        BusLeg(
          board: open.board,
          arrive: e.time,
          approx: open.approx || e.approx,
        ),
      );
    } else {
      legs.add(BusLeg(arrive: e.time, approx: e.approx));
    }
  }
  return CommuteDay(legs);
}
