import 'package:equatable/equatable.dart';

import '../../core/cells.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../derivations/daily_stats.dart';
import '../event.dart';
import '../event_type.dart';
import '../quicklog/parser.dart';
import 'legacy_cell.dart';

/// A data problem in a legacy row, shown to the user rather than fixed.
class LegacyFlag extends Equatable {
  const LegacyFlag({required this.date, required this.text});

  final String date;
  final String text;

  @override
  List<Object?> get props => [date, text];
}

/// What the legacy tabs contribute: read-only synthetic events (source
/// `legacy`, never posted), sleep hours for nights without bed/wake times,
/// and data-bug flags.
class LegacyImport extends Equatable {
  const LegacyImport({
    this.events = const [],
    this.sleepHours = const {},
    this.flags = const [],
  });

  static const empty = LegacyImport();

  final List<Event> events;

  /// Daily Summary sleep hours by date (the morning the night ended).
  final Map<String, LegacyCell> sleepHours;
  final List<LegacyFlag> flags;

  @override
  List<Object?> get props => [events, sleepHours, flags];
}

// ------------------------------------------------------------- headers --

/// Column headers are unknown until the owner's live read, so columns are
/// found by name pattern. Matching is on lower-case letters/digits only.
String _norm(String h) => h.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

String? _col(Iterable<String> headers, List<String> patterns) {
  for (final p in patterns) {
    for (final h in headers) {
      if (h == '_row') continue;
      final n = _norm(h);
      if (p.startsWith('=') ? n == p.substring(1) : n.contains(p)) return h;
    }
  }
  return null;
}

/// First clock time in a cell: "~01:30", "1:30 am", "22.30" → `HH:mm`.
String? _clock(String raw) {
  final m = RegExp(
    r'(\d{1,2})[:.](\d{2})\s*(am|pm)?',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m == null) return null;
  var h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  final ap = m[3]?.toLowerCase();
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (h > 23 || min > 59) return null;
  return hhmmOf(h * 60 + min);
}

bool _isApprox(String raw) =>
    raw.contains('~') ||
    raw.contains('≈') ||
    RegExp(r'\d\s*[–—-]\s*\d').hasMatch(raw);

Set<String> _headers(List<Map<String, dynamic>> rows) => {
  for (final r in rows) ...r.keys,
};

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// `yyyy-MM-dd`, `d/M/yyyy`, "16 Nov 2026", "Mon 16 Nov", "16-Nov".
/// A date without a year takes [year]. Null for anything else.
String? legacyDate(Object? cell, {required int year}) {
  final iso = cellDate(cell);
  if (iso != null) return iso;
  final s = cellStr(cell).toLowerCase();
  final m = RegExp(r'(\d{1,2})[\s\-/]*([a-z]{3})[a-z]*\.?(?:[\s\-/,]*(\d{4}))?')
      .firstMatch(s);
  if (m == null) return null;
  final mo = _months[m[2]];
  if (mo == null) return null;
  final d = parseDate('${m[3] ?? year}-$mo-${m[1]}');
  return d == null ? null : formatDate(d);
}

// ------------------------------------------------------------- adapter --

int _seq = 0;

Event _ev(
  String tab,
  Object? row,
  String field,
  String date,
  EventType type, {
  String? time,
  double? qty,
  String? unit,
  String? label,
  double? amount,
  String? category,
  bool approx = false,
  String? source,
  String? note,
}) => Event(
  // Stable per cell; never starts with dev-, never enters the outbox.
  id: 'legacy-${_norm(tab)}-${row ?? 'r${_seq++}'}-$field',
  date: date,
  time: time,
  type: type,
  qty: qty,
  unit: unit,
  label: label,
  amountInr: amount,
  category: category,
  approx: approx,
  source: source ?? 'legacy',
  note: note,
);

