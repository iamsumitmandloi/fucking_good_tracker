import 'package:intl/intl.dart';

/// India has no DST, so a fixed offset is exact.
const istOffset = Duration(hours: 5, minutes: 30);

abstract class Clock {
  const Clock();

  DateTime nowUtc();

  /// Wall-clock IST, stored in a UTC-flagged DateTime so arithmetic never
  /// shifts with the device time zone.
  DateTime nowIst() {
    final u = nowUtc().toUtc().add(istOffset);
    return DateTime.utc(
      u.year,
      u.month,
      u.day,
      u.hour,
      u.minute,
      u.second,
      u.millisecond,
    );
  }

  String todayIst() => formatDate(nowIst());

  String timeIst() => formatTime(nowIst());
}

class SystemClock extends Clock {
  const SystemClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class FixedClock extends Clock {
  FixedClock(this._utc);

  /// Build from an IST wall-clock time, e.g. `FixedClock.ist(2026, 11, 17, 18, 2)`.
  factory FixedClock.ist(int y, int m, int d, [int h = 12, int min = 0]) =>
      FixedClock(DateTime.utc(y, m, d, h, min).subtract(istOffset));

  DateTime _utc;

  void advance(Duration d) => _utc = _utc.add(d);

  @override
  DateTime nowUtc() => _utc;
}

final _dateFmt = DateFormat('yyyy-MM-dd');

String formatDate(DateTime d) => _dateFmt.format(d);

String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// `yyyy-MM-dd` → UTC midnight. Returns null for anything else.
DateTime? parseDate(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, mo, d);
}

String addDays(String date, int days) =>
    formatDate(parseDate(date)!.add(Duration(days: days)));

/// Whole days from [from] to [to] (`yyyy-MM-dd`).
int daysBetween(String from, String to) =>
    parseDate(to)!.difference(parseDate(from)!).inDays;

/// `HH:mm` → minutes after midnight, or null.
int? minutesOf(String? hhmm) {
  if (hhmm == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(hhmm.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  if (h > 24 || min > 59 || (h == 24 && min > 0)) return null;
  return h * 60 + min;
}

String hhmmOf(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}
