// Read-only check of the app's numbers against the live sheet.
//
//   cd app && dart run tool/live_check.dart [today=2026-11-17]
//
// GETs Events, Daily Summary and Spending (never POSTs), runs the same
// derivations as the Week and Money tabs, and prints totals only. The URL
// and token are read from ../secrets.json and never printed.
import 'dart:convert';
import 'dart:io';

import 'package:starting_again/core/formatters.dart';
import 'package:starting_again/domain/derivations/burn.dart';
import 'package:starting_again/domain/derivations/week.dart';
import 'package:starting_again/domain/derivations/weight.dart';
import 'package:starting_again/domain/effective_events.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/legacy/legacy_adapter.dart';

Future<void> main(List<String> args) async {
  final detail = args.contains('--detail');
  final rest = [
    for (final a in args)
      if (!a.startsWith('--')) a,
  ];
  final today = rest.isNotEmpty ? rest.first : '2026-11-17';
  final secrets = jsonDecode(
    File('../secrets.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final uri = Uri.parse(secrets['SHEET_URL'] as String).replace(
    queryParameters: {
      'token': secrets['SHEET_TOKEN'] as String,
      'tabs': 'Events,Daily Summary,Spending',
    },
  );
  stdout.writeln('Fetching Events, Daily Summary, Spending (GET)…');
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
  final tabs = (json['tabs'] as Map<String, dynamic>).map(
    (k, v) => MapEntry(k, (v as List).cast<Map<String, dynamic>>()),
  );

  final live = [
    for (final r in tabs['Events'] ?? const <Map<String, dynamic>>[])
      ?Event.fromSheetRow(r),
  ];
  final legacy = adaptLegacy(tabs, year: int.parse(today.substring(0, 4)));
  final events = withLegacy(effectiveEvents(live), legacy);
  final days = weekDays(today);
  final w = weekStats(events, days, legacySleepHours: legacy.sleepHours);
  final kg = weightWeek(events, days);
  final b = burn(events, from: days.first, to: days.last);

  stdout
    ..writeln('Week ${days.first} → ${days.last}')
    ..writeln(
      '  live Events rows: ${live.length}, legacy events: ${legacy.events.length}',
    )
    ..writeln('  days logged: ${w.daysLogged}/7')
    ..writeln(
      '  cigarettes: ${trimNum(w.cigTotal)}  per day ${w.cigs.map(trimNum).join(' ')}',
    )
    ..writeln(
      '  sleep h:    ${w.sleep.map((r) => r.hours == null ? dash : '${r.approx ? '~' : ''}${trimNum(r.hours)}').join(' ')}'
      '  (bars: ${w.sleep.where((r) => r.bar != null).length}, late: ${w.sleep.where((r) => r.late).length})',
    )
    ..writeln(
      '  weight avg: ${trimNum(kg.avg, digits: 2)} kg, axis ${trimNum(kg.lo)}–${trimNum(kg.hi)}',
    )
    ..writeln('  not logged: ${w.notLogged}, study sessions ${w.studySessions}')
    ..writeln('Money')
    ..writeln(
      '  total incl. one-offs: ${rupees(b.total, decimals: true)} (${b.entries} entries)',
    )
    ..writeln(
      '  day-to-day: ${rupees(b.dayToDay, decimals: true)} = ${rupees(b.perDay)}/day',
    )
    ..writeln(
      '  delivery: ${rupees(b.delivery)} (${b.deliveryCount} orders) · everything else: ${rupees(b.other)} · one-offs: ${rupees(b.oneOffs)} ${b.oneOffLabels}',
    )
    ..writeln('  pay later: ${rupees(b.payLater)} (${b.payLaterCount} charges)')
    ..writeln('Data flags')
    ..writeln(
      legacy.flags.isEmpty
          ? '  none'
          : legacy.flags.map((f) => '  ${f.date}: ${f.text}').join('\n'),
    );
  if (detail) {
    stdout.writeln('Delivery entries');
    for (final e in events) {
      if (e.amountInr != null &&
          e.category == 'delivery' &&
          days.contains(e.date)) {
        stdout.writeln('  ${e.date} ${rupees(e.amountInr)} ${e.label}');
      }
    }
    String shape(Object? v) => '$v'.replaceAll(RegExp(r'\d'), '9');
    for (final col in ['Energy', 'Steps']) {
      stdout.writeln(
        '$col cells: ${[for (final r in tabs['Daily Summary']!) shape(r[col])]}',
      );
    }
    for (final r in tabs['Daily Summary']!) {
      if ('${r['Date']}' != '2026-11-16') continue;
      for (final col in ['Work', 'Exercise', 'Commute minutes', 'Steps']) {
        final t = '${r[col]}';
        final i = t.toLowerCase().indexOf(
          col == 'Exercise' || col == 'Steps' ? 'step' : 'commut',
        );
        stdout.writeln(
          '16 Nov $col: ${i < 0 ? t.substring(0, t.length.clamp(0, 60)) : t.substring((i - 40).clamp(0, t.length), (i + 40).clamp(0, t.length))}',
        );
      }
    }
  }
}