/// Legacy rows by tab → synthetic events. Never throws; rows it can't read
/// are skipped.
LegacyImport adaptLegacy(
  Map<String, List<Map<String, dynamic>>> tabs, {
  required int year,
  double cigPrice = 25,
  double teaPrice = 20,
}) {
  final events = <Event>[];
  final sleep = <String, LegacyCell>{};
  final flags = <LegacyFlag>[];
  try {
    _daily(tabs['Daily Summary'] ?? const [], year, events, sleep, flags);
  } on Object {
    // Unknown shape: skip the tab rather than break the screen.
  }
  try {
    _spending(tabs['Spending'] ?? const [], year, events);
  } on Object {
    // as above
  }
  return LegacyImport(events: events, sleepHours: sleep, flags: flags);
}

void _daily(
  List<Map<String, dynamic>> rows,
  int year,
  List<Event> out,
  Map<String, LegacyCell> sleep,
  List<LegacyFlag> flags,
) {
  if (rows.isEmpty) return;
  final h = _headers(rows);
  final cDate = _col(h, ['=date', '=day', 'date']);
  if (cDate == null) return;
  final cCig = _col(h, ['cig', 'smok']);
  // "Sleep hours" / "Sleep (h)"; never "Sleep start" or "Sleep quality".
  final cSleep = _col(h, ['sleeph', '=sleep']);
  final cBed = _col(h, ['sleepstart', 'bedtime', '=bed', 'asleepat']);
  final cWake = _col(h, ['=wake', 'waketime', 'wakeup', 'woke']);
  final cWeight = _col(h, ['weight', '=wt', '=kg']);
  final cSteps = _col(h, ['step']);
  final cWater = _col(h, ['water']);
  final cTea = _col(h, ['teacup', '=tea', '=teas']);
  final cProtein = _col(h, ['protein']);
  final cEnergy = _col(h, ['energy']);
  final cCommute = _col(h, ['commute', 'bus', 'travel']);
  const tab = 'Daily Summary';

  for (final r in rows) {
    final date = legacyDate(r[cDate], year: year);
    if (date == null) continue;
    final row = r['_row'];
    LegacyCell cell(String? c) =>
        c == null ? const LegacyCell() : parseLegacyCell(r[c]);

    final cig = cell(cCig);
    if (cig.value != null) {
      out.add(
        _ev(
          tab,
          row,
          'cig',
          date,
          EventType.cigarette,
          qty: cig.value,
          unit: 'cig',
          approx: cig.approx,
        ),
      );
    }
    final w = cell(cWeight);
    if (w.value != null && w.value! >= 20 && w.value! <= 300) {
      out.add(
        _ev(
          tab,
          row,
          'weight',
          date,
          EventType.weight,
          qty: w.value,
          unit: 'kg',
          approx: w.approx,
        ),
      );
    }
    final steps = cell(cSteps);
    if (steps.value != null) {
      out.add(
        _ev(
          tab,
          row,
          'steps',
          date,
          EventType.steps,
          qty: steps.value,
          unit: 'steps',
          approx: steps.approx,
        ),
      );
    }
    final water = cell(cWater);
    if (water.value != null) {
      // "2 L" / "2000 ml": small numbers are litres.
      final ml = water.value! <= 10 ? water.value! * 1000 : water.value!;
      out.add(
        _ev(
          tab,
          row,
          'water',
          date,
          EventType.waterMl,
          qty: ml,
          unit: 'ml',
          approx: water.approx,
        ),
      );
    }
    final energy = cell(cEnergy);
    // Words ("Okay", "Good overall") still mean it was logged: keep the
    // text, no number (never a made-up score).
    final energyNum =
        energy.value != null && energy.value! >= 1 && energy.value! <= 10;
    if (energyNum || energy.raw.isNotEmpty && !_naCell(energy.raw)) {
      out.add(
        _ev(
          tab,
          row,
          'energy',
          date,
          EventType.energy,
          qty: energyNum ? energy.value : null,
          approx: energy.approx,
          note: energyNum ? null : energy.raw,
        ),
      );
    }
    final s = cell(cSleep);
    if (s.value != null && s.value! > 0 && s.value! <= 16) sleep[date] = s;

    final tea = cell(cTea);
    if (tea.value != null) {
      out.add(
        _ev(
          tab,
          row,
          'tea',
          date,
          EventType.tea,
          qty: tea.value,
          unit: 'cup',
          approx: tea.approx,
        ),
      );
    }
    final protein = cell(cProtein);
    if (protein.value != null) {
      out.add(
        _ev(
          tab,
          row,
          'protein',
          date,
          EventType.meal,
          qty: protein.value,
          unit: 'g',
          label: proteinLabel,
          approx: protein.approx,
        ),
      );
    }

    // Each row is the night that ended that morning (checked on the live
    // sheet: start → wake equals "Sleep hours" on every row). An evening
    // bedtime belongs to the day before.
    final bedRaw = cBed == null ? '' : cellStr(r[cBed]);
    final wakeRaw = cWake == null ? '' : cellStr(r[cWake]);
    final bed = _clock(bedRaw);
    final wake = _clock(wakeRaw);
    if (bed != null && wake != null) {
      final bedDate = minutesOf(bed)! >= 12 * 60 ? addDays(date, -1) : date;
      out
        ..add(
          _ev(
            tab,
            row,
            'bed',
            bedDate,
            EventType.sleep,
            time: bed,
            approx: _isApprox(bedRaw),
          ),
        )
        ..add(
          _ev(
            tab,
            row,
            'wake',
            date,
            EventType.wake,
            time: wake,
            approx: _isApprox(wakeRaw),
          ),
        );
    }

    // Data bugs: numbers that live in the wrong column. Surfaced, not fixed.
    final others = {
      for (final k in r.keys)
        if (k != '_row' && k != cDate) k: cellStr(r[k]),
    };
    final commute = cell(cCommute);
    for (final e in others.entries) {
      if (e.key == cCommute || commute.value == null) continue;
      var parts = _commuteMinutes(e.value);
      if (parts.isEmpty) continue;
      // "85 min … morning 90 … 175 total": a stated total is not added again.
      final max = parts.reduce((a, b) => a > b ? a : b);
      final others = parts.fold<double>(0, (a, b) => a + b) - max;
      if (parts.length > 2 && max == others) {
        parts = [
          for (final p in parts)
            if (p != max) p,
        ];
      }
      final said = parts.fold<double>(0, (a, b) => a + b);
      // Only a column that undercounts is a bug; text naming one leg of a
      // longer day is not.
      if (said > commute.value!) {
        flags.add(
          LegacyFlag(
            date: date,
            text:
                'Commute: ${trimNum(commute.value)} min in the column, '
                '${trimNum(said)} in ${e.key}'
                '${parts.length > 1 ? ' (${parts.map(trimNum).join(' + ')})' : ''}',
          ),
        );
      }
    }
    if (steps.value == null) {
      for (final e in others.entries) {
        if (e.key == cSteps) continue;
        final m = RegExp(
          r'(\d{1,3}(?:,\d{3})+|\d{4,6})\s*(?:[a-z]+\s+){0,2}steps',
          caseSensitive: false,
        ).firstMatch(e.value);
        if (m != null) {
          flags.add(
            LegacyFlag(
              date: date,
              text: 'Steps (${m[1]}) are in ${e.key}, not in the Steps column',
            ),
          );
          break;
        }
      }
    }
  }
}

