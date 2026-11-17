import 'package:equatable/equatable.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../derivations/daily_stats.dart';
import '../event_type.dart';

/// One event the quick-log text turned into, before date/time are applied.
class ParsedEntry extends Equatable {
  const ParsedEntry({
    required this.type,
    required this.raw,
    this.qty,
    this.unit,
    this.label,
    this.amount,
    this.category,
    this.time,
    this.approx = false,
    this.note,
    this.source = 'app',
  });

  final EventType type;
  final String raw;
  final double? qty;
  final String? unit;
  final String? label;
  final double? amount;
  final String? category;

  /// Explicit `HH:mm` from the text ("slept 22:30", "tea at 16:30").
  final String? time;
  final bool approx;
  final String? note;
  final String source;

  ParsedEntry withAmount(double? a) => ParsedEntry(
    type: type,
    raw: raw,
    qty: qty,
    unit: unit,
    label: label,
    amount: a,
    category: category,
    time: time,
    approx: approx,
    note: note,
    source: source,
  );

  /// Preview line, e.g. "Cigarette × 1".
  String get title {
    final n = trimNum(qty ?? 1);
    String t(String s) => time == null ? s : '$s $time';
    return switch (type) {
      EventType.cigarette => 'Cigarette × $n',
      EventType.tea => 'Tea × $n',
      EventType.coffee => 'Coffee × $n',
      EventType.waterMl => '${trimNum(qty)} ml water',
      EventType.weight => 'Weight ${trimNum(qty, digits: 2)} kg',
      EventType.sleep => t('Slept'),
      EventType.wake => t('Woke'),
      EventType.busBoard => t('Boarded bus'),
      EventType.busArrive => t('Got off the bus'),
      EventType.steps => '${trimNum(qty, digits: 0)} steps',
      EventType.exercise =>
        '${label ?? 'Exercise'}${qty == null ? '' : ' ${trimNum(qty)} min'}',
      EventType.energy => 'Energy ${trimNum(qty)}/10',
      EventType.mood => 'Mood ${trimNum(qty)}/10',
      EventType.supplement => 'Supplement · ${label ?? ''}',
      EventType.meal || EventType.snack when unit == 'g' =>
        '$proteinLabel ${trimNum(qty)} g',
      EventType.meal || EventType.snack => label ?? 'Meal',
      EventType.spend => label ?? 'Spend',
      EventType.note => 'Note: "${note ?? raw}"',
      _ => label ?? type.wire,
    };
  }

  @override
  List<Object?> get props => [
    type,
    qty,
    unit,
    label,
    amount,
    category,
    time,
    approx,
    note,
    source,
  ];
}

class ParseResult {
  const ParseResult(this.entries, {this.splitTotal});

  final List<ParsedEntry> entries;

  /// Set when one trailing amount was split across several items.
  final double? splitTotal;

  double? get total {
    final paid = entries.where((e) => e.amount != null);
    if (paid.isEmpty) return null;
    return paid.fold<double>(0, (a, e) => a + e.amount!);
  }
}

// ---------------------------------------------------------------- grammar --

const _time = r'(\d{1,2})(?:[:.](\d{2}))\s*(am|pm)?|(\d{1,2})\s*(am|pm)';
const _amt = r'(?:₹|rs\.?\s*)?(\d+(?:\.\d+)?)';

final _approxRe = RegExp(r'~|\b(?:approx|approximately|around|about|abt)\b');
final _lazyRe = RegExp(r'\b(?:lazy\s?pay|lp)\b');
final _atTimeRe = RegExp('(?:^|\\s)(?:at|@)\\s*(?:$_time)\\s*\$');

