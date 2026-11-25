import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starting_again/data/voice/pcm_mic.dart';
import 'package:starting_again/data/voice/sherpa_stt_engine.dart';
import 'package:starting_again/domain/voice/voice_contracts.dart';

const _files = VoiceModelFiles(
  encoderPath: '',
  decoderPath: '',
  tokensPath: '',
  vadPath: '',
);

class _FakeMic implements PcmMicSource {
  StreamController<Uint8List>? _controller;
  bool permission = true;
  int starts = 0;
  int stops = 0;
  Uint8List? drainOnStop;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> startStream() async {
    starts++;
    return (_controller = StreamController<Uint8List>()).stream;
  }

  void add(List<int> bytes) => _controller!.add(Uint8List.fromList(bytes));

  @override
  Future<void> stop() async {
    stops++;
    final tail = drainOnStop;
    if (tail != null) _controller?.add(tail);
    await _controller?.close();
    _controller = null;
  }
}

Future<Iterable<SttSegment>> _decode(
  Float32List samples, {
  required bool flush,
}) async {
  if (flush) {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return [const SttSegment(text: 'final')];
  }
  final text = samples.single.toString();
  if (samples.single == 0) throw StateError('Test decoder failure');
  return [SttSegment(text: text)];
}

void main() {
  test('normalizes PCM16 little-endian samples', () {
    final pcm = Uint8List.fromList([0, 128, 255, 127, 0, 0]);
    expect(pcm16ToFloat32(pcm), Float32List.fromList([-1, 32767 / 32768, 0]));
  });

  test('computes normalized RMS', () {
    final pcm = Uint8List.fromList([0, 64, 0, 64]);
    expect(pcm16Rms(pcm), 0.5);
    expect(pcm16Rms(Uint8List(0)), 0);
  });

  test('permission denial emits error without starting a recording', () async {
    final mic = _FakeMic()..permission = false;
    final engine = SherpaSttEngine(mic: mic, decoder: _decode);
    addTearDown(engine.dispose);
    final statuses = <SttStatus>[];
    final subscription = engine.status.listen(statuses.add);
    addTearDown(subscription.cancel);
    final denied = engine.status.firstWhere((s) => s == SttStatus.error);

    await engine.start(_files);
    await denied;
    expect(statuses, [SttStatus.starting, SttStatus.error]);
    expect(mic.starts, 0);
    expect(mic.stops, 0);
  });

  test(
    'waits for queued PCM, the mic tail, and slow flush before idle',
    () async {
      final mic = _FakeMic()..drainOnStop = Uint8List.fromList([0, 128]);
      final engine = SherpaSttEngine(mic: mic, decoder: _decode);
      addTearDown(engine.dispose);
      final results = <Object>[];
      final subscriptions = [
        engine.segments.listen((segment) => results.add(segment.text)),
        engine.status.listen(results.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      final rms = engine.rmsLevel.first;
      final idle = engine.status.firstWhere((s) => s == SttStatus.idle);
      await engine.start(_files);
      mic.add([0, 64]);
      mic.add([0, 192]);
      await engine.stop();

      expect(await rms, 0.5);
      await idle;
      expect(results.whereType<String>(), ['0.5', '-0.5', '-1.0', 'final']);
      expect(
        results.indexOf('final'),
        lessThan(results.indexOf(SttStatus.idle)),
      );
      expect(mic.stops, 1);
    },
  );

  test('cleans up a failed decoder session so recording can restart', () async {
    final mic = _FakeMic();
    final engine = SherpaSttEngine(mic: mic, decoder: _decode);
    addTearDown(engine.dispose);
    final error = engine.status.firstWhere((s) => s == SttStatus.error);

    await engine.start(_files);
    mic.add([0, 0]);
    await error;
    expect(mic.stops, 1);

    final audio = engine.segments.first;
    await engine.start(_files);
    mic.add([0, 64]);
    expect((await audio).text, '0.5');
    await engine.stop();
    expect(mic.starts, 2);
    expect(mic.stops, 2);
  });

  test('serializes overlapping start and stop calls', () async {
    final mic = _FakeMic();
    final engine = SherpaSttEngine(mic: mic, decoder: _decode);
    addTearDown(engine.dispose);

    await Future.wait([
      engine.start(_files),
      engine.start(_files),
      engine.stop(),
      engine.stop(),
    ]);

    expect(mic.starts, 1);
    expect(mic.stops, 1);
  });
}
