import 'package:intl/intl.dart';

const dash = '—';

final _inr0 = NumberFormat.decimalPattern('en_IN');
final _inr2 = NumberFormat('#,##,##0.##', 'en_IN');

/// ₹1,234 (whole rupees) or ₹1,234.5 when [decimals]. Null → "—".
String rupees(num? v, {bool decimals = false}) {
  if (v == null) return dash;
  return '₹${decimals ? _inr2.format(v) : _inr0.format(v.round())}';
}

/// ₹10.6k style for tight spaces.
String rupeesCompact(num? v) {
  if (v == null) return dash;
  if (v.abs() < 1000) return '₹${v.round()}';
  final k = v / 1000;
  return '₹${k.toStringAsFixed(k >= 100 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '')}k';
}

/// 80 → "1h 20m", 45 → "45m". Null → "—".
String duration(int? minutes) {
  if (minutes == null) return dash;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// 7.5 → "7.5", 6.0 → "6". Null → "—".
String trimNum(num? v, {int digits = 1}) {
  if (v == null) return dash;
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
}

final _dayHeader = DateFormat('EEE d MMM');
final _dayShort = DateFormat('EEE d');
final _dow2 = DateFormat('EEE');

String dayHeader(DateTime d) => _dayHeader.format(d);
String dayShort(DateTime d) => _dayShort.format(d);

/// "Wed", "Thu" … as in the v2 designs.
String dow3(DateTime d) => _dow2.format(d);

/// "We", "Th" … as in the Week design.
String dow2(DateTime d) => _dow2.format(d).substring(0, 2);

/// Never print a secret. Shows "••••" for any non-empty value.
String mask(String? secret) => (secret == null || secret.isEmpty) ? '' : '••••';
