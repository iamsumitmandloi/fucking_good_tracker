import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

import '../../domain/voice/voice_contracts.dart';
import 'pcm_mic.dart';

/// Use a top-level function for a decoder that can be sent to an isolate.
typedef WhisperDecoder = Future<Iterable<SttSegment>> Function(
  Float32List samples, {
  required bool flush,
});

typedef _WorkerArgs = ({
  SendPort replies,
  VoiceModelFiles files,
  WhisperDecoder? decoder,
});

enum _Command { flush, dispose }

enum _Reply { flushed, failed }

class WhisperIsolate {
  WhisperIsolate._(this._onSegment, this._onFailure) {
    _replies.listen(_onReply);
  }

  static const _timeout = Duration(seconds: 60);

  final void Function(SttSegment) _onSegment;
  final void Function() _onFailure;
  final _replies = ReceivePort();
  final _ready = Completer<SendPort?>();
  final _exited = Completer<void>();

  Isolate? _isolate;
  SendPort? _commands;
  Completer<bool>? _flush;
  bool _failed = false;
  bool _closing = false;

  static Future<WhisperIsolate> start(
    VoiceModelFiles files, {
    required void Function(SttSegment) onSegment,
    required void Function() onFailure,
    WhisperDecoder? decoder,
  }) async {
    final worker = WhisperIsolate._(onSegment, onFailure);
    final replies = worker._replies.sendPort;
    try {
      worker._isolate = await Isolate.spawn(
        _runWhisper,
        (replies: replies, files: files, decoder: decoder),
        onError: replies,
        onExit: replies,
        debugName: 'voice-whisper',
      );
      if (await worker._ready.future.timeout(_timeout) == null ||
          worker._failed) {
        throw StateError('Whisper initialization failed.');
      }
      return worker;
    } catch (_) {
      await worker.dispose();
      rethrow;
    }
  }

  void addSamples(Float32List samples) => _commands?.send(samples);

  Future<void> flush() async {
    if (_failed || _exited.isCompleted) {
      throw StateError('Whisper is unavailable.');
    }
    final pending = _flush = Completer<bool>();
    _commands!.send(_Command.flush);
    try {
      if (!await pending.future.timeout(_timeout)) {
        throw StateError('Whisper could not finish decoding.');
      }
    } finally {
      _flush = null;
    }
  }

  Future<void> dispose() async {
    _closing = true;
    try {
      if (_isolate != null && !_exited.isCompleted) {
        _commands?.send(_Command.dispose);
        await _exited.future.timeout(_timeout);
      }
    } on TimeoutException {
      _isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      _replies.close();
    }
  }

  void _onReply(Object? message) {
    switch (message) {
      case final SendPort commands:
        _commands = commands;
        _ready.complete(commands);
        if (_closing) commands.send(_Command.dispose);
      case final SttSegment segment:
        _onSegment(segment);
      case _Reply.flushed:
        _flush?.complete(true);
      case _Reply.failed || List<Object?>():
        _fail();
      case null:
        if (!_closing) _fail();
        _exited.complete();
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    if (!_ready.isCompleted) _ready.complete(null);
    final pending = _flush;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    _onFailure();
  }
}

Future<void> _runWhisper(_WorkerArgs args) async {
  final commands = ReceivePort();
  OfflineRecognizer? recognizer;
  VoiceActivityDetector? vad;
  try {
    if (args.decoder == null) {
      initBindings();
      recognizer = OfflineRecognizer(
        OfflineRecognizerConfig(
          model: OfflineModelConfig(
            whisper: OfflineWhisperModelConfig(
              encoder: args.files.encoderPath,
              decoder: args.files.decoderPath,
              language: 'en',
              task: 'transcribe',
            ),
            tokens: args.files.tokensPath,
            numThreads: 2,
            provider: 'cpu',
            modelType: 'whisper',
            debug: false,
          ),
        ),
      );
      vad = VoiceActivityDetector(
        config: VadModelConfig(
          sileroVad: SileroVadModelConfig(
            model: args.files.vadPath,
            threshold: 0.5,
            minSpeechDuration: 0.25,
            minSilenceDuration: 0.6,
            windowSize: 512,
          ),
          sampleRate: pcmSampleRate,
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        bufferSizeInSeconds: 30,
      );
    }
    args.replies.send(commands.sendPort);

    await for (final message in commands) {
      if (message == _Command.dispose) break;
      final flush = message == _Command.flush;
      final samples = flush ? Float32List(0) : message as Float32List;
      final decoder = args.decoder;
      final segments = decoder == null
          ? _decodeAvailable(vad!, recognizer!, samples, flush: flush)
          : await decoder(samples, flush: flush);
      for (final segment in segments) {
        args.replies.send(segment);
      }
      if (flush) args.replies.send(_Reply.flushed);
    }
  } catch (_) {
    args.replies.send(_Reply.failed);
  } finally {
    try {
      try {
        vad?.free();
      } finally {
        recognizer?.free();
      }
    } finally {
      commands.close();
    }
  }
}

Iterable<SttSegment> _decodeAvailable(
  VoiceActivityDetector vad,
  OfflineRecognizer recognizer,
  Float32List samples, {
  required bool flush,
}) sync* {
  if (flush) {
    vad.flush();
  } else {
    vad.acceptWaveform(samples);
  }
  while (!vad.isEmpty()) {
    final segment = vad.front();
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(
        samples: segment.samples,
        sampleRate: pcmSampleRate,
      );
      final watch = Stopwatch()..start();
      recognizer.decode(stream);
      watch.stop();
      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty) {
        yield SttSegment(
          text: text,
          durationMs: (segment.samples.length * 1000 / pcmSampleRate).round(),
          decodeMs: watch.elapsedMilliseconds,
        );
      }
    } finally {
      stream.free();
      vad.pop();
    }
  }
}
