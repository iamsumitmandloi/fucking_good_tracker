import '../../core/clock.dart';

/// Pure text clean-up for spoken logs: numbers, money, clocks, clauses,
/// self-corrections, plans and dates. No parsing into events happens here.

RegExp _re(String p) => RegExp(p, caseSensitive: false);

/// Nouns that take a spoken count ("2 cigarettes", "do chai").
const habitNouns =
    r'(?:cigs?|cigarettes?|ciggies?|smokes?|sutta|teas?|chai|coffees?)';

const _small = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
  'seven': 7, 'eight': 8, 'nine': 9, 'zero': 0, 'ten': 10, 'eleven': 11,
  'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, //
  'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
};
const _tens = {
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40, 'fifty': 50, //
  'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
};
const _hindi = {
  'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'chaar': 4, 'panch': 5, //
  'paanch': 5,
};

final _tensRe = _re(
  '\\b(${_tens.keys.join('|')})(?:[\\s-]+(${_small.keys.take(9).join('|')}))?\\b',
);

/// "one" stays a word where it is a pronoun ("this one", "one of the…").
final _smallRe = _re(
  '(?<!\\b(?:this|that|every|each) )\\b(${_small.keys.join('|')})\\b'
  '(?! (?:of|day|another)\\b)',
);
final _hindiRe = _re('\\b(${_hindi.keys.join('|')})(?= $habitNouns\\b)');
const _money = r'(?:rupees?|rupaye|rupay|rs\b\.?|bucks?|inr\b|₹)';

