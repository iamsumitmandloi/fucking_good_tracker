import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/voice/speech_normalizer.dart';
import 'package:starting_again/domain/voice/voice_contracts.dart';
import 'package:starting_again/domain/voice/voice_draft.dart';

const builder = VoiceDraftBuilder();
final now = DateTime.utc(2026, 11, 25, 18, 2);
const today = '2026-11-25';
const yesterday = '2026-11-24';

VoiceDraftResult parse(String s, {List<Event> recent = const []}) =>
    builder.parse(
      transcript: s,
      nowIst: now,
      cigPrice: 25,
      teaPrice: 20,
      recentEvents: recent,
    );

/// `type qty ₹amount @time ~`, so a whole draft reads on one line each.
List<String> brief(VoiceDraftResult r) => [
  for (final i in r.items)
    [
      i.entry.type.wire,
      if (i.entry.qty != null) 'x${i.entry.qty}',
      if (i.entry.amount != null) '₹${i.entry.amount}',
      if (i.entry.time != null) '@${i.entry.time}',
      if (i.entry.approx) '~',
    ].join(' '),
];

List<Event> events(String s) {
  var n = 0;
  return builder.toEvents(
    parse(s).items,
    nowIst: now,
    nextId: () => 'dev-${++n}',
  );
}

void main() {
  // transcript → expected entries
  const drafts = <String, List<String>>{
    // Activity vs spend
    'Today I had two cigarettes, one tea, and spent 50': [
      'cigarette x2.0',
      'tea x1.0',
      'spend ₹50.0',
    ],
    'I had tea and spent 50': ['tea x1.0', 'spend ₹50.0'],
    'I spent 50 on tea': ['tea x1.0 ₹50.0'],
    'tea 20 rupees': ['tea x1.0 ₹20.0'],
    'tea 5 rupees': ['tea x1.0 ₹5.0'],
    'I had 2 cigarettes.': ['cigarette x2.0'],
    'I had a tea': ['tea x1.0'],
    'I smoked three': ['cigarette x3.0'],
    'two cups of tea': ['tea x2.0'],
    'two teas 20 each': ['tea x2.0 ₹40.0'],
    'spent 50 on tea and 30 on auto': ['tea x1.0 ₹50.0', 'spend ₹30.0'],
    '1 cig + tea 45': ['cigarette x1.0', 'tea x1.0', 'spend ₹45.0'],
    'half cigarette': ['cigarette x0.5'],
    'paid 150 for lunch': ['meal ₹150.0'],
    // Self-corrections
    'Two cigarettes—actually, three': ['cigarette x3.0'],
    '2 cig—no wait, 3': ['cigarette x3.0'],
    'two cigarettes actually three and one tea': ['cigarette x3.0', 'tea x1.0'],
    'Two cigarettes. Actually three.': ['cigarette x3.0'],
    'two cigarettes, sorry three cigarettes': ['cigarette x3.0'],
    'tea 20, sorry 15': ['tea x1.0 ₹15.0'],
    'one tea, make it 4': ['tea x4.0'],
    'a tea, make it 4': ['tea x4.0'],
    '2 cigarettes for 50, actually 3': ['cigarette x3.0 ₹50.0'],
    'spent 50, no 60': ['spend ₹60.0'],
    'reached office at 10:40, sorry 10:50': ['bus_arrive @10:50'],
    'two cigarettes, actually one tea': ['cigarette x2.0', 'tea x1.0'],
    // Numbers and money
    'Samosa pav 30 rupees and Lahori Jeera 10': ['snack ₹30.0', 'snack ₹10.0'],
    'samosa pav 30 ka': ['snack ₹30.0'],
    '30 rupees samosa': ['snack ₹30.0'],
    'auto fifty bucks': ['spend ₹50.0'],
    'spent two hundred and fifty rupees': ['spend ₹250.0'],
    'auto one fifty rupees': ['spend ₹150.0'],
    'spent one hundred and two cigarettes': ['spend ₹100.0', 'cigarette x2.0'],
    'samosa and chutney 30': ['snack ₹30.0'],
    'Weight 87 point 5': ['weight x87.5'],
    'my weight is eighty seven point five kilos': ['weight x87.5'],
    'ten thousand steps': ['steps x10000.0'],
    'I walked 10,000 steps today': ['steps x10000.0'],
    'half a litre of water': ['water_ml x500.0'],
    'drank two glasses of water': ['water_ml x500.0'],
    'walked for half an hour': ['exercise x30.0'],
    'mood was eight out of ten': ['mood x8.0'],
    // Times
    'Slept around 12:30 am': ['sleep @00:30 ~'],
    'slept at 11': ['sleep @23:00'],
    'Reached office at 10 40': ['bus_arrive @10:40'],
    'reached office at ten forty five': ['bus_arrive @10:45'],
    'Boarded the bus at 9': ['bus_board @09:00'],
    'woke up at 6 30 a.m.': ['wake @06:30'],
    'woke up at half past six': ['wake @06:30'],
    'tea at 5 in the evening': ['tea x1.0 @17:00'],
    'tea at 5': ['tea x1.0'],
    'just now I had a cigarette': ['cigarette x1.0 @18:02'],
    'about two cigarettes just now': ['cigarette x2.0 @18:02'],
    'tea and a cigarette just now': [
      'tea x1.0 @18:02',
      'cigarette x1.0 @18:02',
    ],
    'roughly 8000 steps': ['steps x8000.0 ~'],
    // Plans and negations never become activity
    "I'm thinking of ordering dinner": [],
    'I might order pizza for 300': [],
    'should I have a tea?': [],
    "I haven't yet had lunch": [],
    'planning to have tea, coffee and two cigarettes': [],
    'will have tea but had two cigarettes': ['cigarette x2.0'],
    "I didn't have tea and coffee": ['note', 'note'],
    'no cigarettes today': ['note'],
    'zero cigarettes': ['note'],
    // Word order and fillers
    'two cigarettes no three': ['cigarette x3.0'],
    'tea at 4:30 pm for 20 rupees': ['tea x1.0 ₹20.0 @16:30'],
    'I had a coffee for 120 around 5 pm': ['coffee x1.0 ₹120.0 @17:00 ~'],
    'lunch for 130 in the canteen': ['meal ₹130.0'],
    'I had like two teas': ['tea x2.0'],
    'had a couple of cigarettes': ['cigarette x2.0'],
    'two cigarettes, then one tea': ['cigarette x2.0', 'tea x1.0'],
    // Fallbacks
    '': [],
    'um, uh': [],
    'Feeling a bit low after the call': ['note'],
    'three': ['note'],
  };
  for (final d in drafts.entries) {
    test('"${d.key}"', () => expect(brief(parse(d.key)), d.value));
  }

  group('plans', () {
    test('are reported, verbatim enough to recognise', () {
      final r = parse("One tea. I'm thinking of ordering dinner.");
      expect(brief(r), ['tea x1.0']);
      expect(r.ignoredPlans, ["I'm thinking of ordering dinner"]);
    });

    test('"bus going to office" is not a plan', () {
      final r = parse('Boarded bus going to office');
      expect(r.ignoredPlans, isEmpty);
      expect(brief(r), ['bus_board']);
    });

    test('going to the office in the future does not draft a spend', () {
      final r = parse("I'm going to office for 50 rupees");
      expect(r.ignoredPlans.single, contains('going to office'));
      expect(r.items, isEmpty);
    });
  });

  group('dates', () {
    test('"Yesterday 10000 steps"', () {
      final i = parse('Yesterday 10000 steps').items.single;
      expect(i.dateOverride, yesterday);
      expect(i.entry.time, isNull);
    });

    test('"today" sets the date but no clock', () {
      final i = parse('Today I had a tea').items.single;
      expect(i.dateOverride, today);
      expect(i.entry.time, isNull);
    });

    test('no timing → no override and no clock', () {
      final i = parse('had a tea').items.single;
      expect(i.dateOverride, isNull);
      expect(i.entry.time, isNull);
    });

    test('leading and trailing dates cover the joined items', () {
      for (final s in [
        'Yesterday two cigarettes and one tea',
        'two cigarettes and one tea yesterday',
      ]) {
        expect(parse(s).items.map((i) => i.dateOverride), [
          yesterday,
          yesterday,
        ], reason: s);
      }
    });

    test('a date does not leak into the next sentence', () {
      final r = parse('Yesterday 10000 steps. One tea.');
      expect(r.items.last.dateOverride, isNull);
    });

    test('"last night" follows the clock across midnight', () {
      expect(
        parse('slept last night at 11 pm').items.single.dateOverride,
        yesterday,
      );
      expect(
        parse('slept last night at 12:30 am').items.single.dateOverride,
        today,
      );
    });

    test('"day before yesterday"', () {
      expect(
        parse('day before yesterday 9000 steps').items.single.dateOverride,
        '2026-11-23',
      );
    });

    test('ambiguous clock is dropped with a warning', () {
      expect(parse('tea at 5').warnings, [contains('at 5')]);
    });
  });

  group('source', () {
    test('every entry is voice', () {
      final r = parse('two cigarettes, lunch 130, feeling fine');
      expect(r.items.map((i) => i.entry.source).toSet(), {'voice'});
    });

    test('LazyPay wins', () {
      final r = parse('zomato 250 with lazy pay');
      expect(brief(r), ['spend ₹250.0']);
      expect(r.items.single.entry.source, 'lazypay');
      expect(r.items.single.entry.label, 'Zomato');
    });
  });

  group('duplicates', () {
    Event ev(
      EventType type, {
      String date = today,
      String? time,
      double? amount,
      String? label,
    }) => Event(
      id: 'x',
      date: date,
      type: type,
      time: time,
      amountInr: amount,
      label: label,
    );

    test('same activity today warns and keeps the item', () {
      final r = parse('one tea', recent: [ev(EventType.tea)]);
      expect(r.warnings, ['You already logged Tea today']);
      expect(r.items.single.included, isTrue);
    });

    test('compares against the spoken date', () {
      final r = parse('yesterday one tea', recent: [ev(EventType.tea)]);
      expect(r.warnings, isEmpty);
    });

    test('different meal label is not a duplicate', () {
      final r = parse('lunch', recent: [ev(EventType.meal, label: 'Dinner')]);
      expect(r.warnings, isEmpty);
    });

    test('same amount within 15 minutes only', () {
      Event spend(String time) =>
          ev(EventType.spend, time: time, amount: 50, label: 'Chips');
      expect(parse('auto ₹50', recent: [spend('17:50')]).warnings, [
        '₹50 was already logged at 17:50',
      ]);
      expect(parse('auto ₹50', recent: [spend('17:40')]).warnings, isEmpty);
    });
  });

  group('fallback', () {
    test('keeps the spoken words as a note', () {
      final r = parse('Feeling a bit low after the call');
      expect(r.hasUnparsedFallback, isTrue);
      expect(r.items.single.entry.note, 'Feeling a bit low after the call');
    });

    test('an unknown "thing 5" is flagged as a guessed price', () {
      expect(parse('finished chapter 5').warnings, [contains('₹5')]);
    });

    test('recognised speech is not a fallback', () {
      expect(parse('one tea').hasUnparsedFallback, isFalse);
    });

    test('never throws on odd input', () {
      for (final s in ['...', '—', 'actually', '₹', 'and and', 'at 99', '☕']) {
        expect(() => parse(s), returnsNormally, reason: s);
      }
    });
  });

  group('toEvents', () {
    test('one activity plus one spend per payment', () {
      final e = events('Today I had two cigarettes and tea 20 rupees');
      expect(e.map((x) => x.type), [
        EventType.cigarette,
        EventType.tea,
        EventType.spend,
      ]);
      expect(e.last.amountInr, 20);
      expect(e.last.category, SpendCategory.tea);
      expect(e[1].amountInr, isNull);
      expect(e.map((x) => x.source).toSet(), {'voice'});
      expect(e.map((x) => x.time), everyElement(isNull));
      expect(e.map((x) => x.id).toSet(), hasLength(3));
    });

    test('a bare spend is a single event', () {
      final e = events('spent 50').single;
      expect(e.type, EventType.spend);
      expect(e.category, SpendCategory.other);
    });

    test(
      'a combined payment writes one spend without default habit prices',
      () {
        final e = events('1 cig + tea 45');
        expect(e.map((row) => row.type), [
          EventType.cigarette,
          EventType.tea,
          EventType.spend,
        ]);
        expect(e.map((row) => row.amountInr), [null, null, 45]);
      },
    );

    test('excluded items are not written', () {
      final i = parse('one tea').items.single;
      expect(
        builder.toEvents(
          [VoiceDraftItem(entry: i.entry, included: false)],
          nowIst: now,
          nextId: () => 'dev-1',
        ),
        isEmpty,
      );
    });

    test('a spoken total is not logged on top of its parts', () {
      final r = parse('tea 20, samosa 30, total 50');
      expect(r.items.map((i) => i.included), [true, true, false]);
    });

    test('a spoken total is kept when the activities have no stated price', () {
      final e = events('one tea, total 50');
      expect(e.map((row) => row.amountInr), [null, 50]);
    });

    test('a later clock without a date means yesterday', () {
      expect(events('slept at 11:30 pm').single.date, yesterday);
      expect(events('woke up at 6:30 am').single.date, today);
    });

    test('item note overrides the entry note', () {
      final i = parse('one tea').items.single;
      final e = builder.toEvents(
        [VoiceDraftItem(entry: i.entry, note: 'ginger')],
        nowIst: now,
        nextId: () => 'dev-1',
      );
      expect(e.single.note, 'ginger');
    });
  });

  group('normalizeSpeech', () {
    const cases = {
      'twenty-one rupees': '₹21',
      'Rs. 50': '₹50',
      'five hundred': '500',
      'at ten oh five': 'at 10:05',
      'one of the best days': 'one of the best days',
      'um two  teas': '2 teas',
    };
    for (final c in cases.entries) {
      test(c.key, () => expect(normalizeSpeech(c.key), c.value));
    }
  });
}
