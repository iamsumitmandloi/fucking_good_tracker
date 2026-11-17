import '../core/cells.dart';

/// `Start Here` is a two-column key/value tab. The backend uses row 1 as the
/// header, so the first pair arrives as the header names themselves. Both are
/// recovered here, in sheet order.
List<MapEntry<String, String>> startHerePairs(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return const [];
  final headers = rows.first.keys.where((k) => k != '_row').toList();
  if (headers.isEmpty) return const [];
  final out = <MapEntry<String, String>>[];
  if (headers.length >= 2 && !_isGenericHeader(headers[0])) {
    out.add(MapEntry(headers[0], headers[1]));
  }
  for (final r in rows) {
    final k = cellStr(r[headers[0]]);
    final v = headers.length >= 2 ? cellStr(r[headers[1]]) : '';
    if (k.isNotEmpty) out.add(MapEntry(k, v));
  }
  return out;
}

bool _isGenericHeader(String h) => const {
  'key',
  'field',
  'item',
  'name',
  'what',
  'setting',
}.contains(h.trim().toLowerCase());

/// Typed view over the key/value pairs.
class StartHere {
  const StartHere(this.pairs);

  static const empty = StartHere({});

  final Map<String, String> pairs;

  String? lookup(String key) {
    final want = _n(key);
    for (final e in pairs.entries) {
      if (_n(e.key) == want) return _nonEmpty(e.value);
    }
    for (final e in pairs.entries) {
      if (_n(e.key).startsWith(want)) return _nonEmpty(e.value);
    }
    return null;
  }

  String? get currentFocus => lookup('Current focus');
  String? get nextAction => lookup('Next action');
  String? get whereToResume => lookup('Where to resume');
  String? get targetDate => cellDate(lookup('Target date'));

  /// The first question id mentioned in the current focus (e.g. "RS-34").
  String? get focusQuestionId => questionIdIn(currentFocus);

  static String? questionIdIn(String? s) {
    if (s == null) return null;
    final m = RegExp(r'\b([A-Z]{1,4}-?\d+(?:\.\d+)?)\b').firstMatch(s);
    return m?[1];
  }

  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  static String? _nonEmpty(String s) => s.trim().isEmpty ? null : s.trim();
}