/// Spoken numbers → digits, rupees → `₹N`, clocks → `H:MM`, units shortened.
String normalizeSpeech(String input) {
  var s = input;
  void sub(String p, String Function(Match m) f) =>
      s = s.replaceAllMapped(_re(p), f);

  s = s.replaceAll(RegExp('[‘’]'), "'").replaceAll(RegExp(r'[ \t]+'), ' ');
  sub(r'\b([ap])\.?\s?m\b(?:\.(?=\s*\S))?', (m) => '${m[1]!.toLowerCase()}m');
  sub(r'(^|[\s,])(?:u+m+|u+h+|e+r+m*|hm+|you know|basically)\b[,.]?', (m) {
    return m[1]!;
  });

  sub(r'\ba couple(?: of)?\b', (_) => '2');

  // "half" before the plain number words eat its neighbours.
  sub(r'\bhalf an? hour\b', (_) => '30 min');
  sub(
    r'\b(?:a )?half (?:an? )?(?=(?:lit(?:re|er)|cup|glass|' +
        habitNouns.substring(3, habitNouns.length - 1) +
        r')\w*)',
    (_) => '0.5 ',
  );

  s = s.replaceAllMapped(
    _tensRe,
    (m) =>
        '${_tens[m[1]!.toLowerCase()]! + (_small[m[2]?.toLowerCase()] ?? 0)}',
  );
  s = s.replaceAllMapped(_smallRe, (m) => '${_small[m[1]!.toLowerCase()]}');
  s = s.replaceAllMapped(_hindiRe, (m) => '${_hindi[m[1]!.toLowerCase()]}');
  sub(r'(\d),(?=\d{2,3}(?:\D|$))', (m) => m[1]!);
  sub(r'\b(\d+) and a half\b', (m) => '${m[1]}.5');
  // "one hundred and two cigarettes" is ₹100 and 2 cigarettes, not 102.
  sub(
    r'\b(?:(\d{1,2}) |an? )?hundred\b(?: (?:and )?(\d{1,2})\b(?![:.]\d| ?' +
        habitNouns +
        r'))?',
    (m) => '${int.parse(m[1] ?? '1') * 100 + int.parse(m[2] ?? '0')}',
  );
  sub(
    r'\b(?:(\d{1,3}) |an? )thousand\b(?: (?:and )?(\d{1,3})\b(?! ?' +
        habitNouns +
        r'))?',
    (m) => '${int.parse(m[1] ?? '1') * 1000 + int.parse(m[2] ?? '0')}',
  );
  sub(r'\b(\d{1,3})k(?= steps)', (m) => '${m[1]}000');
  sub(r'\b(\d+) point (\d+)\b', (m) => '${m[1]}.${m[2]}');

  // Clocks.
  sub(r'\bhalf past (\d{1,2})\b', (m) => '${m[1]}:30');
  sub(r'\bquarter past (\d{1,2})\b', (m) => '${m[1]}:15');
  sub(r'\bquarter to (\d{1,2})\b', (m) {
    final h = int.parse(m[1]!);
    return '${h <= 1 ? 12 : h - 1}:45';
  });
  sub(r'\b(\d{1,2}) (?:oh|o) (\d)\b', (m) => '${m[1]}:0${m[2]}');
  sub(r"\b(\d{1,2}) o'? ?clock\b", (m) => '${m[1]}:00');
  const hm = r'([01]?\d|2[0-3]) ([0-5]\d)\b';
  sub(
    r'\b(at|around|about|roughly|slept|woke up|woke|reached|arrived) ' +
        hm +
        r'(?! ?(?:' +
        _money +
        r'|steps|ml|min|hours?|g\b|k))',
    (m) => '${m[1]} ${m[2]}:${m[3]}',
  );
  sub('\\b$hm(?= ?[ap]m\\b)', (m) => '${m[1]}:${m[2]}');
  sub(
    r'\b(\d{1,2}(?::\d{2})?) (?:in the (morning|afternoon|evening)|at (night))\b',
    (m) {
      final h = int.parse(m[1]!.split(':').first);
      if (h > 12) return m[1]!;
      final am =
          m[2]?.toLowerCase() == 'morning' ||
          (m[3] != null && (h == 12 || h < 5));
      return '${m[1]} ${am ? 'am' : 'pm'}';
    },
  );

  // Money: "1 50 rupees" is how 150 is spoken.
  sub('\\b([1-9]) (\\d{2})(?= ?$_money)', (m) => '${m[1]}${m[2]}');
  sub(r'(?<![\d.])(\d+(?:\.\d+)?) ?' + _money + r'(?!\w)(?! ?\d)', (m) {
    return '₹${m[1]}';
  });
  sub(r'(?:\b(?:rupees?|rs\.?|inr)|₹) ?(\d)', (m) => '₹${m[1]}');
  sub(r'(?<![\d.₹])(\d+(?:\.\d+)?) ?' + _money + r'(?!\w)', (m) {
    return '₹${m[1]}';
  });
  sub(r'(?<![\d.₹])(\d+(?:\.\d+)?) (?:ka|ki|ke)\b', (m) => '₹${m[1]}');

  sub(r'\blike (?=₹?\d)', (_) => '');

  // Units.
  sub(r'\b(\d+(?:\.\d+)?) ?(?:kilograms?|kilos?)\b', (m) => '${m[1]} kg');
  sub(r'\b(\d+(?:\.\d+)?) ?kilomet(?:er|re)s?\b', (m) => '${m[1]} km');
  sub(r'\b(\d+(?:\.\d+)?) ?millilit(?:er|re)s?\b', (m) => '${m[1]} ml');
  sub(r'\b(\d+(?:\.\d+)?) ?grams?\b', (m) => '${m[1]} g');
  sub(r'\b(\d+(?:\.\d+)?) ?(?:hours?|hrs?)\b', (m) {
    final min = double.parse(m[1]!) * 60;
    return '${min.round()} min';
  });
  sub(r'\b(\d+) out of 10\b', (m) => '${m[1]}/10');
  return s.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// One spoken item with its context resolved.
class SpeechClause {
  SpeechClause(this.text, {required this.sentence, this.joined = false});

  String text;
  final int sentence;

  /// Linked to the previous clause by "and" (or a synonym).
  final bool joined;
  bool plan = false;
  bool negated = false;
  SpeechTiming timing = const SpeechTiming();
}

enum SpeechDay { today, yesterday, dayBefore, lastNight, now }

/// Date words found in a clause, resolved against a clock on demand.
class SpeechTiming {
  const SpeechTiming([this._day]);
  final SpeechDay? _day;

  bool get isEmpty => _day == null;
  bool get justNow => _day == SpeechDay.now;

  String? date(DateTime nowIst, {String? time}) {
    final today = formatDate(nowIst);
    return switch (_day) {
      null => null,
      SpeechDay.today || SpeechDay.now => today,
      SpeechDay.yesterday => addDays(today, -1),
      SpeechDay.dayBefore => addDays(today, -2),
      SpeechDay.lastNight => addDays(
        today,
        // "last night at 00:30" already belongs to today.
        (minutesOf(time) ?? 1439) < 12 * 60 ? 0 : -1,
      ),
    };
  }
}

final _timings = <(RegExp, SpeechDay)>[
  (_re(r'\b(?:the )?day before yesterday\b'), SpeechDay.dayBefore),
  (_re(r'\b(?:last night|yesterday night)\b'), SpeechDay.lastNight),
  (_re(r'\byesterday(?: morning| afternoon| evening)?\b'), SpeechDay.yesterday),
  (_re(r'\b(?:just now|right now|abhi)\b'), SpeechDay.now),
  (
    _re(r'\b(?:today|aaj|this (?:morning|afternoon|evening))\b'),
    SpeechDay.today,
  ),
];

/// Pulls date words out of [text]; returns what is left.
(String, SpeechTiming) extractTiming(String text) {
  for (final (re, day) in _timings) {
    if (re.hasMatch(text)) {
      final rest = text.replaceAll(re, ' ').replaceAll(RegExp(r'\s+'), ' ');
      return (rest.trim(), SpeechTiming(day));
    }
  }
  return (text, const SpeechTiming());
}

final _approxRe = _re(
  r'(?:\b(?:around|about|roughly|approximately|approx|nearly|almost)\s+|~\s*)'
  r'(?=(?:at\s+)?₹?\d)',
);

/// Pulls "around / about / roughly / ~" off a number.
(String, bool) extractApprox(String text) =>
    (text.replaceAll(_approxRe, ''), _approxRe.hasMatch(text));

final _planRe = _re(
  r'\b(?:thinking (?:of|about)|thought of|plan(?:ning|ned)? (?:to|on)|might|'
  r"should (?:i|we)|(?:i|we)'ll|(?:i|we) will|"
  r'will (?:have|order|eat|drink|go|take|buy|get|smoke|do|be)|gonna|'
  r'about to|(?:want|need|have) to|tomorrow|'
  r"haven't|have not|hasn't)\b",
);
final _goingToRe = _re(r'\bgoing to\b');
final _completedCommuteRe = _re(
  r'\b(?:boarded|got on|got off) (?:the )?bus going to '
  r'(?:the )?(?:office|work|home)\b',
);
final _negatedRe = _re(
  r"\b(?:didn't|did not|don't|do not|never|skipped|without)\b|"
  r'^(?:(?:i|had|have)\s+)*(?:no|0)\s(?!wait)',
);
final _doneRe = _re(
  r'\b(?:had|spent|paid|drank|smoked|ate|ordered|walked|ran|took|reached|'
  r'arrived|boarded|slept|woke|bought|did|got)\b',
);

const _markers =
    r'(?:(?:oh|no|nope|wait|sorry|actually|i mean|i meant|correction|'
    r'or rather|rather|make (?:it|that))\b[\s,]*)+';
const _lead =
    r"(?:(?:it'?s|it was|that'?s|that was|i had|had|i spent|spent|only|just)"
    r'\s+)*';
const _token = r'(?:₹?\d+(?::\d{2}|\.\d+)?)';
final _midMarkerRe = _re('(?<=\\S)\\s+(?=$_markers$_lead$_token)');
final _correctionRe = _re('^$_markers($_lead)(.*)\$');
final _bareRe = _re('^($_token)\\s*([ap]m)?\$');

final _sentenceRe = RegExp(r'[.!?…]+(?=\s|$)|[;\n]+');
final _joinRe = _re(
  r'(?:\s*,\s*|\s*(?:[—–]|--)\s*|\s+-\s+|^|\s+)'
  r'(and|then|also|plus|aur|but)(?=\s|$)|'
  r'\s*,\s*|\s*(?:[—–]|--)\s*|\s+-\s+',
);
final _emptyRe = _re(r"^(?:i|i've|so|ok|okay|well|yeah|the|had|[^\w₹]*)$");

/// Splits already-normalized text, applies self-corrections, and marks plans,
/// negations and dates.
List<SpeechClause> splitSpeech(String normalized) {
  final out = <SpeechClause>[];
  var pendingCorrection = false;
  var sentence = 0;
  for (final sent in normalized.split(_sentenceRe)) {
    sentence++;
    var plan = false;
    var negated = false;
    var timing = const SpeechTiming();

    for (var (text, joiner) in _pieces(sent)) {
      if (joiner == 'but') plan = negated = false;
      var correcting = pendingCorrection;
      pendingCorrection = false;
      final c = _correctionRe.firstMatch(text);
      if (c != null) {
        final rest = c.group(2)!.trim();
        if (rest.isEmpty) {
          pendingCorrection = true;
          continue;
        }
        // "no cigarettes" is a negation, not a correction.
        if (RegExp(r'^₹?\d').hasMatch(rest)) {
          correcting = true;
          text = rest;
        }
      } else if (correcting) {
        text = text.replaceFirst(_re('^$_lead'), '');
      }
      if (_emptyRe.hasMatch(text)) continue;

      final (stripped, own) = extractTiming(text);
      final isPlan =
          _planRe.hasMatch(text) ||
          _goingToRe.hasMatch(text.replaceAll(_completedCommuteRe, ''));
      final isNegated = !isPlan && _negatedRe.hasMatch(stripped);
      // Plans and "didn't" carry over a list until something was done.
      if (isPlan || isNegated) {
        plan = isPlan;
        negated = isNegated;
      } else if (!own.isEmpty || _doneRe.hasMatch(text)) {
        plan = negated = false;
      }

      if (correcting && !plan && !negated) {
        final last = out.lastIndexWhere((x) => !x.plan && !x.negated);
        if (last >= 0 && _correct(out[last], stripped)) continue;
      }

      if (!own.isEmpty) {
        timing = own;
        // "two cigarettes and one tea yesterday" dates both.
        if (RegExp(r'\S').hasMatch(stripped) &&
            !_startsWithTiming(text) &&
            joiner == 'and') {
          for (final p in out.reversed) {
            if (p.sentence != sentence || !p.timing.isEmpty) break;
            p.timing = own;
            if (!p.joined) break;
          }
        }
      }
      if (_emptyRe.hasMatch(stripped)) continue;
      out.add(
        SpeechClause(
            plan || negated ? text : stripped,
            sentence: sentence,
            joined: joiner == 'and',
          )
          ..plan = plan
          ..negated = negated
          ..timing = timing,
      );
    }
  }
  return out;
}

bool _startsWithTiming(String text) =>
    _timings.any((t) => t.$1.matchAsPrefix(text) != null);

/// Pieces of a sentence with the word that joined each to the one before.
Iterable<(String, String?)> _pieces(String sentence) sync* {
  var start = 0;
  String? joiner;
  Iterable<(String, String?)> piece(String s, String? j) sync* {
    final parts = s.trim().split(_midMarkerRe);
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i].trim();
      if (p.isNotEmpty) yield (p, i == 0 ? j : null);
    }
  }

  for (final m in _joinRe.allMatches(sentence)) {
    final text = sentence.substring(start, m.start);
    yield* piece(text, joiner);
    final word = m.group(1)?.toLowerCase();
    joiner = switch (word) {
      'but' => 'but',
      null => text.trim().isEmpty ? joiner : null,
      _ => 'and',
    };
    start = m.end;
  }
  yield* piece(sentence.substring(start), joiner);
}

