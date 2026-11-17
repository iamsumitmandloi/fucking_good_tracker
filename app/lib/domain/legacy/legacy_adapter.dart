import 'package:equatable/equatable.dart';

import '../../core/cells.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../event.dart';
import '../event_type.dart';
import '../quicklog/build_events.dart';
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
  try {
    _timeline(tabs['Timeline'] ?? const [], year, events, cigPrice, teaPrice);
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
  final cSleep = _col(h, ['sleep']);
  final cWeight = _col(h, ['weight', '=wt', '=kg']);
  final cSteps = _col(h, ['step']);
  final cWater = _col(h, ['water']);
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
    if (energy.value != null && energy.value! >= 1 && energy.value! <= 10) {
      out.add(
        _ev(
          tab,
          row,
          'energy',
          date,
          EventType.energy,
          qty: energy.value,
          approx: energy.approx,
        ),
      );
    }
    final s = cell(cSleep);
    if (s.value != null && s.value! > 0 && s.value! <= 16) sleep[date] = s;

    // Data bugs: numbers that live in the wrong column. Surfaced, not fixed.
    final others = {
      for (final k in r.keys)
        if (k != '_row' && k != cDate) k: cellStr(r[k]),
    };
    final commute = cell(cCommute);
    for (final e in others.entries) {
      if (e.key == cCommute) continue;
      final m = RegExp(
        r'commute[^0-9]{0,20}(\d[\d,]*)\s*(?:min|m\b)|(\d[\d,]*)\s*min[a-z]*\s+commute',
        caseSensitive: false,
      ).firstMatch(e.value);
      if (m == null) continue;
      final said = double.tryParse((m[1] ?? m[2])!.replaceAll(',', ''));
      if (said != null && commute.value != null && said != commute.value) {
        flags.add(
          LegacyFlag(
            date: date,
            text:
                'Commute: ${trimNum(commute.value)} min in the column, '
                '${trimNum(said)} in ${e.key}',
          ),
        );
      }
    }
    if (steps.value == null) {
      for (final e in others.entries) {
        if (e.key == cSteps) continue;
        final m = RegExp(
          r'(\d{1,3}(?:,\d{3})+|\d{4,6})\s*steps',
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

String _legacyCategory(String category, String item) {
  final c = _norm(category);
  if (c.contains('oneoff') || c.contains('oneof')) return SpendCategory.oneOff;
  if (c.contains('bill') || c.contains('utilit')) return SpendCategory.bills;
  if (c.contains('deliver')) return SpendCategory.delivery;
  for (final known in SpendCategory.all) {
    if (c == _norm(known)) return known;
  }
  final guess = categoryFor('$category $item');
  return guess;
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
  const tab = 'Spending';
  for (final r in rows) {
    final date = legacyDate(r[cDate], year: year);
    final amt = parseLegacyCell(r[cAmount]);
    if (date == null || amt.value == null) continue;
    final item = cItem == null ? '' : cellStr(r[cItem]);
    final cat = cCat == null ? '' : cellStr(r[cCat]);
    final method = cMethod == null ? '' : cellStr(r[cMethod]);
    out.add(
      _ev(
        tab,
        r['_row'],
        'spend',
        date,
        EventType.spend,
        time: cTime == null ? null : cellTime(r[cTime]),
        amount: amt.value,
        label: item.isEmpty ? (cat.isEmpty ? 'Spend' : cat) : item,
        category: _legacyCategory(cat, item),
        approx: amt.approx,
        source: method.toLowerCase().contains('lazy') ? 'lazypay' : null,
        note: method.isEmpty ? null : method,
      ),
    );
  }
}

/// Timeline phrases ("slept 22:30", "woke 6:10") → sleep and wake only.
/// Counts and money come from Daily Summary and Spending, so nothing is
/// counted twice.
void _timeline(
  List<Map<String, dynamic>> rows,
  int year,
  List<Event> out,
  double cigPrice,
  double teaPrice,
) {
  if (rows.isEmpty) return;
  final h = _headers(rows);
  final cDate = _col(h, ['=date', '=day', 'date']);
  final cTime = _col(h, ['=time', 'time']);
  final cText = _col(h, [
    'entry',
    'event',
    'what',
    'activity',
    'log',
    'note',
    'text',
    'description',
  ]);
  if (cDate == null || cText == null) return;
  const tab = 'Timeline';
  for (final r in rows) {
    final date = legacyDate(r[cDate], year: year);
    if (date == null) continue;
    final text = cellStr(r[cText]);
    final rowTime = cTime == null ? null : cellTime(r[cTime]);
    final parsed = parseQuickLog(text, cigPrice: cigPrice, teaPrice: teaPrice)
        .entries
        .where((e) => e.type == EventType.sleep || e.type == EventType.wake);
    var i = 0;
    for (final p in parsed) {
      // Same rule as Quick log: a stated time later than the row's time
      // happened the day before.
      final at = parseDate(date)!;
      final rowMin = minutesOf(rowTime) ?? (24 * 60 - 1);
      final built = buildEvents(
        [p],
        nowIst: at.add(Duration(minutes: rowMin)),
        idFactory: () => '',
      ).single;
      if (p.time == null && rowTime == null) continue;
      out.add(
        _ev(
          tab,
          r['_row'],
          '${p.type.wire}${i++}',
          built.date,
          p.type,
          time: built.time,
          approx: p.approx,
          note: text,
        ),
      );
    }
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
