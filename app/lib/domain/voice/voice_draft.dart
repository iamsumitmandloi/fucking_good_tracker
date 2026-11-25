import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../event.dart';
import '../event_type.dart';
import '../quicklog/parser.dart';
import 'speech_normalizer.dart';
import 'voice_contracts.dart';

RegExp _re(String p) => RegExp(p, caseSensitive: false);

final _lazyRe = _re(
  r'\s*\b(?:(?:with|via|on|by|using|through)\s+)?(?:lazy\s?pay|lp)\b',
);
final _habitRe = _re('\\b$habitNouns\\b');
final _clockRe = _re(
  r'(?:\b(?:at|@) ?)?(?<![\d.₹])(\d{1,2}(?:[:.]\d{2})? ?[ap]m|\d{1,2}:\d{2})\b',
);
final _bareAtRe = _re(r'\s*(?:\bat|@)\s*(\d{1,2})$');
final _sleepClockRe = _re(r'^slept (?:at )?(\d{1,2})(?::(\d{2}))?$');
final _spokenSpendRe = _re(r'\b(?:spent|spend|paid|bought|ordered)\b|₹');
final _verbRe = _re(
  r"^(?:(?:i|we|i've)\s+)?(?:had|spent|paid|drank|smoked|ate|ordered|walked|"
  r'ran|took|reached|boarded|slept|woke|bought|got|went|met)\b',
);

/// Builds a reviewable draft from a transcript, offline. Never throws.
class VoiceDraftBuilder implements VoiceDraftParser {
  const VoiceDraftBuilder();

  @override
  VoiceDraftResult parse({
    required String transcript,
    required DateTime nowIst,
    required double cigPrice,
    required double teaPrice,
    List<Event> recentEvents = const [],
  }) {
    final normalized = normalizeSpeech(transcript);
    final plans = <String>[];
    final warnings = <String>{};
    final drafts = <_Draft>[];

    for (final c in splitSpeech(normalized)) {
      if (c.plan) {
        plans.add(c.text);
        continue;
      }
      final parsed = c.negated
          ? [_note(c.text)]
          : _entries(c, nowIst, warnings);
      final prev = drafts.lastOrNull;
      // "samosa and chutney 30", "idli and dosa": one thing, not two.
      if (c.joined &&
          !c.negated &&
          prev != null &&
          prev.mergeable &&
          prev.clause.sentence == c.sentence &&
          !_verbRe.hasMatch(c.text) &&
          _continues(parsed)) {
        final whole = SpeechClause(
          '${prev.clause.text} and ${c.text}',
          sentence: c.sentence,
        )..timing = c.timing;
        drafts.last = _Draft(whole, _entries(whole, nowIst, warnings));
      } else {
        drafts.add(_Draft(c, parsed));
      }
    }

    final items = <VoiceDraftItem>[];
    var fallback = false;
    for (final d in drafts) {
      for (final e in d.entries) {
        fallback |= e.type == EventType.note;
        final date = d.clause.timing.date(nowIst, time: e.time);
        final repeatsPayment =
            e.type == EventType.spend &&
            e.label == 'Total' &&
            items.any(
              (item) =>
                  item.included &&
                  (item.entry.amount ?? 0) > 0 &&
                  _dateOf(item, nowIst) == (date ?? formatDate(nowIst)),
            );
        final item = VoiceDraftItem(
          entry: e,
          dateOverride: date,
          included: !repeatsPayment,
        );
        items.add(item);
        final dup = _duplicate(item, nowIst, recentEvents);
        if (dup != null) warnings.add(dup);
      }
    }
    return VoiceDraftResult(
      normalizedText: normalized,
      items: items,
      ignoredPlans: plans,
      warnings: warnings.toList(),
      hasUnparsedFallback: fallback,
    );
  }

