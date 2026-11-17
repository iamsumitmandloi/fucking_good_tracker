import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/result.dart';
import '../../domain/event.dart';
import 'sheet_config.dart';

typedef SheetRow = Map<String, dynamic>;
typedef SheetTabs = Map<String, List<SheetRow>>;

class PostResult {
  const PostResult({required this.added, required this.skipped});

  final List<String> added;
  final List<String> skipped;

  /// Both mean "the row is on the server" (skipped = already existed).
  Set<String> get confirmed => {...added, ...skipped};
}

/// Thin client over the Apps Script web app (PRD §5.1).
class SheetApi {
  SheetApi({
    required this._client,
    required this._config,
    this.timeout = const Duration(seconds: 20),
  });

  final http.Client _client;
  final SheetConfigStore _config;
  final Duration timeout;

  /// GET only the named tabs. Absent tabs are simply missing from the map.
  Future<Result<SheetTabs>> fetchTabs(List<String> tabs) async {
    final cfg = await _config.load();
    if (cfg == null || !cfg.isComplete) {
      return const Err(NotConfiguredFailure());
    }
    final Uri uri;
    try {
      uri = _getUri(cfg, tabs);
    } on FormatException {
      return const Err(ParseFailure('bad sheet URL'));
    }
    return _guard(() async {
      final res = await _client.get(uri).timeout(timeout);
      final json = _decode(res);
      final raw = json['tabs'];
      if (raw is! Map) throw const _Bad('missing tabs');
      return <String, List<SheetRow>>{
        for (final entry in raw.entries)
          if (entry.value is List)
            entry.key as String: [
              for (final r in entry.value as List)
                if (r is Map) Map<String, dynamic>.from(r),
            ],
      };
    });
  }

  /// POST events. Apps Script answers with a 302 whose `Location` holds the
  /// JSON reply; dart:io won't follow a 302 for POST, so we GET it ourselves.
  Future<Result<PostResult>> postEvents(List<Event> events) async {
    final cfg = await _config.load();
    if (cfg == null || !cfg.isComplete) {
      return const Err(NotConfiguredFailure());
    }
    final Uri uri;
    try {
      uri = Uri.parse(cfg.url.trim());
    } on FormatException {
      return const Err(ParseFailure('bad sheet URL'));
    }
    return _guard(() async {
      final req = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode({
          'token': cfg.token,
          'events': [for (final e in events) e.toJson()],
        });
      final streamed = await _client.send(req).timeout(timeout);
      var res = await http.Response.fromStream(streamed).timeout(timeout);
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final location = res.headers['location'];
        if (location == null || location.isEmpty) {
          throw const _Bad('redirect without Location');
        }
        res = await _client.get(uri.resolve(location)).timeout(timeout);
      }
      final json = _decode(res);
      List<String> ids(Object? v) => [
        if (v is List)
          for (final x in v)
            if (x != null) x.toString(),
      ];
      return PostResult(
        added: ids(json['added']),
        skipped: ids(json['skipped']),
      );
    });
  }

  Uri _getUri(SheetConfig cfg, List<String> tabs) {
    final base = Uri.parse(cfg.url.trim());
    // Build the query by hand: spaces must be %20 (not '+'), commas literal.
    final parts = <String>[
      if (base.query.isNotEmpty) base.query,
      'token=${Uri.encodeComponent(cfg.token)}',
      if (tabs.isNotEmpty) 'tabs=${tabs.map(Uri.encodeComponent).join(',')}',
    ];
    return base.replace(query: parts.join('&'));
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 500) throw _Net('HTTP ${res.statusCode}');
    if (res.statusCode != 200) throw _Bad('HTTP ${res.statusCode}');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const _Bad('reply was not JSON');
    }
    if (json is! Map<String, dynamic>) {
      throw const _Bad('reply was not an object');
    }
    if (json['ok'] != true) {
      final error = json['error']?.toString() ?? 'unknown error';
      throw _Server(error);
    }
    return json;
  }

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on TimeoutException {
      return const Err(TimeoutFailure());
    } on _Server catch (e) {
      return Err(
        e.message == 'unauthorised'
            ? const UnauthorisedFailure()
            : ServerFailure(e.message),
      );
    } on _Bad catch (e) {
      return Err(ParseFailure(e.message));
    } on _Net catch (e) {
      return Err(NetworkFailure(e.message));
    } on SocketException catch (e) {
      return Err(NetworkFailure(e.message));
    } on HandshakeException catch (e) {
      return Err(NetworkFailure(e.message));
    } on http.ClientException catch (e) {
      return Err(NetworkFailure(e.message));
    }
  }
}

class _Bad implements Exception {
  const _Bad(this.message);
  final String message;
}

class _Net implements Exception {
  const _Net(this.message);
  final String message;
}

class _Server implements Exception {
  const _Server(this.message);
  final String message;
}
