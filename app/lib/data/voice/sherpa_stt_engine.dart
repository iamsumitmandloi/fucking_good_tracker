import 'dart:async';
import 'dart:typed_data';

import '../../domain/voice/voice_contracts.dart';
import 'pcm_mic.dart';
import 'whisper_isolate.dart';

class SherpaSttEngine implements SttEngine {
  SherpaSttEngine({PcmMicSource? mic, this.decoder})
    : _mic = mic ?? RecordPcmMicSource();

  final PcmMicSource _mic;
  final WhisperDecoder? decoder;
  final _segments = StreamController<SttSegment>.broadcast();
  final _rms = StreamController<double>.broadcast();
  final _status = StreamController<SttStatus>.broadcast();

  WhisperIsolate? _worker;
  StreamSubscription<Uint8List>? _micSubscription;
  Object? _capture;
  bool _micStarted = false;
  bool _disposed = false;
  Future<void> _operations = Future<void>.value();

  @override
  Stream<SttSegment> get segments => _segments.stream;
  @override
  Stream<double> get rmsLevel => _rms.stream;
  @override
  Stream<SttStatus> get status => _status.stream;

  @override
  Future<void> start(VoiceModelFiles files) => _schedule(() async {
    if (_disposed || _capture != null) return;
    _status.add(SttStatus.starting);
    final capture = _capture = Object();
    try {
      if (!await _mic.hasPermission()) {
        await _failCapture();
        return;
      }
      final worker = _worker = await WhisperIsolate.start(
        files,
        onSegment: _segments.add,
        onFailure: () => _scheduleFailure(capture),
        decoder: decoder,
      );
      _micStarted = true;
      final stream = await _mic.startStream();
      _micSubscription = stream.listen(
        (bytes) {
          final samples = pcm16ToFloat32(bytes);
          if (samples.isEmpty) return;
          _rms.add(sampleRms(samples));
          worker.addSamples(samples);
        },
        onError: (Object _) => _scheduleFailure(capture),
        onDone: () => _scheduleFailure(capture),
      );
      _status.add(SttStatus.listening);
    } catch (_) {
      await _failCapture();
    }
  });

  @override
  Future<void> stop() => _schedule(_stop);

  Future<void> _stop() async {
    if (_capture == null) return;
    _status.add(SttStatus.stopping);
    try {
      await _endCapture(flush: true);
      _status.add(SttStatus.idle);
    } catch (_) {
      _status.add(SttStatus.error);
    }
  }

  @override
  Future<void> dispose() => _schedule(() async {
    if (_disposed) return;
    _disposed = true;
    await _stop();
    try {
      if (_mic is RecordPcmMicSource) await _mic.dispose();
    } finally {
      await Future.wait([_segments.close(), _rms.close(), _status.close()]);
    }
  });

  Future<void> _schedule(Future<void> Function() run) {
    final operation = _operations.then((_) => run());
    _operations = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _scheduleFailure(Object capture) {
    if (_capture != capture) return;
    unawaited(
      _schedule(() async {
        if (_capture == capture) await _failCapture();
      }),
    );
  }

  Future<void> _failCapture() async {
    try {
      await _endCapture(flush: false);
    } catch (_) {
      // A recorder failure can also fail cleanup.
    }
    _status.add(SttStatus.error);
  }

  Future<void> _endCapture({required bool flush}) async {
    _capture = null;
    final worker = _worker;
    final micSubscription = _micSubscription;
    _worker = null;
    _micSubscription = null;
    try {
      try {
        if (_micStarted) await _mic.stop();
      } finally {
        _micStarted = false;
        await micSubscription?.cancel();
      }
      if (flush) await worker?.flush();
    } finally {
      await worker?.dispose();
    }
  }
}
