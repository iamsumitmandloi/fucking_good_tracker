import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starting_again/core/result.dart';
import 'package:starting_again/data/remote/sheet_api.dart';
import 'package:starting_again/data/remote/sheet_config.dart';
import 'package:starting_again/domain/event.dart';
import 'package:starting_again/domain/event_type.dart';

import '../support/fake_sheet_server.dart';

SheetApi apiWith(MockClientHandler h, {Duration? timeout}) => SheetApi(
  client: MockClient(h),
  config: MemorySheetConfigStore(
    const SheetConfig(url: testUrl, token: testToken),
  ),
  timeout: timeout ?? const Duration(seconds: 20),
);

const note = Event(
  id: 'dev-1',
  date: '2026-11-17',
  type: EventType.note,
  note: 'hello',
);

void main() {
  group('fetchTabs', () {
    test('200 GET returns rows per tab, string cells kept', () async {
      late Uri seen;
      final api = apiWith((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode({
            'ok': true,
            'generatedAt': 'x',
            'tabs': {
              'Start Here': [
                {'_row': 2, 'Current focus': 'Next action', 'RS-34': 'Open it'},
              ],
            },
          }),
          200,
        );
      });

      final res = await api.fetchTabs(['Start Here', 'Study Bank']);

      final tabs = (res as Ok<SheetTabs>).value;
      expect(tabs.keys, ['Start Here']); // absent tabs are simply missing
      expect(tabs['Start Here']!.single['RS-34'], 'Open it');
      expect(seen.query, contains('tabs=Start%20Here,Study%20Bank'));
      expect(seen.query, isNot(contains('+')));
      expect(seen.queryParameters['token'], testToken);
    });

    test(
      'ok:false unauthorised → UnauthorisedFailure (not retryable)',
      () async {
        final api = apiWith(
          (_) async =>
              http.Response('{"ok":false,"error":"unauthorised"}', 200),
        );
        final res = await api.fetchTabs(['Events']);
        final f = (res as Err).failure;
        expect(f, isA<UnauthorisedFailure>());
        expect(f.retryable, isFalse);
      },
    );

    test('ok:false other error → ServerFailure with message', () async {
      final api = apiWith(
        (_) async => http.Response(
          '{"ok":false,"error":"run setupEventsTab() first"}',
          200,
        ),
      );
      final f = ((await api.fetchTabs(['Events'])) as Err).failure;
      expect(f, isA<ServerFailure>());
      expect(f.message, 'run setupEventsTab() first');
    });

    test('HTML reply → ParseFailure', () async {
      final api = apiWith((_) async => http.Response('<html>oops</html>', 200));
      expect(
        ((await api.fetchTabs(['Events'])) as Err).failure,
        isA<ParseFailure>(),
      );
    });

    test('client exception → NetworkFailure', () async {
      final api = apiWith(
        (r) async => throw http.ClientException('down', r.url),
      );
      expect(
        ((await api.fetchTabs(['Events'])) as Err).failure,
        isA<NetworkFailure>(),
      );
    });

    test('no reply in 20 s → TimeoutFailure', () {
      fakeAsync((fa) {
        final api = apiWith((_) => Completer<http.Response>().future);
        Result<SheetTabs>? res;
        unawaited(api.fetchTabs(['Events']).then((r) => res = r));
        fa.elapse(const Duration(seconds: 19));
        expect(res, isNull);
        fa.elapse(const Duration(seconds: 2));
        expect((res! as Err).failure, isA<TimeoutFailure>());
      });
    });

    test('missing config → NotConfiguredFailure, no request made', () async {
      var calls = 0;
      final api = SheetApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
        config: MemorySheetConfigStore(),
      );
      expect(
        ((await api.fetchTabs(['Events'])) as Err).failure,
        isA<NotConfiguredFailure>(),
      );
      expect(calls, 0);
    });
  });

  group('postEvents', () {
    test('302 → GET Location → added ids', () async {
      final calls = <String>[];
      String? postedBody;
      final api = apiWith((req) async {
        calls.add('${req.method} ${req.url.host}');
        if (req.method == 'POST') {
          postedBody = req.body;
          return http.Response('', 302, headers: {'location': echoUrl});
        }
        return http.Response('{"ok":true,"added":["dev-1"],"skipped":[]}', 200);
      });

      final res = await api.postEvents([note]);

      expect(calls, [
        'POST script.google.com',
        'GET script.googleusercontent.com',
      ]);
      expect((res as Ok<PostResult>).value.added, ['dev-1']);
      final body = jsonDecode(postedBody!) as Map<String, dynamic>;
      expect(body['token'], testToken);
      expect((body['events'] as List).single['type'], 'note');
    });

    test('token goes in the body, never the POST URL', () async {
      late Uri postUrl;
      final api = apiWith((req) async {
        if (req.method == 'POST') {
          postUrl = req.url;
          return http.Response('', 302, headers: {'location': echoUrl});
        }
        return http.Response('{"ok":true,"added":[],"skipped":[]}', 200);
      });
      await api.postEvents([note]);
      expect(postUrl.toString(), isNot(contains(testToken)));
    });

    test('skipped ids count as confirmed (idempotent re-send)', () async {
      final server = FakeSheetServer();
      final api = server.api();
      final first = (await api.postEvents([note])) as Ok<PostResult>;
      final second = (await api.postEvents([note])) as Ok<PostResult>;
      expect(first.value.added, ['dev-1']);
      expect(second.value.added, isEmpty);
      expect(second.value.confirmed, {'dev-1'});
      expect(server.events, hasLength(1));
    });

    test('a direct 200 (redirect already followed) is accepted', () async {
      final api = apiWith(
        (_) async =>
            http.Response('{"ok":true,"added":["dev-1"],"skipped":[]}', 200),
      );
      expect(((await api.postEvents([note])) as Ok<PostResult>).value.added, [
        'dev-1',
      ]);
    });

    test('302 without Location → ParseFailure', () async {
      final api = apiWith((_) async => http.Response('', 302));
      expect(
        ((await api.postEvents([note])) as Err).failure,
        isA<ParseFailure>(),
      );
    });

    test('ok:false on the echo GET → typed failure', () async {
      final server = FakeSheetServer();
      final res = await server.api(token: 'wrong').postEvents([note]);
      expect((res as Err).failure, isA<UnauthorisedFailure>());
      expect(server.events, isEmpty);
    });

    test('timeout on the POST → TimeoutFailure', () {
      fakeAsync((fa) {
        final api = apiWith((_) => Completer<http.Response>().future);
        Result<PostResult>? res;
        unawaited(api.postEvents([note]).then((r) => res = r));
        fa.elapse(const Duration(seconds: 21));
        expect((res! as Err).failure, isA<TimeoutFailure>());
      });
    });

    test('5xx → NetworkFailure (retryable)', () async {
      final api = apiWith((_) async => http.Response('bad gateway', 502));
      final f = ((await api.postEvents([note])) as Err).failure;
      expect(f, isA<NetworkFailure>());
      expect(f.retryable, isTrue);
    });
  });

  test('SheetConfig.toString never shows the token', () {
    expect(
      const SheetConfig(url: testUrl, token: testToken).toString(),
      isNot(contains(testToken)),
    );
  });
}
