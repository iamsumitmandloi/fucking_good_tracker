import 'package:equatable/equatable.dart';

import '../event.dart';
import '../quicklog/parser.dart';

/// Paths on disk for the offline Whisper + Silero-VAD model bundle.
class VoiceModelFiles extends Equatable {
  const VoiceModelFiles({
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
    required this.vadPath,
  });

  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
  final String vadPath;

  @override
  List<Object?> get props => [encoderPath, decoderPath, tokensPath, vadPath];
}

enum VoiceModelStatus { missing, downloading, ready, error }

/// Current state of the offline voice model bundle on disk.
class VoiceModelState extends Equatable {
  const VoiceModelState({
    required this.status,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.files,
  });

  final VoiceModelStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;
  final VoiceModelFiles? files;

  @override
  List<Object?> get props => [
    status,
    progress,
    downloadedBytes,
    totalBytes,
    error,
    files,
  ];
}

/// Manages downloading, verifying, and deleting offline voice models.
abstract interface class VoiceModelRepository {
  Stream<VoiceModelState> watchState();
  Future<VoiceModelState> currentState();
  Future<void> download({bool force = false});
  Future<void> delete();
}

/// A decoded speech segment produced by [SttEngine].
class SttSegment extends Equatable {
  const SttSegment({
    required this.text,
    this.durationMs = 0,
    this.decodeMs = 0,
    this.isFinal = true,
  });

  final String text;
  final int durationMs;
  final int decodeMs;
  final bool isFinal;

  @override
  List<Object?> get props => [text, durationMs, decodeMs, isFinal];
}

enum SttStatus { idle, starting, listening, stopping, error }

/// Offline streaming speech-to-text engine interface.
abstract interface class SttEngine {
  Stream<SttSegment> get segments;

  /// Normalized mic amplitude (`0.0`..`1.0`) for waveform rendering.
  Stream<double> get rmsLevel;
  Stream<SttStatus> get status;

  Future<void> start(VoiceModelFiles files);
  Future<void> stop();
  Future<void> dispose();
}

/// One editable entry in a reviewed voice draft before committing to Drift.
class VoiceDraftItem extends Equatable {
  const VoiceDraftItem({
    required this.entry,
    this.dateOverride,
    this.note,
    this.included = true,
  });

  final ParsedEntry entry;
  final String? dateOverride;
  final String? note;
  final bool included;

  @override
  List<Object?> get props => [entry, dateOverride, note, included];
}

/// Output of parsing a voice transcript into a reviewable draft.
class VoiceDraftResult extends Equatable {
  VoiceDraftResult({
    required this.normalizedText,
    List<VoiceDraftItem> items = const [],
    List<String> ignoredPlans = const [],
    List<String> warnings = const [],
    this.hasUnparsedFallback = false,
  }) : items = List.unmodifiable(items),
       ignoredPlans = List.unmodifiable(ignoredPlans),
       warnings = List.unmodifiable(warnings);

  final String normalizedText;
  final List<VoiceDraftItem> items;
  final List<String> ignoredPlans;
  final List<String> warnings;
  final bool hasUnparsedFallback;

  @override
  List<Object?> get props => [
    normalizedText,
    items,
    ignoredPlans,
    warnings,
    hasUnparsedFallback,
  ];
}

/// Turns a spoken transcript into an editable [VoiceDraftResult] offline.
abstract interface class VoiceDraftParser {
  VoiceDraftResult parse({
    required String transcript,
    required DateTime nowIst,
    required double cigPrice,
    required double teaPrice,
    List<Event> recentEvents = const [],
  });
}
