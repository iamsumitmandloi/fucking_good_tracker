/// The backend returns `getDisplayValues()`, so every cell is a string.
/// These helpers turn cells into typed values without ever throwing.
library;

import 'clock.dart';

String cellStr(Object? v) => v == null ? '' : v.toString().trim();

String? cellStrOrNull(Object? v) {
  final s = cellStr(v);
  return s.isEmpty ? null : s;
}

/// "87.91", "1,234.50", "₹130", 87.91 → number. Anything else → null.
num? cellNum(Object? v) {
  if (v is num) return v;
  var s = cellStr(v);
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'[₹,\s]'), '');
  if (s.startsWith('Rs.')) s = s.substring(3);
  final n = num.tryParse(s);
  if (n == null || n.isNaN || n.isInfinite) return null;
  return n;
}

double? cellDouble(Object? v) => cellNum(v)?.toDouble();

int? cellInt(Object? v) {
  final n = cellNum(v);
  if (n == null) return null;
  return n == n.roundToDouble() ? n.toInt() : null;
}

/// "TRUE"/"true"/true → true. Everything else → false.
bool cellBool(Object? v) {
  if (v is bool) return v;
  return cellStr(v).toLowerCase() == 'true';
}

/// `yyyy-MM-dd` passes through. `d/M/yyyy` (sheet locale) is normalised.
String? cellDate(Object? v) {
  final s = cellStr(v);
  if (s.isEmpty) return null;
  final iso = parseDate(s);
  if (iso != null) return formatDate(iso);
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
  if (m != null) {
    final d = parseDate('${m[3]}-${m[2]}-${m[1]}');
    if (d != null) return formatDate(d);
  }
  return null;
}

/// `H:mm`, `HH:mm`, `HH:mm:ss` → `HH:mm`. Anything else → null.
String? cellTime(Object? v) {
  final mins = minutesOf(cellStr(v));
  if (mins == null) return null;
  return mins == 24 * 60 ? '24:00' : hhmmOf(mins);
}