  /// Included items as sheet rows: one event for each activity, one spend
  /// event for each payment. Unlike typed quick log, an unstated time stays
  /// unknown.
  List<Event> toEvents(
    Iterable<VoiceDraftItem> items, {
    required DateTime nowIst,
    required String Function() nextId,
  }) {
    final out = <Event>[];
    for (final item in items.where((i) => i.included)) {
      final e = item.entry;
      final date = _dateOf(item, nowIst);
      final paid = e.amount != null && e.amount! > 0;
      final isSpend = e.type == EventType.spend;
      if (!isSpend) {
        out.add(
          Event(
            id: nextId(),
            date: date,
            time: e.time,
            type: e.type,
            qty: e.qty,
            unit: e.unit,
            label: e.label,
            approx: e.approx,
            source: e.source,
            note: item.note ?? e.note,
          ),
        );
      }
      if (paid) {
        out.add(
          Event(
            id: nextId(),
            date: date,
            time: e.time,
            type: EventType.spend,
            label: isSpend ? e.label : e.spendLabel,
            amountInr: e.amount,
            category: e.category ?? SpendCategory.other,
            approx: e.approx,
            source: e.source,
            note: isSpend ? item.note ?? e.note : null,
          ),
        );
      }
    }
    return out;
  }
}

class _Draft {
  const _Draft(this.clause, this.entries);
  final SpeechClause clause;
  final List<ParsedEntry> entries;

  bool get mergeable =>
      !clause.negated &&
      entries.length == 1 &&
      entries.single.type == EventType.note;
}

bool _continues(List<ParsedEntry> parsed) {
  if (parsed.length != 1) return false;
  final e = parsed.single;
  return e.type == EventType.note ||
      ((e.type == EventType.spend || e.type == EventType.snack) &&
          e.amount != null &&
          e.label != 'Spend');
}

ParsedEntry _note(String text, {bool approx = false, String? source}) =>
    ParsedEntry(
      type: EventType.note,
      raw: text,
      note: text,
      approx: approx,
      source: source ?? 'voice',
    );

List<ParsedEntry> _entries(
  SpeechClause clause,
  DateTime nowIst,
  Set<String> warnings,
) {
  final lazy = _lazyRe.hasMatch(clause.text);
  final source = lazy ? 'lazypay' : 'voice';
  final (precise, approximate) = extractApprox(
    clause.text.replaceAll(_lazyRe, '').trim(),
  );
  final nowTime = clause.timing.justNow ? formatTime(nowIst) : null;
  final approx = nowTime == null && approximate;
  var s = _command(precise);

  // The typed grammar wants the clock last: "tea at 4:30 pm ₹20".
  final mid = _clockRe.firstMatch(s);
  if (mid != null && !s.startsWith(_re('woke|wake|up|awake|slept'))) {
    final rest = '${s.substring(0, mid.start)} ${s.substring(mid.end)}';
    s = '${_command(rest)} at ${mid.group(1)}';
  }

  final clock = _sleepClockRe.firstMatch(s);
  if (clock != null) {
    // No am/pm: nobody goes to bed at 11 in the morning.
    final h = int.parse(clock.group(1)!);
    final fixed = h == 12 ? 0 : (h >= 8 && h < 12 ? h + 12 : h);
    if (fixed != h && fixed < 24) {
      final t = '$fixed:${clock.group(2) ?? '00'}';
      s = 'slept $t';
      warnings.add('Check: assumed you slept at ${t.padLeft(5, '0')}');
    }
  } else {
    final at = _bareAtRe.firstMatch(s);
    if (at != null && !s.startsWith(_re('woke|wake|up|awake|slept'))) {
      final h = int.parse(at.group(1)!);
      final bus = s.startsWith(_re('bus|board|reach|arriv|got o'));
      final head = s.substring(0, at.start);
      if (h < 24 && (bus || h >= 13)) {
        s = '$head at $h:00';
      } else {
        // A bare hour could be am or pm, and is never a price.
        s = head;
        warnings.add('Time unclear: "${clause.text}". Set it if needed');
      }
    }
  }
  if (s.isEmpty) return [_note(clause.text, approx: approx, source: source)];

  // "half cigarette": the typed grammar only counts whole ones.
  double? fraction;
  final frac = _re('^(\\d*\\.\\d+) (?=$habitNouns\\b)').firstMatch(s);
  if (frac != null) {
    fraction = double.parse(frac.group(1)!);
    s = s.substring(frac.end);
  }

  // Zero defaults: a price that wasn't spoken must not be invented.
  final result = parseQuickLog(s, cigPrice: 0, teaPrice: 0);
  final splitTotal = result.splitTotal;
  final split = splitTotal != null && splitTotal > 0;

  return [
    for (final e in result.entries)
      _finish(
        split ? e.withAmount(null) : e,
        clause: clause,
        spoken: s,
        approx: approx,
        source: source,
        qty: fraction ?? e.qty,
        time: nowTime ?? e.time,
        single: result.entries.length == 1,
        warnings: warnings,
      ),
    if (split)
      ParsedEntry(
        type: EventType.spend,
        raw: clause.text,
        label: 'Combined payment',
        amount: splitTotal,
        category: SpendCategory.other,
        time: nowTime ?? result.entries.last.time,
        approx: approx || (nowTime == null && result.entries.last.approx),
        source: source,
      ),
  ];
}

