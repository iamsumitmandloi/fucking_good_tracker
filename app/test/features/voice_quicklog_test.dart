import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:starting_again/core/feature_flags.dart';
import 'package:starting_again/data/sync/sync_service.dart';
import 'package:starting_again/domain/event_type.dart';
import 'package:starting_again/domain/voice/voice_contracts.dart';

import '../support/app_harness.dart';

const _files = VoiceModelFiles(
  encoderPath: 'encoder',
  decoderPath: 'decoder',
  tokensPath: 'tokens',
  vadPath: 'vad',
);

class _VoiceModels implements VoiceModelRepository {
  _VoiceModels({this.ready = true});

  bool ready;
  final _changes = StreamController<VoiceModelState>.broadcast();

  VoiceModelState get _state => ready
      ? const VoiceModelState(status: VoiceModelStatus.ready, files: _files)
      : const VoiceModelState(status: VoiceModelStatus.missing);

  @override
  Future<VoiceModelState> currentState() async => _state;

  @override
  Stream<VoiceModelState> watchState() async* {
    yield _state;
    yield* _changes.stream;
  }

  @override
  Future<void> download({bool force = false}) async {
    ready = true;
    _changes.add(_state);
  }

  @override
  Future<void> delete() async {
    ready = false;
    _changes.add(_state);
  }

  Future<void> close() => _changes.close();
}

class _VoiceEngine implements SttEngine {
  final _segments = StreamController<SttSegment>.broadcast();
  final _rms = StreamController<double>.broadcast();
  final _status = StreamController<SttStatus>.broadcast();

  int starts = 0;
  int stops = 0;
  bool disposed = false;
  Completer<void>? finishStop;
  String? finalWords;

  @override
  Stream<SttSegment> get segments => _segments.stream;
  @override
  Stream<double> get rmsLevel => _rms.stream;
  @override
  Stream<SttStatus> get status => _status.stream;

  void speak(String text, {bool isFinal = true}) {
    _segments.add(SttSegment(text: text, isFinal: isFinal));
    _rms.add(0.6);
  }

  @override
  Future<void> start(VoiceModelFiles files) async {
    expect(files, _files);
    starts++;
    _status.add(SttStatus.listening);
  }

  @override
  Future<void> stop() async {
    stops++;
    _status.add(SttStatus.stopping);
    await finishStop?.future;
    final last = finalWords;
    if (last != null) speak(last);
    _status.add(SttStatus.idle);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await Future.wait([_segments.close(), _rms.close(), _status.close()]);
  }
}

final _fab = find.byKey(const Key('quicklog-fab'));
final _mic = find.byKey(const Key('voice-mic'));
final _transcript = find.byKey(const Key('voice-transcript'));
final _submit = find.byKey(const Key('quicklog-submit'));

Future<void> _openVoice(
  WidgetTester tester,
  AppHarness harness, {
  bool shortcut = false,
}) async {
  if (shortcut) {
    await tester.longPress(_fab);
  } else {
    await tester.tap(_fab);
  }
  await harness.settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
  if (!shortcut) {
    await tester.tap(_mic);
  }
  await harness.settle(tester);
}

Finder get _submitButton =>
    find.descendant(of: _submit, matching: find.byType(FilledButton));

Future<T> _settleOperation<T>(
  WidgetTester tester,
  AppHarness harness,
  Future<T> operation,
) async {
  var settled = false;
  final result = operation.whenComplete(() => settled = true);
  for (var attempt = 0; attempt < 5 && !settled; attempt++) {
    await harness.settle(tester);
  }
  expect(settled, isTrue, reason: 'The sync operation should finish.');
  return result;
}