final _sleepRe = RegExp(
  '^(?:slept|sleep|bed|asleep|went to bed|in bed)\\s*(?:at\\s*)?(?:$_time)\$',
);
final _wakeRe = RegExp(
  '^(?:woke(?: up)?|wake(?: up)?|up|awake)\\s*(?:at\\s*)?(?:$_time)\$',
);
final _boardRe = RegExp(
  '^(?:board(?:ed)?|on (?:the )?bus|got on(?: the)? bus|bus)'
  '(?:\\s+(?:to\\s+)?(?:office|home|work))?\\s*(?:at\\s*)?(?:$_time)?\$',
);
final _arriveRe = RegExp(
  '^(?:(?:office|home|work)\\s+)?(?:reached|arrived|arrive|reach|got off)'
  '(?:\\s+(?:at\\s+)?(?:office|home|work))?\\s*(?:at\\s*)?(?:$_time)?\$',
);
final _weightRe = RegExp(
  r'^(?:weight|wt|weighed)\s*:?\s*(\d+(?:\.\d+)?)\s*(?:kgs?)?$|^(\d+(?:\.\d+)?)\s*kgs?$',
);
final _stepsRe = RegExp(r'^steps\s*:?\s*([\d,]+)$|^([\d,]+)\s*steps$');
final _scoreRe = RegExp(r'^(energy|mood)\s*:?\s*(\d+)(?:\s*/\s*10)?$');
final _waterRe = RegExp(
  r'^water\s*(\d+(?:\.\d+)?)?\s*(ml|l|ltr|litres?|liters?|glass(?:es)?)?$'
  r'|^(\d+(?:\.\d+)?)\s*(ml|l|ltr|litres?|liters?|glass(?:es)?)\s*(?:of\s+)?water$',
);
final _proteinRe = RegExp(
  r'^(?:(?:bkfst|breakfast)\s+)?protein\s*(\d+(?:\.\d+)?)\s*g?$|^(\d+(?:\.\d+)?)\s*g\s+protein$',
);
final _exerciseRe = RegExp(
  r'^(walk(?:ed)?|gym|run|ran|jog(?:ged)?|exercise|workout|yoga|cycl(?:ing|ed))'
  r'\s*(\d+)?\s*(?:min|mins|minutes|m)?$',
);
final _cigRe = RegExp(
  '^(\\d+)?\\s*(?:cigs?|cigarettes?|smokes?|sutta|ciggies?)'
  '(?:\\s*[x×]\\s*(\\d+))?(?:\\s+$_amt)?\$',
);
final _drinkRe = RegExp(
  '^(\\d+)?\\s*(teas?|chai|coffees?)(?:\\s*[x×]\\s*(\\d+))?(?:\\s+$_amt)?\$',
);
final _mealRe = RegExp(r'^(breakfast|bkfst|lunch|dinner|snacks?)\b\s*(.*)$');
final _suppRe = RegExp(r'^(?:supp(?:lement)?s?|took)\s+(.+)$');
final _amountOnlyRe = RegExp('^$_amt\$');
final _textAmountRe = RegExp('^(.*?[a-z].*?)\\s+$_amt\$');
final _trailingAmtRe = RegExp('^(.*?)\\s*$_amt\$');

const _categoryWords = <String, List<String>>{
  SpendCategory.delivery: [
    'zomato', 'swiggy', 'zepto', 'blinkit', 'instamart', 'bigbasket', //
    'dunzo', 'delivery', 'order',
  ],
  SpendCategory.canteen: ['canteen', 'mess', 'office food'],
  SpendCategory.streetFood: [
    'pani puri', 'panipuri', 'golgappa', 'vada pav', 'vada', 'momos', //
    'samosa', 'chaat', 'bhel', 'kachori', 'pav bhaji', 'street', 'jeera',
  ],
  SpendCategory.groceries: [
    'grocery', 'groceries', 'milk', 'eggs', 'bread', 'vegetables', //
    'veggies', 'fruit', 'dmart', 'whey',
  ],
  SpendCategory.transport: [
    'auto', 'uber', 'ola', 'rapido', 'metro', 'ticket', 'cab', 'fuel', //
    'petrol', 'pass',
  ],
  SpendCategory.grooming: ['haircut', 'salon', 'barber', 'shave'],
  SpendCategory.bills: [
    'bill', 'electricity', 'recharge', 'rent', 'wifi', 'internet', 'emi',
  ],
  SpendCategory.tobacco: ['lighter', 'pack'],
  SpendCategory.tea: ['tea', 'chai'],
};

String categoryFor(String text) {
  final t = text.toLowerCase();
  for (final e in _categoryWords.entries) {
    for (final w in e.value) {
      if (RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(t)) return e.key;
    }
  }
  return SpendCategory.other;
}

