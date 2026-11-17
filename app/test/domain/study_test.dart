import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/derivations/leitner.dart';
import 'package:starting_again/domain/derivations/study_progress.dart';
import 'package:starting_again/domain/effective_events.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/start_here.dart';
import 'package:starting_again/domain/study_question.dart';

var _n = 0;
Event rate(String q, String rating, String date, {String? id}) => Event(
  id: id ?? 'e${_n++}',
  date: date,
  time: '08:00',
  type: EventType.study,
  label: q,
  note: rating,
);

StudyQuestion q(
  String id,
  int row, {
  int tier = 1,
  String source = 'My work',
}) => StudyQuestion(id: id, row: row, tier: tier, sourceTab: source);

void main() {
  group('Study Bank parsing', () {
    test('splits follow-ups and answer points on ";" and trims', () {
      final s = StudyQuestion.fromRow({
        '_row': 7,
        'Question ID': 'D61.1',
        'Source tab': 'Debasmita 100',
        'Topic': 'Platform channels',
        'Area': 'Senior',
        'Tier': 'T1',
        'Type': 'Concept',
        'Stars': '★★★',
        'Question': 'How do platform channels work?',
        'Follow-ups': 'What types? ; How are errors returned?;',
        'Answer points / rubric': 'Async binary messages; MethodChannel: request/response ;;EventChannel',
        'Project': '',
        'Related question': 'D61.2',
        'Status': '',
      })!;
      expect(s.id, 'D61.1');
      expect(s.row, 7);
      expect(s.tier, 1);
      expect(s.followUps, ['What types?', 'How are errors returned?']);
      expect(s.answerPoints, [
        'Async binary messages',
        'MethodChannel: request/response',
        'EventChannel',
      ]);
      expect(s.meta, 'Senior · T1 · Concept');
      expect(s.related, 'D61.2');
    });

    test('tier accepts "1", "T2", "Tier 3"; missing id → null', () {
      expect(StudyQuestion.parseTier('1'), 1);
      expect(StudyQuestion.parseTier('T2'), 2);
      expect(StudyQuestion.parseTier('Tier 3'), 3);
      expect(StudyQuestion.parseTier(''), isNull);
      expect(
        StudyQuestion.fromRow({'Question ID': '', 'Question': 'x'}),
        isNull,
      );
    });

    test('header drift: "Answer points" alone still maps', () {
      final s = StudyQuestion.fromRow({
        'Question ID': 'X1',
        'Answer points': 'a;b',
        'Follow ups': 'c',
      })!;
      expect(s.answerPoints, ['a', 'b']);
      expect(s.followUps, ['c']);
    });
  });

  group('Start Here', () {
    test('recovers the pair used as the header row', () {
      final pairs = startHerePairs([
        {
          '_row': 2,
          'Current focus': 'Next action',
          'RS-34 · Root detection': 'Open the file',
        },
        {
          '_row': 3,
          'Current focus': 'Target date',
          'RS-34 · Root detection': '2026-11-30',
        },
      ]);
      final sh = StartHere({for (final p in pairs) p.key: p.value});
      expect(sh.currentFocus, 'RS-34 · Root detection');
      expect(sh.nextAction, 'Open the file');
      expect(sh.targetDate, '2026-11-30');
      expect(sh.focusQuestionId, 'RS-34');
    });

    test('generic "Key | Value" header is not treated as data', () {
      final pairs = startHerePairs([
        {'Key': 'Current focus', 'Value': 'D61.1 platform channels'},
      ]);
      expect(pairs.map((p) => p.key), ['Current focus']);
      expect(StartHere.questionIdIn('D61.1 platform channels'), 'D61.1');
    });
  });

  group('Leitner', () {
    test('blank / shaky → due next day, streak reset', () {
      final s = leitnerStates([rate('A', 'blank', '2026-11-17')]);
      expect(s['A']!.due, '2026-11-18');
      expect(s['A']!.streak, 0);
      final s2 = leitnerStates([rate('A', 'shaky', '2026-11-30')]);
      expect(s2['A']!.due, '2026-12-01');
    });

    test('nailed → +4 days; nailed twice running → +10 days', () {
      final once = leitnerStates([rate('A', 'nailed', '2026-11-17')]);
      expect(once['A']!.due, '2026-11-21');
      final twice = leitnerStates([
        rate('A', 'nailed', '2026-11-17'),
        rate('A', 'nailed', '2026-11-21'),
      ]);
      expect(twice['A']!.due, '2026-12-01');
      expect(twice['A']!.streak, 2);
    });

    test('a shaky between nails resets the streak', () {
      final s = leitnerStates([
        rate('A', 'nailed', '2026-11-10'),
        rate('A', 'shaky', '2026-11-14'),
        rate('A', 'nailed', '2026-11-15'),
      ]);
      expect(s['A']!.streak, 1);
      expect(s['A']!.due, '2026-11-19');
    });

    test('events are applied in time order regardless of input order', () {
      final s = leitnerStates([
        rate('A', 'nailed', '2026-11-21'),
        rate('A', 'blank', '2026-11-17'),
      ]);
      expect(s['A']!.lastRating, 'nailed');
      expect(s['A']!.due, '2026-11-25');
    });

    test('session events and non-rating notes are ignored', () {
      final s = leitnerStates([
        const Event(
          id: 's',
          date: '2026-11-17',
          type: EventType.study,
          label: 'A',
          note: 'session',
          qty: 25,
        ),
      ]);
      expect(s, isEmpty);
    });
  });

  group('bus queue', () {
    final bank = [
      q('D1', 2),
      q('D2', 3),
      q('D3', 4),
      q('D4', 5),
      q('T2', 6, tier: 2),
    ];

    test('never-seen first, then overdue by due date, tier 1 only', () {
      final states = leitnerStates([
        rate('D1', 'blank', '2026-11-15'), // due 16
        rate('D3', 'shaky', '2026-11-13'), // due 14 (more overdue)
        rate('D4', 'nailed', '2026-11-16'), // due 20: not due
      ]);
      final queue = busQueue(bank: bank, states: states, today: '2026-11-17');
      expect(queue.map((x) => x.id), ['D2', 'D3', 'D1']);
    });

    test('a card rated today is not due again today', () {
      final states = leitnerStates([rate('D1', 'blank', '2026-11-17')]);
      final queue = busQueue(bank: bank, states: states, today: '2026-11-17');
      expect(queue.map((x) => x.id), ['D2', 'D3', 'D4']);
    });

    test('dev- ratings never move a card', () {
      final states = leitnerStates(
        effectiveEvents([rate('D1', 'nailed', '2026-11-17', id: 'dev-1')]),
      );
      final queue = busQueue(bank: bank, states: states, today: '2026-11-17');
      expect(queue.first.id, 'D1');
    });
  });

  group('study progress', () {
    final bank = [
      for (var i = 0; i < 198; i++) q('T1-$i', i + 2),
      for (var i = 0; i < 303; i++)
        q('T2-$i', i + 300, tier: 2, source: 'Debasmita 100'),
    ];

    test('design numbers: 0/501, T1 pace 16/day with 13 days left', () {
      final p = computeStudyProgress(
        bank: bank,
        effective: const [],
        today: '2026-11-17',
        targetDate: '2026-11-30',
      );
      expect(p.total, 501);
      expect(p.assessed, 0);
      expect(p.daysLeft, 13);
      expect(p.tierTotal(1), 198);
      expect(p.t1Pace, 16); // ceil(198 / 13) = 15.23 → 16
    });

    test('assessed = distinct ids with ≥1 rating; sessions counted apart', () {
      final p = computeStudyProgress(
        bank: bank,
        effective: [
          rate('T1-0', 'blank', '2026-11-17'),
          rate('T1-0', 'nailed', '2026-11-18'),
          rate('T2-5', 'shaky', '2026-11-17'),
          rate('NOT-IN-BANK', 'nailed', '2026-11-17'),
          const Event(
            id: 's1',
            date: '2026-11-17',
            type: EventType.study,
            qty: 25,
            note: 'session',
            label: 'T1-1',
          ),
        ],
        today: '2026-11-18',
        targetDate: '2026-11-30',
      );
      expect(p.assessed, 2);
      expect(p.tierDone(1), 1);
      expect(p.tierDone(2), 1);
      expect(p.sessions, 1);
      expect(p.sessionMinutes, 25);
      expect(p.daysLeft, 12);
      expect(p.t1Pace, 17); // ceil(197 / 12) = 16.4 → 17
      expect(p.ratedToday, 1);
    });

    test('target passed → pace is null, not 0', () {
      final p = computeStudyProgress(
        bank: bank,
        effective: const [],
        today: '2026-12-01',
        targetDate: '2026-11-30',
      );
      expect(p.daysLeft, -1);
      expect(p.t1Pace, isNull);
    });
  });
}