ParsedEntry _finish(
  ParsedEntry e, {
  required SpeechClause clause,
  required String spoken,
  required bool approx,
  required String source,
  required double? qty,
  required String? time,
  required bool single,
  required Set<String> warnings,
}) {
  final raw = single ? clause.text : e.raw;
  var type = e.type;
  if (type == EventType.spend) {
    final explicit = _spokenSpendRe.hasMatch('${clause.text} $spoken');
    if (!explicit && e.label == 'Spend') {
      type = EventType.note; // a lone number means nothing
    } else if (!explicit && e.category == SpendCategory.other) {
      warnings.add(
        'Check: "$raw" was read as ₹${trimNum(e.amount, digits: 2)}',
      );
    }
  }
  final zero = qty == 0;
  final zeroHabit =
      zero &&
      (type == EventType.cigarette ||
          type == EventType.tea ||
          type == EventType.coffee);
  if (type == EventType.note || zeroHabit) {
    return ParsedEntry(
      type: EventType.note,
      raw: raw,
      note: raw,
      time: time,
      approx: approx,
      source: source,
    );
  }
  var amount = e.amount == 0 ? null : e.amount;
  if (amount != null && qty != null && _re(r'\beach\b').hasMatch(clause.text)) {
    amount *= qty;
  }
  return ParsedEntry(
    type: type,
    raw: raw,
    qty: qty,
    unit: e.unit,
    label: e.label,
    amount: amount,
    category: e.category,
    time: time,
    approx: !clause.timing.justNow && (approx || e.approx),
    note: e.note,
    source: source,
  );
}

