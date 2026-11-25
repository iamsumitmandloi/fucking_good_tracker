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

/// Pairs each `bus_board` with the next `bus_arrive` on [date] (and if the last
/// board on [date] is still open, checks early-morning `< 04:00` arrives on the
/// next day).
CommuteDay commuteFor(Iterable<Event> effective, String date) {
  final allBus =
      effective
          .where(
            (e) =>
                e.type == EventType.busBoard || e.type == EventType.busArrive,
          )
          .toList()
        ..sort(compareEvents);
  final prevDate = addDays(date, -1);
  final nextDate = addDays(date, 1);

  // Check if an early-morning (< 04:00) arrive on `date` closed yesterday's leg.
  final prevDay = allBus.where((e) => e.date == prevDate).toList();
  final prevHasOpenBoard =
      prevDay.isNotEmpty && prevDay.last.type == EventType.busBoard;

  final bus = <Event>[];
  var consumedPrevMorningArrive = false;
  for (final e in allBus) {
    if (e.date != date) continue;
    final m = minutesOf(e.time);
    if (!consumedPrevMorningArrive &&
        prevHasOpenBoard &&
        e.type == EventType.busArrive &&
        m != null &&
        m < 4 * 60 &&
        bus.isEmpty) {
      consumedPrevMorningArrive = true;
      continue;
    }
    bus.add(e);
  }

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

  // If still riding at the end of `date`, see if an early-morning arrive on
  // `date + 1` closed this leg.
  if (legs.isNotEmpty && legs.last.arrive == null && legs.last.board != null) {
    for (final e in allBus) {
      if (e.date != nextDate) continue;
      if (e.type == EventType.busBoard) break;
      final m = minutesOf(e.time);
      if (e.type == EventType.busArrive && m != null && m < 4 * 60) {
        final open = legs.removeLast();
        legs.add(
          BusLeg(
            board: open.board,
            arrive: e.time,
            approx: open.approx || e.approx,
          ),
        );
      }
      break;
    }
  }
  return CommuteDay(legs);
}
