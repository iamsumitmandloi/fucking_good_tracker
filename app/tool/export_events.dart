// Read-only export of the live Events tab to a test fixture.
//
//   cd app && dart run tool/export_events.dart
//
// GETs `tabs=Events` only (never POSTs) and writes the raw rows to
// fixtures/events_backfill.json (gitignored: it is personal data). Prints
// counts only. The URL and token are read from ../secrets.json and never
// printed.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final secrets = jsonDecode(
    File('../secrets.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final uri = Uri.parse(secrets['SHEET_URL'] as String).replace(
    queryParameters: {
      'token': secrets['SHEET_TOKEN'] as String,
      'tabs': 'Events',
    },
  );
  stdout.writeln('Fetching Events (GET)…');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final String body;
  try {
    final req = await client.getUrl(uri); // GET follows the 302 itself
    final res = await req.close().timeout(const Duration(seconds: 60));
    body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 60));
  } on Object catch (e) {
    stdout.writeln('Request failed: ${e.runtimeType}');
    exitCode = 1;
    return;
  } finally {
    client.close(force: true);
  }
  final json = jsonDecode(body) as Map<String, dynamic>;
  if (json['ok'] != true) {
    stdout.writeln('Sheet said ok:false (${json['error']}).');
    exitCode = 1;
    return;
  }
  final rows = ((json['tabs'] as Map<String, dynamic>)['Events'] as List)
      .cast<Map<String, dynamic>>();
  final out = File('fixtures/events_backfill.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));

  String prefix(String id) {
    final i = id.indexOf('-');
    return i < 0 ? '(uuid)' : id.substring(0, i + 1);
  }

  final byPrefix = <String, int>{};
  final byType = <String, int>{};
  final dates = <String>{};
  for (final r in rows) {
    final id = '${r['id']}';
    final p = RegExp(r'^[0-9a-f]{8}-').hasMatch(id) ? '(uuid)' : prefix(id);
    byPrefix[p] = (byPrefix[p] ?? 0) + 1;
    byType['${r['type']}'] = (byType['${r['type']}'] ?? 0) + 1;
    dates.add('${r['date']}');
  }
  stdout
    ..writeln('rows: ${rows.length} → ${out.path}')
    ..writeln('by id prefix: $byPrefix')
    ..writeln('by type: $byType')
    ..writeln('dates: ${(dates.toList()..sort()).join(', ')}')
    ..writeln('columns: ${rows.isEmpty ? '-' : rows.first.keys.join(', ')}');
}
