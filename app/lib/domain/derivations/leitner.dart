import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../event.dart';
import '../event_type.dart';
import '../study_question.dart';

/// Review state of one question, derived from its rating events (PRD §3 P0-4).
class CardState extends Equatable {
  const CardState({
    required this.id,
    this.due,
    this.streak = 0,
    this.lastRating,
    this.lastRatedOn,
    this.ratings = 0,
  });

  final String id;

  /// `yyyy-MM-dd`; null when never rated.
  final String? due;

  /// Consecutive "nailed" ratings.
  final int streak;
  final String? lastRating;
  final String? lastRatedOn;
  final int ratings;

  bool get seen => ratings > 0;

  @override
  List<Object?> get props => [
    id,
    due,
    streak,
    lastRating,
    lastRatedOn,
    ratings,
  ];
}

/// Blank/Shaky → tomorrow. Nailed → +4 days; nailed twice running → +10.
int intervalDays(String rating, int streakAfter) {
  if (rating != Rating.nailed) return 1;
  return streakAfter >= 2 ? 10 : 4;
}

bool isRatingEvent(Event e) =>
    e.type == EventType.study &&
    e.label != null &&
    Rating.all.contains(e.note?.toLowerCase());

/// Folds rating events (already run through effectiveEvents) into states.
Map<String, CardState> leitnerStates(Iterable<Event> effective) {
  final ratings = effective.where(isRatingEvent).toList()..sort(compareEvents);
  final out = <String, CardState>{};
  for (final e in ratings) {
    final id = e.label!;
    final r = e.note!.toLowerCase();
    final prev = out[id] ?? CardState(id: id);
    final streak = r == Rating.nailed ? prev.streak + 1 : 0;
    out[id] = CardState(
      id: id,
      due: addDays(e.date, intervalDays(r, streak)),
      streak: streak,
      lastRating: r,
      lastRatedOn: e.date,
      ratings: prev.ratings + 1,
    );
  }
  return out;
}

/// Tier-[tier] questions due on [today]. Never-seen first (sheet order),
/// then the most overdue, ties by sheet order.
List<StudyQuestion> busQueue({
  required List<StudyQuestion> bank,
  required Map<String, CardState> states,
  required String today,
  int tier = 1,
}) {
  final candidates = bank.where((q) => q.tier == tier).toList();
  final unseen = <StudyQuestion>[];
  final due = <StudyQuestion>[];
  for (final q in candidates) {
    final s = states[q.id];
    if (s == null || !s.seen) {
      unseen.add(q);
    } else if (s.due!.compareTo(today) <= 0) {
      due.add(q);
    }
  }
  unseen.sort((a, b) => a.row.compareTo(b.row));
  due.sort((a, b) {
    final c = states[a.id]!.due!.compareTo(states[b.id]!.due!);
    return c != 0 ? c : a.row.compareTo(b.row);
  });
  return [...unseen, ...due];
}