bool _naCell(String raw) =>
    parseLegacyCell(raw).raw.isEmpty ||
    RegExp(
      r'^\s*(?:n\s*/\s*a|na|none|-+|—)\s*$',
      caseSensitive: false,
    ).hasMatch(raw);

/// Minutes stated in the sentence that mentions a commute:
/// "Evening bus commute 20:15–21:40 (85 min); morning 90" → [85, 90].
/// Clock times are ignored. Splits on "." and new lines only, so a clause
/// after ";" stays with its commute sentence.
List<double> _commuteMinutes(String text) {
  final out = <double>[];
  for (final sentence in text.split(RegExp(r'\.\s|\n'))) {
    if (!sentence.toLowerCase().contains('commut')) continue;
    for (final m in RegExp(
      r'(?<![\d:.])(\d{1,3})\s*min\b|\b(?:morning|evening|return|home|office)\s+(\d{1,3})\b(?![:.]\d)',
      caseSensitive: false,
    ).allMatches(sentence)) {
      out.add(double.parse((m[1] ?? m[2])!));
    }
  }
  return out;
}

bool _isCategoryName(String s) {
  final c = _norm(s);
  return c == 'oneoff' ||
      c == 'bill' ||
      SpendCategory.all.any((k) => _norm(k) == c);
}