String? _timeFrom(Match m, int first) {
  // Groups: h, mm, ampm | h, ampm
  final h1 = m.group(first);
  final mm = m.group(first + 1);
  final ap1 = m.group(first + 2);
  final h2 = m.group(first + 3);
  final ap2 = m.group(first + 4);
  int h;
  int min;
  String? ap;
  if (h1 != null) {
    h = int.parse(h1);
    min = int.parse(mm!);
    ap = ap1;
  } else if (h2 != null) {
    h = int.parse(h2);
    min = 0;
    ap = ap2;
  } else {
    return null;
  }
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (h > 24 || min > 59) return null;
  if (h == 24) h = 0;
  return hhmmOf(h * 60 + min);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

double? _num(String? s) => s == null ? null : double.tryParse(s.replaceAll(',', ''));

/// Parses free text like "1 cig + tea 45" into events (PRD §4).
/// Never throws: anything it can't read becomes a `note`.
ParseResult parseQuickLog(
  String input, {
  required double cigPrice,
  required double teaPrice,
}) {
  final segments = input
      .split(RegExp(r'\s*[+,;]\s*|\s+&\s+|\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final entries = <ParsedEntry>[];
  final explicitAmount = <bool>[];
  for (final seg in segments) {
    final r = _parseSegment(seg, cigPrice: cigPrice, teaPrice: teaPrice);
    entries.add(r.$1);
    explicitAmount.add(r.$2);
  }

  // "1 cig + tea 45": one trailing amount on a combo of habit items is the
  // total for the whole payment. Price the others at their defaults and give
  // the last item the remainder.
  double? split;
  if (entries.length >= 2 &&
      explicitAmount.last &&
      explicitAmount.take(entries.length - 1).every((x) => !x) &&
      entries.every(_isHabit)) {
    final total = entries.last.amount!;
    final others = entries
        .take(entries.length - 1)
        .fold<double>(0, (a, e) => a + (e.amount ?? 0));
    if (others <= total) {
      entries[entries.length - 1] = entries.last.withAmount(total - others);
      split = total;
    }
  }
  return ParseResult(entries, splitTotal: split);
}

bool _isHabit(ParsedEntry e) =>
    e.type == EventType.cigarette ||
    e.type == EventType.tea ||
    e.type == EventType.coffee;

/// Returns the entry and whether its amount was typed (not a default).
(ParsedEntry, bool) _parseSegment(
  String original, {
  required double cigPrice,
  required double teaPrice,
}) {
  var s = original.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final approx = _approxRe.hasMatch(s);
  s = s.replaceAll(_approxRe, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final lazy = _lazyRe.hasMatch(s);
  s = s.replaceAll(_lazyRe, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final source = lazy ? 'lazypay' : 'app';

  ParsedEntry e(
    EventType type, {
    double? qty,
    String? unit,
    String? label,
    double? amount,
    String? category,
    String? time,
    String? note,
  }) => ParsedEntry(
    type: type,
    raw: original,
    qty: qty,
    unit: unit,
    label: label,
    amount: amount,
    category: category,
    time: time,
    approx: approx,
    note: note,
    source: source,
  );

  Match? m;
  if ((m = _sleepRe.firstMatch(s)) != null) {
    return (e(EventType.sleep, time: _timeFrom(m!, 1)), false);
  }
  if ((m = _wakeRe.firstMatch(s)) != null) {
    return (e(EventType.wake, time: _timeFrom(m!, 1)), false);
  }
  if ((m = _boardRe.firstMatch(s)) != null) {
    return (e(EventType.busBoard, time: _timeFrom(m!, 1)), false);
  }
  if ((m = _arriveRe.firstMatch(s)) != null) {
    return (e(EventType.busArrive, time: _timeFrom(m!, 1)), false);
  }

  // "tea at 16:30": peel the time off, then parse the rest.
  String? at;
  final atM = _atTimeRe.firstMatch(s);
  if (atM != null) {
    at = _timeFrom(atM, 1);
    s = s.substring(0, atM.start).trim();
  }

  if ((m = _weightRe.firstMatch(s)) != null) {
    final kg = _num(m!.group(1) ?? m.group(2));
    if (kg != null && kg >= 20 && kg <= 300) {
      return (e(EventType.weight, qty: kg, unit: 'kg', time: at), false);
    }
  }
  if ((m = _stepsRe.firstMatch(s)) != null) {
    return (
      e(EventType.steps, qty: _num(m!.group(1) ?? m.group(2)), unit: 'steps', time: at),
      false,
    );
  }
  if ((m = _scoreRe.firstMatch(s)) != null) {
    final v = _num(m!.group(2));
    if (v != null && v >= 1 && v <= 10) {
      return (
        e(m.group(1) == 'energy' ? EventType.energy : EventType.mood, qty: v, time: at),
        false,
      );
    }
  }
  if ((m = _waterRe.firstMatch(s)) != null) {
    final v = _num(m!.group(1) ?? m.group(3));
    final unit = m.group(2) ?? m.group(4);
    double ml;
    if (v == null) {
      ml = 250;
    } else if (unit == null) {
      ml = v <= 5 ? v * 1000 : v; // "water 2" = 2 L, "water 500" = 500 ml
    } else if (unit.startsWith('glass')) {
      ml = v * 250;
    } else if (unit == 'ml') {
      ml = v;
    } else {
      ml = v * 1000;
    }
    return (e(EventType.waterMl, qty: ml, unit: 'ml', time: at), false);
  }
  if ((m = _proteinRe.firstMatch(s)) != null) {
    return (
      e(EventType.meal, qty: _num(m!.group(1) ?? m.group(2)), unit: 'g', label: proteinLabel, time: at),
      false,
    );
  }
  if ((m = _exerciseRe.firstMatch(s)) != null) {
    final kind = m!.group(1)!;
    final label = switch (kind) {
      'walked' => 'Walk',
      'ran' => 'Run',
      'jogged' => 'Jog',
      'cycled' => 'Cycling',
      _ => _cap(kind),
    };
    return (
      e(EventType.exercise, qty: _num(m.group(2)), unit: 'min', label: label, time: at),
      false,
    );
  }
  if ((m = _cigRe.firstMatch(s)) != null) {
    final n = _num(m!.group(1) ?? m.group(2)) ?? 1;
    final typed = _num(m.group(3));
    return (
      e(
        EventType.cigarette,
        qty: n,
        unit: 'cig',
        amount: typed ?? cigPrice * n,
        category: SpendCategory.tobacco,
        time: at,
      ),
      typed != null,
    );
  }
  if ((m = _drinkRe.firstMatch(s)) != null) {
    final coffee = m!.group(2)!.startsWith('coffee');
    final n = _num(m.group(1) ?? m.group(3)) ?? 1;
    final typed = _num(m.group(4));
    return (
      e(
        coffee ? EventType.coffee : EventType.tea,
        qty: n,
        unit: 'cup',
        amount: typed ?? (coffee ? null : teaPrice * n),
        category: SpendCategory.tea,
        time: at,
      ),
      typed != null,
    );
  }
  if ((m = _mealRe.firstMatch(s)) != null) {
    var kind = m!.group(1)!;
    if (kind == 'bkfst') kind = 'breakfast';
    if (kind == 'snacks') kind = 'snack';
    var rest = m.group(2)!.trim();
    double? amount;
    final t = _trailingAmtRe.firstMatch(rest);
    if (t != null) {
      amount = _num(t.group(2));
      rest = t.group(1)!.trim();
    }
    final label = rest.isEmpty ? _cap(kind) : '${_cap(rest)} $kind';
    return (
      e(
        kind == 'snack' ? EventType.snack : EventType.meal,
        label: label,
        amount: amount,
        category: amount == null ? null : categoryFor(rest.isEmpty ? kind : rest),
        note: kind,
        time: at,
      ),
      amount != null,
    );
  }
  if ((m = _suppRe.firstMatch(s)) != null) {
    return (e(EventType.supplement, label: _cap(m!.group(1)!.trim()), time: at), false);
  }
  if ((m = _amountOnlyRe.firstMatch(s)) != null) {
    return (
      e(EventType.spend, label: 'Spend', amount: _num(m!.group(1)), category: SpendCategory.other, time: at),
      true,
    );
  }
  if ((m = _textAmountRe.firstMatch(s)) != null) {
    final text = m!.group(1)!.trim();
    final cat = categoryFor(text);
    final street = cat == SpendCategory.streetFood;
    return (
      e(
        street ? EventType.snack : EventType.spend,
        label: _cap(text),
        amount: _num(m.group(2)),
        category: cat,
        note: street ? 'snack' : null,
        time: at,
      ),
      true,
    );
  }
  return (
    ParsedEntry(type: EventType.note, raw: original, note: original.trim(), approx: approx, source: source),
    false,
  );
}
