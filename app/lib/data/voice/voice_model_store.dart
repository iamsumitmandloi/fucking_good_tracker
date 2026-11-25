import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/voice/voice_contracts.dart';

class VoiceArtifactSpec {
  const VoiceArtifactSpec({
    required this.fileName,
    required this.url,
    this.sizeBytes,
  });

  final String fileName;
  final String url;
  final int? sizeBytes;
}

abstract interface class CancellableVoiceModelRepository
    implements VoiceModelRepository {
  Future<void> cancelDownload();
}

class VoiceModelStore implements CancellableVoiceModelRepository {
  VoiceModelStore({
    required this._dirProvider,
    this._client,
    List<VoiceArtifactSpec>? artifacts,
  }) : _artifacts = List.unmodifiable(artifacts ?? _whisperBase) {
    final names = _artifacts.map((artifact) => artifact.fileName).toSet();
    if (_artifacts.length != _whisperBase.length ||
        !_whisperBase.every((artifact) => names.contains(artifact.fileName))) {
      throw ArgumentError('Expected the four Whisper base model file names.');
    }
  }

  static const _hub =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main';
  static const _encoder = 'base-encoder.int8.onnx';
  static const _decoder = 'base-decoder.int8.onnx';
  static const _tokens = 'base-tokens.txt';
  static const _vad = 'silero_vad.onnx';
  static const _whisperBase = [
    VoiceArtifactSpec(
      fileName: _encoder,
      url: '$_hub/$_encoder',
      sizeBytes: 29120534,
    ),
    VoiceArtifactSpec(
      fileName: _decoder,
      url: '$_hub/$_decoder',
      sizeBytes: 130672026,
    ),
    VoiceArtifactSpec(
      fileName: _tokens,
      url: '$_hub/$_tokens',
      sizeBytes: 816730,
    ),
    VoiceArtifactSpec(
      fileName: _vad,
      url:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$_vad',
      sizeBytes: 643854,
    ),
  ];

  static const _missing = VoiceModelState(status: VoiceModelStatus.missing);
  static const _networkTimeout = Duration(seconds: 30);

  final Future<Directory> Function() _dirProvider;
  final http.Client? _client;
  final List<VoiceArtifactSpec> _artifacts;
  final _changes = StreamController<VoiceModelState>.broadcast(sync: true);

  VoiceModelState _state = _missing;
  Future<void>? _download;
  Future<void>? _deletion;
  Completer<void>? _abort;

  @override
  Stream<VoiceModelState> watchState() => Stream.multi((listener) {
    var published = false;
    final subscription = _changes.stream.listen((state) {
      published = true;
      listener.add(state);
    });
    listener.onCancel = subscription.cancel;
    unawaited(
      currentState().then((state) {
        if (!published && !listener.isClosed) listener.add(state);
      }),
    );
  });

  @override
  Future<VoiceModelState> currentState() async {
    final snapshot = _state;
    if (_download != null ||
        _deletion != null ||
        snapshot.status == VoiceModelStatus.error) {
      return snapshot;
    }
    final diskState = await _readDisk();
    return identical(_state, snapshot) ? diskState : _state;
  }

  @override
  Future<void> download({bool force = false}) async {
    final deletion = _deletion;
    if (deletion != null) await deletion;
    final active = _download;
    if (active != null) return active;

    final abort = Completer<void>();
    _abort = abort;
    return _download = _downloadModel(force, abort).whenComplete(() {
      _download = null;
      _abort = null;
    });
  }

  @override
  Future<void> cancelDownload() async {
    final abort = _abort;
    if (abort == null) return;
    if (!abort.isCompleted) abort.complete();
    await _download;
  }

  @override
  Future<void> delete() => _deletion ??= _deleteModel().whenComplete(() {
    _deletion = null;
  });

  Future<Directory> _modelDirectory() async => Directory.fromUri(
    (await _dirProvider()).uri.resolve('voice_models/whisper_base/'),
  );

  File _file(Directory directory, String name) =>
      File.fromUri(directory.uri.resolve(name));

  Future<int> _validLength(Directory directory, VoiceArtifactSpec spec) async {
    final file = _file(directory, spec.fileName);
    if (!await file.exists()) return 0;
    final size = await file.length();
    return spec.sizeBytes == null || spec.sizeBytes == size ? size : 0;
  }