/// The live "Category" column holds descriptions ("Electricity bill",
/// "Blinkit groceries"), so a known category name is used when present and
/// otherwise the keyword guess runs on description + merchant.
String _legacyCategory(String category, String merchant) {
  final c = _norm(category);
  for (final known in SpendCategory.all) {
    if (c == _norm(known)) return known;
  }
  if (c.contains('oneoff')) return SpendCategory.oneOff;
  return categoryFor('$category $merchant');
}

void _spending(List<Map<String, dynamic>> rows, int year, List<Event> out) {
  if (rows.isEmpty) return;
  final h = _headers(rows);
  final cDate = _col(h, ['=date', '=day', 'date']);
  final cAmount = _col(h, ['amount', '=amt', 'inr', 'cost', 'price', 'spent']);
  if (cDate == null || cAmount == null) return;
  final cTime = _col(h, ['=time', 'time']);
  final cCat = _col(h, ['category', '=cat', '=type', 'bucket']);
  final cItem = _col(h, [
    'item',
    'what',
    'description',
    'desc',
    'details',
    'merchant',
    'note',
  ]);
  final cMethod = _col(h, [
    'method',
    'paid',
    'via',
    'mode',
    'source',
    'payment',
  ]);
  final cSource = _col(h, ['=source', 'reportedvia']);
  const tab = 'Spending';
  for (final r in rows) {
    final date = legacyDate(r[cDate], year: year);
    final amt = parseLegacyCell(r[cAmount]);
    if (date == null || amt.value == null) continue;
    final merchant = cItem == null ? '' : cellStr(r[cItem]);
    final cat = cCat == null ? '' : cellStr(r[cCat]);
    final method = cMethod == null ? '' : cellStr(r[cMethod]);
    final via = cSource == null ? '' : cellStr(r[cSource]);
    final lazy = '$method $via'.toLowerCase().contains('lazy');
    out.add(
      _ev(
        tab,
        r['_row'],
        'spend',
        date,
        EventType.spend,
        time: cTime == null ? null : cellTime(r[cTime]),
        amount: amt.value,
        // A description ("Electricity bill") reads better than the merchant;
        // a bare category name ("Bills") does not.
        label: cat.isNotEmpty && !_isCategoryName(cat)
            ? cat
            : (merchant.isNotEmpty ? merchant : (cat.isEmpty ? 'Spend' : cat)),
        category: _legacyCategory(cat, merchant),
        approx: amt.approx,
        source: lazy ? 'lazypay' : null,
        // Merchant groups itemised rows of one order (Money "orders").
        note: merchant.isEmpty ? null : merchant,
      ),
    );
  }
}

// --------------------------------------------------------------- merge --

String _metric(Event e) => switch (e.type) {
  EventType.sleep || EventType.wake => 'sleep',
  EventType.cigarette => 'cig',
  EventType.waterMl => 'water',
  EventType.weight => 'weight',
  EventType.steps => 'steps',
  EventType.energy => 'energy',
  _ => 'other',
};

/// Effective Events plus the legacy events for (date, metric) pairs the
/// Events tab has nothing for. Legacy spend is used only on days with no
/// money in Events. The Events tab always wins.
List<Event> withLegacy(List<Event> effective, LegacyImport legacy) {
  if (legacy.events.isEmpty) return effective;
  final have = {for (final e in effective) '${e.date}|${_metric(e)}'};
  final paidDays = {
    for (final e in effective)
      if (e.amountInr != null) e.date,
  };
  final out = [
    ...effective,
    for (final e in legacy.events)
      if (e.type == EventType.spend
          ? !paidDays.contains(e.date)
          : !have.contains('${e.date}|${_metric(e)}'))
        e,
  ]..sort(compareEvents);
  return out;
}
