import '../../core/clock.dart';
import '../effective_events.dart';
import '../event.dart';
import '../event_type.dart';

/// Phase 7 data rules (handoff_v2/AGENT_PROMPT_v2.md §4).
///
/// The events every viewer screen reads: [effectiveEvents] (no `dev-` ids,
/// voids applied) minus `test-` ids. `note` rows stay in the list for the
/// chronological views; metrics never count them.
List<Event> viewerEvents(Iterable<Event> all) => [
  for (final e in effectiveEvents(all))
    if (!e.id.startsWith('test-')) e,
];

/// Spend categories (they replace the PRD's list).
abstract final class SpendCat {
  static const tobacco = 'tobacco';
  static const tea = 'tea';
  static const foodOut = 'food_out';
  static const groceries = 'groceries';
  static const quickCommerce = 'quick_commerce';
  static const transport = 'transport';
  static const personalCare = 'personal_care';
  static const bills = 'bills';
  static const oneOff = 'one_off';
  static const other = 'other';

  /// Left out of day-to-day burn.
  static const nonBurn = {bills, oneOff};

  static const _names = {
    quickCommerce: 'Delivery apps',
    foodOut: 'Eating out',
    tobacco: 'Tobacco (logged)',
    transport: 'Transport',
    groceries: 'Groceries',
    tea: 'Tea',
    personalCare: 'Personal care',
    bills: 'Bills',
    oneOff: 'One-off',
    other: 'Other',
  };

  static String name(String? cat) {
    final c = cat ?? other;
    if (_names[c] case final n?) return n;
    final s = c.replaceAll('_', ' ');
    return s.isEmpty ? 'Other' : '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

extension EventViewer on Event {
  /// Minutes after midnight, or null when untimed.
  int? get minute => minutesOf(time);
  bool get timed => minute != null;

  bool get isSpend => type == EventType.spend && amountInr != null;

  /// A spend row that counts toward day-to-day burn.
  bool get isDayToDay => isSpend && !SpendCat.nonBurn.contains(category);

  bool get isFood =>
      type == EventType.meal ||
      type == EventType.snack ||
      type == EventType.tea ||
      type == EventType.coffee;

  bool get isBus => type == EventType.busBoard || type == EventType.busArrive;

  /// "Zepto Marketplace: Groceries / order" → "Groceries / order".
  String get itemText {
    final l = label?.trim() ?? '';
    final i = l.indexOf(':');
    if (i > 0 && i < l.length - 1) return l.substring(i + 1).trim();
    return l;
  }

  /// "Zepto Marketplace: Groceries" → "Zepto".
  String? get merchant {
    final l = label?.trim() ?? '';
    final i = l.indexOf(':');
    if (i <= 0) return null;
    final m = l.substring(0, i).trim();
    return m.split(RegExp(r'[\s/]+')).first;
  }
}

/// Events grouped by date, each list in time order (untimed last).
Map<String, List<Event>> byDate(Iterable<Event> events) {
  final out = <String, List<Event>>{};
  for (final e in events) {
    (out[e.date] ??= []).add(e);
  }
  for (final l in out.values) {
    l.sort(compareEvents);
  }
  return out;
}

/// Mean of the values that are present. Null when none are.
double? meanOf(Iterable<num?> values) {
  final have = values.whereType<num>().toList();
  if (have.isEmpty) return null;
  return have.fold<double>(0, (a, v) => a + v) / have.length;
}

double? sumOrNull(Iterable<Event> es, double Function(Event) f) {
  if (es.isEmpty) return null;
  return es.fold<double>(0, (a, e) => a + f(e));
}