  Future<VoiceModelState> _inspect(Directory directory) async {
    var total = 0;
    for (final spec in _artifacts) {
      final length = await _validLength(directory, spec);
      if (length == 0) return _missing;
      total += length;
    }
    return VoiceModelState(
      status: VoiceModelStatus.ready,
      progress: 1,
      downloadedBytes: total,
      totalBytes: total,
      files: VoiceModelFiles(
        encoderPath: _file(directory, _encoder).path,
        decoderPath: _file(directory, _decoder).path,
        tokensPath: _file(directory, _tokens).path,
        vadPath: _file(directory, _vad).path,
      ),
    );
  }

  Future<VoiceModelState> _readDisk() async {
    try {
      return await _inspect(await _modelDirectory());
    } catch (_) {
      return _error('Could not read the voice model files.');
    }
  }

  Future<void> _downloadModel(bool force, Completer<void> abort) async {
    final client = _client ?? http.Client();
    try {
      final directory = await _modelDirectory();
      final previous = await _inspect(directory);
      if (abort.isCompleted ||
          (!force && previous.status == VoiceModelStatus.ready)) {
        _publish(previous);
        return;
      }
      await directory.create(recursive: true);
      var total = _artifacts.fold(
        0,
        (sum, spec) => sum + (spec.sizeBytes ?? 0),
      );
      var downloaded = 0;

      void progress() => _publish(
        VoiceModelState(
          status: VoiceModelStatus.downloading,
          progress: total == 0 ? 0 : (downloaded / total).clamp(0.0, 1.0),
          downloadedBytes: downloaded,
          totalBytes: total,
        ),
      );

      progress();
      for (final spec in _artifacts) {
        final cached = force ? 0 : await _validLength(directory, spec);
        if (abort.isCompleted) break;
        if (cached > 0) {
          if (spec.sizeBytes == null) total += cached;
          downloaded += cached;
          progress();
          continue;
        }
        await _downloadFile(
          client,
          directory,
          spec,
          abort,
          onLength: (size) {
            if (spec.sizeBytes == null) total += size;
            progress();
          },
          onChunk: (size) {
            downloaded += size;
            progress();
          },
        );
      }
      _publish(await _inspect(directory));
    } on FormatException catch (error) {
      _publish(abort.isCompleted ? await _readDisk() : _error(error.message));
    } catch (_) {
      _publish(
        abort.isCompleted
            ? await _readDisk()
            : _error('Download interrupted. Try again.'),
      );
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (_client == null) client.close();
    }
  }

  Future<void> _downloadFile(
    http.Client client,
    Directory directory,
    VoiceArtifactSpec spec,
    Completer<void> abort, {
    required void Function(int) onLength,
    required void Function(int) onChunk,
  }) async {
    final uri = Uri.parse(spec.url);
    final response = await client
        .send(http.AbortableRequest('GET', uri, abortTrigger: abort.future))
        .timeout(_networkTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.listen(null).cancel();
      throw FormatException(
        'Model download failed (HTTP ${response.statusCode}).',
      );
    }
    final part = _file(directory, '${spec.fileName}.part');
    final expected = spec.sizeBytes ?? response.contentLength;
    onLength(expected ?? 0);
    var received = 0;
    try {
      final output = await part.open(mode: FileMode.write);
      try {
        await for (final bytes in response.stream.timeout(_networkTimeout)) {
          if (abort.isCompleted) return;
          received += bytes.length;
          if (expected != null && received > expected) {
            throw FormatException('Invalid size for ${spec.fileName}.');
          }
          await output.writeFrom(bytes);
          onChunk(bytes.length);
        }
      } finally {
        await output.close();
      }
      if (abort.isCompleted) return;
      if (received == 0 || (expected != null && received != expected)) {
        throw FormatException('Incomplete model file: ${spec.fileName}.');
      }
      await part.rename(_file(directory, spec.fileName).path);
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  Future<void> _deleteModel() async {
    try {
      await cancelDownload();
      final directory = await _modelDirectory();
      if (await directory.exists()) await directory.delete(recursive: true);
      _publish(_missing);
    } catch (_) {
      _publish(_error('Could not delete the voice model files.'));
    }
  }

  VoiceModelState _error(String message) =>
      VoiceModelState(status: VoiceModelStatus.error, error: message);

  void _publish(VoiceModelState state) {
    _state = state;
    _changes.add(state);
  }
}