/// Spoken phrasing → the typed quick-log grammar ("I spent ₹50 on tea" →
/// "tea ₹50").
String _command(String text) {
  var s = text.trim();
  void sub(String p, [String to = '']) => s = s.replaceFirst(_re(p), to);

  sub(r'^(?:(?:so|ok|okay|well|yeah|please|log|add|maine)\s+)+');
  sub(r'^(?:(?:i|we)\s+(?:have\s+)?|i\x27ve\s+)');
  sub(r'^(?:also|just|actually|already)\s+');
  sub(r'\s+(?:please|too|as well|each|piya|peeya|pi|khaya|liya)$');
  sub(r'^my\s+');

  final smoked = _re(r'^smoked\s+(.*)$').firstMatch(s);
  if (smoked != null) {
    s = smoked.group(1)!;
    if (RegExp(r'^\d+$').hasMatch(s)) s = '$s cigarettes';
  }
  if (_re(r'^took\b').hasMatch(s) && _habitRe.hasMatch(s)) sub(r'^took\s+');
  sub(r'^(?:had|have|drank|ate|bought|ordered)\s+');
  sub(r'^(?:walked|did)\s+(?=\d+\s+steps)');
  sub(r'^(?:an?|some)\s+(?=\S)');
  if (_habitRe.hasMatch(s)) sub(r'\b(?:cups?|glass(?:es)?) of\s+');
  sub(r'^glass(?=(?:es)? of water)', '1 glass');
  sub(r'(?<=\d (?:ml|l|litre|liter)) of(?= water)');
  sub(r'(?<=\d g) of(?= protein)');
  final score = _re(
    r'^(?:my )?(weight|energy|mood)(?: level)? (?:is|was)\s+(.*)$',
  ).firstMatch(text.trim());
  if (score != null) s = '${score.group(1)} ${score.group(2)}';
  sub(r'^(?:weigh|weighed)(?= \d)', 'weight');
  sub(r'^(?:went to (?:sleep|bed)|fell asleep|sleep|asleep)\b', 'slept');
  sub(r'^got to(?= (?:the )?(?:office|home|work))', 'reached');
  sub(r'(?<=^reached |^arrived |^arrived at )(?:the )(?=office|work)');
  sub(r'^got off (?:the )?bus', 'got off');
  sub(r'(?<=\bbus )going (?=to )');
  sub(r'(?<=^(?:walk(?:ed)?|gym|run|ran|jogged|yoga|cycled|exercise)) for\b');

  // Money phrasing.
  final spent = _re(
    r'^(?:spent|spend|paid)\s+₹?(\d+(?:\.\d+)?)'
    r'(?:\s+(?:on|for|to|at|in)\s+(.+))?$',
  ).firstMatch(s);
  if (spent != null) {
    final what = spent.group(2);
    return what == null
        ? '₹${spent.group(1)}'
        : '${_command(what)} ₹${spent.group(1)}';
  }
  final lead = _re(
    r'^(?:₹(\d+(?:\.\d+)?)(?:\s+(?:on|for|of))?|(\d+(?:\.\d+)?)\s+(?:on|for))'
    r'\s+(.+)$',
  ).firstMatch(s);
  if (lead != null) {
    return '${_command(lead.group(3)!)} ₹${lead.group(1) ?? lead.group(2)}';
  }
  sub(r'\s+each$');
  sub(r'\s+(?:for|at)\s+(?=₹\d+(?:\.\d+)?$)', ' ');
  final priced = _re(r'\s+for\s+(\d+(?:\.\d+)?)$').firstMatch(s);
  if (priced != null) s = '${s.substring(0, priced.start)} ₹${priced.group(1)}';
  final placed = _re(
    r'^(.+) for ₹?(\d+(?:\.\d+)?) ((?:in|at|from) (?:the )?[a-z].*)$',
  ).firstMatch(s);
  if (placed != null) {
    s = '${placed.group(1)} ${placed.group(3)} ₹${placed.group(2)}';
  }
  return s.trim();
}

String _dateOf(VoiceDraftItem item, DateTime nowIst) {
  if (item.dateOverride != null) return item.dateOverride!;
  final today = formatDate(nowIst);
  final m = minutesOf(item.entry.time);
  // "slept 23:30" logged in the morning was last night.
  final later = m != null && m > nowIst.hour * 60 + nowIst.minute + 5;
  return later ? addDays(today, -1) : today;
}

String? _duplicate(VoiceDraftItem item, DateTime nowIst, List<Event> recent) {
  final e = item.entry;
  if (e.type == EventType.note) return null;
  final date = _dateOf(item, nowIst);
  final today = formatDate(nowIst);
  final at = minutesOf(e.time ?? (date == today ? formatTime(nowIst) : null));
  String key(String? s) => (s ?? '').trim().toLowerCase();

  for (final r in recent.where((r) => r.date == date)) {
    if (r.type == e.type && key(r.label) == key(e.label)) {
      final name = switch (e.type) {
        EventType.cigarette => 'Cigarette',
        EventType.tea => 'Tea',
        EventType.coffee => 'Coffee',
        EventType.waterMl => 'water',
        EventType.busBoard => 'boarding the bus',
        EventType.busArrive => 'getting off the bus',
        _ => e.label ?? e.type.wire.replaceAll('_', ' '),
      };
      return 'You already logged $name ${date == today ? 'today' : 'on $date'}';
    }
    final rAt = minutesOf(r.time);
    if (e.amount != null &&
        r.amountInr == e.amount &&
        at != null &&
        rAt != null &&
        (at - rAt).abs() <= 15) {
      return '₹${trimNum(e.amount, digits: 2)} was already logged at ${r.time}';
    }
  }
  return null;
}
