import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../event.dart';
import '../event_type.dart';
import '../study_question.dart';
import 'leitner.dart';

class StudyProgress extends Equatable {
  const StudyProgress({
    required this.total,
    required this.assessed,
    required this.tierTotals,
    required this.tierAssessed,
    required this.sessions,
    required this.sessionMinutes,
    required this.daysLeft,
    required this.t1Pace,
    required this.sourceCounts,
    required this.ratedToday,
  });

  final int total;
  final int assessed;
  final Map<int, int> tierTotals;
  final Map<int, int> tierAssessed;
  final int sessions;
  final int sessionMinutes;

  /// Null when no target date is known.
  final int? daysLeft;

  /// Null when the target has passed or no T1 cards exist.
  final int? t1Pace;
  final Map<String, int> sourceCounts;
  final int ratedToday;

  int tierTotal(int t) => tierTotals[t] ?? 0;
  int tierDone(int t) => tierAssessed[t] ?? 0;

  @override
  List<Object?> get props => [
    total,
    assessed,
    tierTotals,
    tierAssessed,
    sessions,
    sessionMinutes,
    daysLeft,
    t1Pace,
    sourceCounts,
    ratedToday,
  ];
}

bool isSessionEvent(Event e) =>
    e.type == EventType.study && e.note?.toLowerCase() == Rating.session;

/// [effective] must already exclude dev- rows and voids.
StudyProgress computeStudyProgress({
  required List<StudyQuestion> bank,
  required List<Event> effective,
  required String today,
  required String? targetDate,
}) {
  final bankIds = {for (final q in bank) q.id};
  final assessedIds = <String>{
    for (final e in effective)
      if (isRatingEvent(e) && bankIds.contains(e.label)) e.label!,
  };
  final tierTotals = <int, int>{};
  final tierAssessed = <int, int>{};
  final sources = <String, int>{};
  for (final q in bank) {
    if (q.tier != null) {
      tierTotals[q.tier!] = (tierTotals[q.tier!] ?? 0) + 1;
      if (assessedIds.contains(q.id)) {
        tierAssessed[q.tier!] = (tierAssessed[q.tier!] ?? 0) + 1;
      }
    }
    final src = q.sourceTab.isEmpty ? 'Other' : q.sourceTab;
    sources[src] = (sources[src] ?? 0) + 1;
  }
  final sessions = effective.where(isSessionEvent).toList();
  final days = targetDate == null || parseDate(targetDate) == null
      ? null
      : daysBetween(today, targetDate);
  final remainingT1 = (tierTotals[1] ?? 0) - (tierAssessed[1] ?? 0);
  final pace = (days == null || days <= 0 || (tierTotals[1] ?? 0) == 0)
      ? null
      : (remainingT1 / days).ceil();
  return StudyProgress(
    total: bank.length,
    assessed: assessedIds.length,
    tierTotals: tierTotals,
    tierAssessed: tierAssessed,
    sessions: sessions.length,
    sessionMinutes: sessions.fold(0, (a, e) => a + (e.qty ?? 0).round()),
    daysLeft: days,
    t1Pace: pace,
    sourceCounts: sources,
    ratedToday: effective
        .where((e) => isRatingEvent(e) && e.date == today)
        .length,
  );
}
