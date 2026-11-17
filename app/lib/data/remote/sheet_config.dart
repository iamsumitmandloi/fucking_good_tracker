import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SheetConfig {
  const SheetConfig({required this.url, required this.token});

  final String url;
  final String token;

  bool get isComplete => url.trim().isNotEmpty && token.trim().isNotEmpty;

  /// Never let the token reach a log line.
  @override
  String toString() => 'SheetConfig(url: $url, token: ••••)';
}

abstract class SheetConfigStore {
  Future<SheetConfig?> load();
  Future<void> save(SheetConfig config);

  /// Copies `--dart-define` values into storage the first time only.
  Future<void> seedFromEnvironment();
}

class SecureSheetConfigStore implements SheetConfigStore {
  SecureSheetConfigStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _kUrl = 'sheet_url';
  static const _kToken = 'sheet_token';
  static const _envUrl = String.fromEnvironment('SHEET_URL');
  static const _envToken = String.fromEnvironment('SHEET_TOKEN');

  SheetConfig? _cache;

  @override
  Future<SheetConfig?> load() async {
    if (_cache != null) return _cache;
    final url = await _storage.read(key: _kUrl);
    final token = await _storage.read(key: _kToken);
    if (url == null || token == null) return null;
    return _cache = SheetConfig(url: url, token: token);
  }

  @override
  Future<void> save(SheetConfig config) async {
    await _storage.write(key: _kUrl, value: config.url.trim());
    await _storage.write(key: _kToken, value: config.token.trim());
    _cache = SheetConfig(url: config.url.trim(), token: config.token.trim());
  }

  @override
  Future<void> seedFromEnvironment() async {
    if (_envUrl.isEmpty || _envToken.isEmpty) return;
    final existing = await load();
    if (existing != null && existing.isComplete) return;
    await save(const SheetConfig(url: _envUrl, token: _envToken));
  }
}

class MemorySheetConfigStore implements SheetConfigStore {
  MemorySheetConfigStore([this.config]);

  SheetConfig? config;

  @override
  Future<SheetConfig?> load() async => config;

  @override
  Future<void> save(SheetConfig config) async => this.config = config;

  @override
  Future<void> seedFromEnvironment() async {}
}