void main() {
  setUp(() => FeatureFlags.logging = true);
  tearDown(() => FeatureFlags.logging = false);

  testWidgets('live corrections require confirmation and sync exactly once', (
    tester,
  ) async {
    final models = _VoiceModels();
    final engine = _VoiceEngine();
    final h = await AppHarness.create(
      voiceModels: models,
      createSttEngine: () => engine,
    );
    h.server.offline = true;
    try {
      await h.pump(tester, '/today');
      await _openVoice(tester, h);
      expect(engine.starts, 1);

      engine.speak('Today I had two cigarettes');
      await h.settle(tester);
      expect(find.text('Cigarette × 2'), findsOneWidget);

      engine.speak('actually three and one tea');
      await h.settle(tester);
      expect(find.text('Cigarette × 3'), findsOneWidget);
      expect(find.text('Tea × 1'), findsOneWidget);

      engine.speak('and spent 50');
      await h.settle(tester);
      final transcript = tester.widget<TextField>(_transcript).controller!.text;
      expect(transcript, endsWith('actually three and one tea and spent 50'));
      expect(find.text('Spend · ₹50'), findsOneWidget);
      expect(find.text('Unlinked spend'), findsOneWidget);
      expect(find.text('Confirm & log 3 entries'), findsOneWidget);
      expect(tester.widget<FilledButton>(_submitButton).onPressed, isNull);
      expect(await tester.runAsync(h.deps.events.all), isEmpty);
      expect(
        await tester.runAsync(() => h.deps.db.select(h.deps.db.outbox).get()),
        isEmpty,
      );

      await tester.tap(_mic);
      await h.settle(tester);
      expect(engine.stops, 1);
      final tea = find.byKey(const Key('voice-include-1'));
      await tester.ensureVisible(tea);
      await tester.tap(tea);
      await tester.pump();
      expect(find.text('Confirm & log 2 entries'), findsOneWidget);
      await tester.tap(_submit);
      await tester.pump(const Duration(milliseconds: 400));
      await h.settle(tester);

      expect(find.text('Log anything'), findsNothing);
      expect(find.byKey(const Key('undo-button')), findsOneWidget);
      expect(engine.disposed, isTrue);
      final rows = (await tester.runAsync(h.deps.events.all))!;
      expect(rows.map((row) => row.type).toSet(), {
        EventType.cigarette,
        EventType.spend,
      });
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.source == 'voice'), isTrue);
      expect(rows.every((row) => row.time == null), isTrue);
      final cigarette = rows.singleWhere(
        (row) => row.type == EventType.cigarette,
      );
      final spend = rows.singleWhere((row) => row.type == EventType.spend);
      expect(cigarette.qty, 3);
      expect(cigarette.amountInr, isNull);
      expect(spend.amountInr, 50);
      expect(spend.category, SpendCategory.other);
      final pending = (await tester.runAsync(
        () => h.deps.db.select(h.deps.db.outbox).get(),
      ))!;
      expect(
        pending.map((row) => row.id).toSet(),
        rows.map((row) => row.id).toSet(),
      );
      expect(
        pending.map((row) => (jsonDecode(row.payload) as Map)['source']),
        everyElement('voice'),
      );

      expect(
        await _settleOperation(tester, h, h.deps.sync.flushNow()),
        FlushOutcome.failed,
      );
      expect(h.server.posts, 0);
      expect(
        await tester.runAsync(() => h.deps.db.select(h.deps.db.outbox).get()),
        hasLength(2),
      );

      h.server.offline = false;
      await _settleOperation(tester, h, h.deps.appSync.syncNow());
      expect(
        await tester.runAsync(() => h.deps.db.select(h.deps.db.outbox).get()),
        isEmpty,
      );
      expect(
        h.server.events.map((row) => row['id']).toSet(),
        rows.map((row) => row.id).toSet(),
      );
      expect(
        await _settleOperation(tester, h, h.deps.sync.flushNow()),
        FlushOutcome.empty,
      );
      expect(h.server.posts, 1);
    } finally {
      await h.dispose(tester);
      await models.close();
      await engine.dispose();
    }
  });

  testWidgets('missing model keeps typing available and opens Settings', (
    tester,
  ) async {
    final models = _VoiceModels(ready: false);
    final engine = _VoiceEngine();
    final h = await AppHarness.create(
      voiceModels: models,
      createSttEngine: () => engine,
    );
    try {
      await h.pump(tester, '/today');
      await _openVoice(tester, h);
      expect(engine.starts, 0);
      expect(
        find.text(
          'Download Whisper base (~160 MB) in Settings for offline voice',
        ),
        findsOneWidget,
      );
      final typed = find.byKey(const Key('quicklog-input'));
      await tester.enterText(typed, 'tea');
      await h.settle(tester);
      expect(find.text('Log 1 entry'), findsOneWidget);
      expect(await tester.runAsync(h.deps.events.all), isEmpty);

      final settings = find.text('Open Settings');
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Whisper base (int8) + Silero VAD'), findsOneWidget);
      expect(find.text('Not downloaded (~160 MB)'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await h.settle(tester);
      expect(find.text('Ready offline'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<TextField>(typed).controller!.text, 'tea');
      await tester.tap(_mic);
      await h.settle(tester);
      expect(engine.starts, 1);
      expect(find.text('Tea × 1'), findsOneWidget);
      expect(await tester.runAsync(h.deps.events.all), isEmpty);
    } finally {
      await h.dispose(tester);
      await models.close();
      await engine.dispose();
    }
    expect(engine.disposed, isTrue);
  });

  testWidgets('waits for the last segment and saves transcript and row edits', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final models = _VoiceModels();
    final engine = _VoiceEngine()..finishStop = Completer<void>();
    final h = await AppHarness.create(
      voiceModels: models,
      createSttEngine: () => engine,
      tabs: {
        'Events': [
          {
            'id': 'previous-tea',
            'date': '2026-11-17',
            'time': '09:00',
            'type': 'tea',
            'qty': '1',
            'source': 'app',
          },
        ],
      },
    );
    try {
      await tester.runAsync(h.deps.events.refresh);
      await h.pump(tester, '/today');
      await _openVoice(tester, h, shortcut: true);
      expect(engine.starts, 1);
      engine.speak('yesterday had about two cigarettes');
      await h.settle(tester);
      expect(find.text('yesterday'), findsOneWidget);
      expect(find.text('~ approx'), findsOneWidget);

      await tester.tap(_mic);
      await h.settle(tester);
      expect(find.text('Finishing transcription…'), findsOneWidget);
      expect(tester.widget<FilledButton>(_submitButton).onPressed, isNull);
      engine.finalWords = 'and one tea';
      engine.finishStop!.complete();
      await h.settle(tester);
      expect(find.text('Tea × 1'), findsOneWidget);

      await tester.enterText(
        _transcript,
        'Yesterday I had about two cigarettes. Today I had one tea. '
        'Planning to order dinner.',
      );
      await h.settle(tester);
      expect(find.textContaining('Skipped plan:'), findsOneWidget);
      expect(find.text('You already logged Tea today'), findsOneWidget);

      final amount = find.byKey(const Key('voice-amount-0'));
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '35.50');
      await h.settle(tester);
      final time = find.byKey(const Key('voice-time-0'));
      await tester.ensureVisible(time);
      await tester.tap(time);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await h.settle(tester);
      expect(
        find.descendant(of: time, matching: find.text('18:02')),
        findsOneWidget,
      );

      final remove = find.bySemanticsLabel('Remove Tea × 1');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();
      expect(find.text('Tea × 1'), findsNothing);
      expect(find.text('Confirm & log 1 entry'), findsOneWidget);

      await tester.tap(_submit);
      await tester.pump(const Duration(milliseconds: 400));
      await h.settle(tester);
      final rows = (await tester.runAsync(h.deps.events.all))!
          .where((row) => row.source == 'voice')
          .toList();
      expect(rows, hasLength(2));
      expect(
        rows.every((row) => row.date == '2026-11-16' && row.time == '18:02'),
        isTrue,
      );
      expect(
        rows.singleWhere((row) => row.type == EventType.spend).amountInr,
        35.5,
      );
    } finally {
      if (!engine.finishStop!.isCompleted) engine.finishStop!.complete();
      await h.dispose(tester);
      await models.close();
      await engine.dispose();
    }
  });

  testWidgets('dismissing a live session disposes it without writing', (
    tester,
  ) async {
    final models = _VoiceModels();
    final engine = _VoiceEngine();
    final h = await AppHarness.create(
      voiceModels: models,
      createSttEngine: () => engine,
    );
    try {
      await h.pump(tester, '/today');
      await _openVoice(tester, h);
      engine.speak('two cigarettes');
      await h.settle(tester);
      expect(find.text('Cigarette × 2'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump(const Duration(milliseconds: 400));
      await h.settle(tester);
      expect(engine.disposed, isTrue);
      expect(await tester.runAsync(h.deps.events.all), isEmpty);
      expect(
        await tester.runAsync(() => h.deps.db.select(h.deps.db.outbox).get()),
        isEmpty,
      );
    } finally {
      await h.dispose(tester);
      await models.close();
      await engine.dispose();
    }
  });
}