/// Applies correction [fix] to [target]; false when it isn't about it.
bool _correct(SpeechClause target, String fix) {
  final bare = _bareRe.firstMatch(fix);
  if (bare != null) {
    target.text = _override(target.text, bare.group(1)!, bare.group(2));
    return true;
  }
  if (_subject(fix).isEmpty || _subject(fix) != _subject(target.text)) {
    return false;
  }
  final numbers = RegExp(_token).allMatches(fix).toList();
  target.text = numbers.length == 1
      ? _override(target.text, numbers.single.group(0)!, null)
      : fix;
  return true;
}

String _override(String text, String value, String? meridiem) {
  final tokens = RegExp('(?<![\\d.:])$_token(?:\\s*[ap]m\\b)?')
      .allMatches(text)
      .toList();
  final newValue = meridiem == null ? value : '$value $meridiem';
  Match? hit;
  if (value.startsWith('₹')) {
    hit = tokens.where((t) => t.group(0)!.startsWith('₹')).lastOrNull;
    // "tea 20, sorry ₹15": a trailing number after the noun is the price.
    final last = tokens.lastOrNull;
    if (hit == null &&
        last != null &&
        last.start > 0 &&
        last.end == text.length) {
      hit = last;
    }
    if (hit == null) return '$text $value';
  } else if (tokens.isEmpty) {
    final habit = _re('\\b$habitNouns\\b').firstMatch(text);
    final isCount = habit != null && (double.tryParse(value) ?? 99) < 10;
    if (!isCount) return '$text $newValue';
    final head = text
        .substring(0, habit.start)
        .replaceFirst(_re(r'\ban?\s+$'), '');
    return '$head$value ${text.substring(habit.start)}';
  } else {
    // "2 cigarettes for 50, actually 3": replace whichever is nearer.
    double size(String s) =>
        double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final want = size(value);
    double gap(Match t) {
      final v = size(t.group(0)!);
      if (v <= 0 || want <= 0) return double.infinity;
      return v > want ? v / want : want / v;
    }

    hit = tokens.reduce((a, b) => gap(b) <= gap(a) ? b : a);
  }
  final old = hit.group(0)!;
  final rupee = old.startsWith('₹') && !value.startsWith('₹') ? '₹' : '';
  final oldMeridiem = _re(r'\s*[ap]m$').stringMatch(old) ?? '';
  return text.replaceRange(
    hit.start,
    hit.end,
    '$rupee$newValue${meridiem == null ? oldMeridiem : ''}',
  );
}

/// What a clause is about, ignoring counts, prices and filler.
String _subject(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'₹?\d+(?:[.:]\d+)?'), ' ')
    .replaceAll(
      RegExp(
        r'\b(?:i|had|have|smoked|drank|spent|paid|ate|took|on|for|at|a|an|'
        r'the|of|cups?|glass(?:es)?)\b',
      ),
      ' ',
    )
    .replaceAll(RegExp(r'\b(?:cigs?|cigarettes?)\b'), 'cigarette')
    .replaceAll(RegExp(r's\b'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
