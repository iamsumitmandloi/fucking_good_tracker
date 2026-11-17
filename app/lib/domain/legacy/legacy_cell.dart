import 'package:equatable/equatable.dart';

import '../../core/cells.dart';

/// One parsed `Daily Summary`-style cell (PRD §6.4).
class LegacyCell extends Equatable {
  const LegacyCell({this.value, this.approx = false, this.raw = ''});

  /// First number, or the midpoint of a range. Null for N/A, text or empty.
  final double? value;

  /// `~` or a range was present.
  final bool approx;

  /// The original text, always kept.
  final String raw;

  bool get missing => value == null;

  @override
  List<Object?> get props => [value, approx, raw];
}

final _range = RegExp(
  r'(\d[\d,]*(?:\.\d+)?)\s*(?:–|—|-|to)\s*(\d[\d,]*(?:\.\d+)?)',
);
final _number = RegExp(r'\d[\d,]*(?:\.\d+)?');
final _na = RegExp(
  r'^\s*(?:n\s*/\s*a|na|none|nil|not\s+(?:logged|tracked|recorded)|unknown|\?+|-+|—)\b',
  caseSensitive: false,
);

double? _toNum(String s) => double.tryParse(s.replaceAll(',', ''));

/// "~7.5 (inferred…)" → 7.5 approx; "~6–6.25 h" → 6.125 approx;
/// "N/A — weekend" → missing; "12,576" → 12576. Never throws.
LegacyCell parseLegacyCell(Object? cell) {
  final raw = cellStr(cell);
  if (raw.isEmpty || _na.hasMatch(raw)) return LegacyCell(raw: raw);
  final tilde = raw.contains('~') || raw.contains('≈');
  final r = _range.firstMatch(raw);
  final n = _number.firstMatch(raw);
  // A range only counts when it comes first ("6–6.25 h", not "4 (2–3 singles)").
  if (r != null && n != null && r.start == n.start) {
    final a = _toNum(r.group(1)!);
    final b = _toNum(r.group(2)!);
    if (a != null && b != null) {
      return LegacyCell(value: (a + b) / 2, approx: true, raw: raw);
    }
  }
  if (n == null) return LegacyCell(raw: raw);
  final v = _toNum(n.group(0)!);
  return LegacyCell(value: v, approx: tilde && v != null, raw: raw);
}
