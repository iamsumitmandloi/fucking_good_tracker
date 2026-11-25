import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

const pcmSampleRate = 16000;

abstract interface class PcmMicSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream();
  Future<void> stop();
}

class RecordPcmMicSource implements PcmMicSource {
  RecordPcmMicSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();
  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: pcmSampleRate,
      numChannels: 1,
    ),
  );

  @override
  Future<void> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}

Float32List pcm16ToFloat32(Uint8List bytes) {
  final count = bytes.length ~/ 2;
  final data = ByteData.sublistView(bytes);
  final samples = Float32List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

double pcm16Rms(Uint8List bytes) => sampleRms(pcm16ToFloat32(bytes));

double sampleRms(Float32List samples) {
  if (samples.isEmpty) return 0;
  var sum = 0.0;
  for (final sample in samples) {
    sum += sample * sample;
  }
  return math.sqrt(sum / samples.length).clamp(0.0, 1.0);
}
