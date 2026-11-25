import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starting_again/data/voice/voice_model_store.dart';
import 'package:starting_again/domain/voice/voice_contracts.dart';

const _names = [
  'base-encoder.int8.onnx',
  'base-decoder.int8.onnx',
  'base-tokens.txt',
  'silero_vad.onnx',
];
final _artifacts = [
  for (final name in _names)
    VoiceArtifactSpec(
      fileName: name,
      url: 'https://models.example/$name',
      sizeBytes: 4,
    ),
];

class _FakeClient extends http.BaseClient {
  _FakeClient(this.respond);

  final http.StreamedResponse Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return respond(request);
  }
}

http.StreamedResponse _fileResponse([List<int> bytes = const [1, 2, 3, 4]]) =>
    http.StreamedResponse(Stream.value(bytes), 200, contentLength: 4);

void main() {
  late Directory root;
  late Directory modelDir;
  late _FakeClient client;
  late VoiceModelStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice-model-test-');
    modelDir = Directory('${root.path}/voice_models/whisper_base');
    client = _FakeClient((_) => _fileResponse());
    store = VoiceModelStore(
      dirProvider: () async => root,
      client: client,
      artifacts: _artifacts,
    );
  });

  tearDown(() async {
    client.close();
    await root.delete(recursive: true);
  });

  File modelFile(String name) => File('${modelDir.path}/$name');

  test(
    'streams to .part, then atomically publishes valid model files',
    () async {
      final chunks = StreamController<List<int>>();
      client = _FakeClient(
        (request) => request.url.pathSegments.last == _names[0]
            ? http.StreamedResponse(chunks.stream, 200, contentLength: 4)
            : _fileResponse(),
      );
      store = VoiceModelStore(
        dirProvider: () async => root,
        client: client,
        artifacts: _artifacts,
      );

      expect((await store.watchState().first).status, VoiceModelStatus.missing);
      final midway = store.watchState().firstWhere(
        (state) => state.downloadedBytes == 2,
      );
      final download = store.download();
      final sameDownload = store.download();
      chunks.add([1, 2]);
      final progress = await midway;
      expect(progress.status, VoiceModelStatus.downloading);
      expect(progress.totalBytes, 16);
      expect(progress.progress, 0.125);
      expect(await modelFile('${_names[0]}.part').exists(), isTrue);
      expect(await modelFile(_names[0]).exists(), isFalse);

      chunks.add([3, 4]);
      await chunks.close();
      await Future.wait([download, sameDownload]);
      expect(client.requests, hasLength(4));
      expect(await modelFile('${_names[0]}.part').exists(), isFalse);
      expect(await modelFile(_names[0]).readAsBytes(), [1, 2, 3, 4]);

      final ready = await store.watchState().first;
      expect(ready.status, VoiceModelStatus.ready);
      expect(ready.progress, 1);
      expect(ready.downloadedBytes, 16);
      expect(
        ready.files,
        VoiceModelFiles(
          encoderPath: modelFile(_names[0]).path,
          decoderPath: modelFile(_names[1]).path,
          tokensPath: modelFile(_names[2]).path,
          vadPath: modelFile(_names[3]).path,
        ),
      );
    },
  );

  test('reuses a complete bundle, detects truncation and repairs it', () async {
    await store.download();
    final reopened = VoiceModelStore(
      dirProvider: () async => root,
      client: client,
      artifacts: _artifacts,
    );
    expect((await reopened.currentState()).status, VoiceModelStatus.ready);
    await reopened.download();
    expect(client.requests, hasLength(4));

    await modelFile(_names.first).writeAsBytes([1]);
    expect((await reopened.currentState()).status, VoiceModelStatus.missing);
    await reopened.download();
    expect(client.requests, hasLength(5));
    expect((await reopened.currentState()).status, VoiceModelStatus.ready);
  });

  test('an HTTP failure leaves no partial file and a retry recovers', () async {
    var unavailable = true;
    client = _FakeClient((request) {
      if (unavailable && request.url.pathSegments.last == _names[1]) {
        return http.StreamedResponse(const Stream.empty(), 503);
      }
      return _fileResponse();
    });
    store = VoiceModelStore(
      dirProvider: () async => root,
      client: client,
      artifacts: _artifacts,
    );

    await store.download();
    final failure = await store.currentState();
    expect(failure.status, VoiceModelStatus.error);
    expect(failure.error, contains('503'));
    expect(await modelFile(_names[1]).exists(), isFalse);
    expect(await modelFile('${_names[1]}.part').exists(), isFalse);

    unavailable = false;
    await store.download();
    expect((await store.currentState()).status, VoiceModelStatus.ready);
    expect(client.requests.map((r) => r.url.pathSegments.last), [
      _names[0],
      _names[1],
      _names[1],
      _names[2],
      _names[3],
    ]);
  });

  test('rejects a truncated replacement and keeps the valid file', () async {
    var truncate = false;
    client = _FakeClient((_) => _fileResponse(truncate ? [9] : [1, 2, 3, 4]));
    store = VoiceModelStore(
      dirProvider: () async => root,
      client: client,
      artifacts: _artifacts,
    );

    await store.download();
    truncate = true;
    await store.download(force: true);
    expect((await store.currentState()).status, VoiceModelStatus.error);
    expect(await modelFile(_names.first).readAsBytes(), [1, 2, 3, 4]);
    expect(await modelFile('${_names.first}.part').exists(), isFalse);
  });

  test('cancel aborts a running request and clears the staging file', () async {
    final chunks = StreamController<List<int>>();
    client = _FakeClient((request) {
      final abortable = request as http.AbortableRequest;
      unawaited(
        abortable.abortTrigger!.then((_) async {
          chunks.addError(http.RequestAbortedException(request.url));
          await chunks.close();
        }),
      );
      return http.StreamedResponse(chunks.stream, 200, contentLength: 4);
    });
    store = VoiceModelStore(
      dirProvider: () async => root,
      client: client,
      artifacts: _artifacts,
    );

    final midway = store.watchState().firstWhere(
      (state) => state.downloadedBytes == 2,
    );
    final download = store.download();
    chunks.add([1, 2]);
    await midway;
    await store.cancelDownload();
    await download;
    expect(client.requests, hasLength(1));
    expect(await modelFile(_names.first).exists(), isFalse);
    expect(await modelFile('${_names.first}.part').exists(), isFalse);
    expect((await store.currentState()).status, VoiceModelStatus.missing);
  });

  test('delete removes the bundle and publishes missing', () async {
    await store.download();
    final missing = store.watchState().firstWhere(
      (state) => state.status == VoiceModelStatus.missing,
    );
    await store.delete();
    expect(await modelDir.exists(), isFalse);
    expect((await missing).files, isNull);
    expect((await store.currentState()).status, VoiceModelStatus.missing);
  });
}
