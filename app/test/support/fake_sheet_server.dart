import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starting_again/core/clock.dart';
import 'package:starting_again/data/local/db.dart';
import 'package:starting_again/data/remote/sheet_api.dart';
import 'package:starting_again/data/remote/sheet_config.dart';

const testUrl = 'https://script.google.com/macros/s/TEST/exec';
const testToken = 'test-token';
const echoUrl =
    'https://script.googleusercontent.com/macros/echo?user_content_key=abc';

/// In-memory stand-in for the Apps Script web app (backend/Code.gs).
/// - GET ?token&tabs → {ok, tabs}; values are strings like getDisplayValues.
/// - POST → 302 Location; GET Location → {ok, added, skipped}.
class FakeSheetServer {
  FakeSheetServer({Map<String, List<Map<String, dynamic>>>? tabs})
    : tabs = tabs ?? {'Events': []};

  final Map<String, List<Map<String, dynamic>>> tabs;

  bool offline = false;
  bool hang = false;
  String? forceError;
  int posts = 0;
  int gets = 0;
  final List<Uri> requested = [];
  final List<List<String>> postedIds = [];

  Map<String, dynamic>? _pendingReply;

  static const eventColumns = [
    'id', 'date', 'time', 'end_time', 'type', 'qty', 'unit', 'label', //
    'amount_inr', 'category', 'approx', 'source', 'note', 'created_at',
  ];

  List<Map<String, dynamic>> get events => tabs['Events']!;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    requested.add(req.url);
    if (hang) {
      await Completer<void>().future; // never completes
    }
    if (offline) throw http.ClientException('offline', req.url);

    if (req.method == 'GET' && req.url.toString() == echoUrl) {
      final reply = _pendingReply ?? {'ok': false, 'error': 'no pending'};
      _pendingReply = null;
      return _json(reply);
    }

    if (req.method == 'GET') {
      gets++;
      if (req.url.queryParameters['token'] != testToken) {
        return _json({'ok': false, 'error': 'unauthorised'});
      }
      if (forceError != null) return _json({'ok': false, 'error': forceError});
      final wanted = req.url.queryParameters['tabs']?.split(',') ?? tabs.keys;
      return _json({
        'ok': true,
        'generatedAt': DateTime.utc(2026, 11, 17).toIso8601String(),
        'tabs': {
          for (final name in wanted)
            if (tabs.containsKey(name.trim())) name.trim(): tabs[name.trim()],
        },
      });
    }

    // POST
    posts++;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    Map<String, dynamic> reply;
    if (body['token'] != testToken) {
      reply = {'ok': false, 'error': 'unauthorised'};
    } else if (forceError != null) {
      reply = {'ok': false, 'error': forceError};
    } else {
      final existing = {for (final r in events) r['id']};
      final added = <String>[];
      final skipped = <String?>[];
      for (final ev in (body['events'] as List).cast<Map<String, dynamic>>()) {
        final id = ev['id'] as String?;
        if (id == null || existing.contains(id)) {
          skipped.add(id);
          continue;
        }
        events.add({
          '_row': events.length + 2,
          for (final c in eventColumns)
            c: c == 'created_at'
                ? '2026-11-17T12:00:00.000Z'
                : c == 'approx'
                ? (ev['approx'] == true ? 'TRUE' : 'FALSE')
                : (ev[c] ?? '').toString(),
        });
        existing.add(id);
        added.add(id);
      }
      postedIds.add(added);
      reply = {'ok': true, 'added': added, 'skipped': skipped};
    }
    _pendingReply = reply;
    return http.Response(
      '<html>Moved Temporarily</html>',
      302,
      headers: {'location': echoUrl},
    );
  }

  http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  SheetApi api({String token = testToken, Duration? timeout}) => SheetApi(
    client: client,
    config: MemorySheetConfigStore(SheetConfig(url: testUrl, token: token)),
    timeout: timeout ?? const Duration(seconds: 20),
  );
}

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());

FixedClock testClock() => FixedClock.ist(2026, 11, 17, 18, 2);
