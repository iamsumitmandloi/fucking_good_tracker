import 'dart:async';
import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/settings_repository.dart';
import '../../domain/effective_events.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';
import '../../domain/quicklog/parser.dart';
import '../../domain/voice/voice_contracts.dart';
import '../../domain/voice/voice_draft.dart';

class QuickLogOutcome {
  const QuickLogOutcome(this.events);

  final List<Event> events;
}

class VoiceSessionState extends Equatable {
  const VoiceSessionState({
    required this.nowIst,
    this.status = SttStatus.idle,
    this.modelMissing = false,
    this.transcript = '',
    this.draft,
    this.rms = 0,
  });

  final DateTime nowIst;
  final SttStatus status;
  final bool modelMissing;
  final String transcript;
  final VoiceDraftResult? draft;
  final double rms;

  bool get busy =>
      status == SttStatus.starting ||
      status == SttStatus.listening ||
      status == SttStatus.stopping;

  List<VoiceDraftItem> get items => draft?.items ?? const [];
  int get includedCount => items.where((item) => item.included).length;
  bool get canCommit =>
      !busy &&
      includedCount > 0 &&
      items.every(
        (item) =>
            !item.included ||
            item.entry.type != EventType.spend ||
            (item.entry.amount ?? 0) > 0,
      );

  VoiceSessionState copyWith({
    DateTime? nowIst,
    SttStatus? status,
    bool? modelMissing,
    String? transcript,
    VoiceDraftResult? draft,
    double? rms,
  }) => VoiceSessionState(
    nowIst: nowIst ?? this.nowIst,
    status: status ?? this.status,
    modelMissing: modelMissing ?? this.modelMissing,
    transcript: transcript ?? this.transcript,
    draft: draft ?? this.draft,
    rms: rms ?? this.rms,
  );

  @override
  List<Object?> get props => [
    nowIst,
    status,
    modelMissing,
    transcript,
    draft,
    rms,
  ];
}

class VoiceSessionCubit extends Cubit<VoiceSessionState> {
  VoiceSessionCubit({
    required this._models,
    required this._createEngine,
    required this._parser,
    required this._clock,
    required this._settings,
    required this._events,
    this.idFactory = newEventId,
  }) : super(VoiceSessionState(nowIst: _clock.nowIst()));

  final VoiceModelRepository _models;
  final SttEngine Function() _createEngine;
  final VoiceDraftParser _parser;
  final Clock _clock;
  final SettingsRepository _settings;
  final EventsRepository _events;
  final String Function() idFactory;

  SttEngine? _engine;
  final _subscriptions = <StreamSubscription<Object?>>[];
  var _appSettings = const AppSettings();
  List<Event> _recentEvents = const [];
  String _confirmedTranscript = '';
  VoiceDraftResult? _parsed;
  List<VoiceDraftItem?> _reviewed = [];
  bool _closing = false;
  Future<void>? _shutdown;

  Future<void> start({String initialTranscript = ''}) async {
    if (_closing || state.busy) return;
    emit(state.copyWith(status: SttStatus.starting, modelMissing: false));
    try {
      final model = await _models.currentState();
      if (_closing) return;
      final files = model.files;
      if (model.status != VoiceModelStatus.ready || files == null) {
        emit(state.copyWith(status: SttStatus.idle, modelMissing: true));
        return;
      }

      final (settings, events) = await (_settings.load(), _events.all()).wait;
      if (_closing) return;
      _appSettings = settings;
      if (state.draft == null) {
        emit(state.copyWith(nowIst: _clock.nowIst()));
      }
      final today = formatDate(state.nowIst);
      _recentEvents = effectiveEvents(events)
          .where((event) => event.date == today)
          .toList();
      _confirmedTranscript = state.draft == null
          ? initialTranscript.trim()
          : state.transcript;
      _reparse(_confirmedTranscript);
      final engine = _engine ??= _connectEngine();
      await engine.start(files);
    } catch (_) {
      _captureFailed();
    }
  }

  SttEngine _connectEngine() {
    final engine = _createEngine();
    _subscriptions.addAll([
      engine.segments.listen(_onSegment),
      engine.rmsLevel.listen((level) {
        if (!_closing && state.status == SttStatus.listening) {
          emit(state.copyWith(rms: level.clamp(0.0, 1.0)));
        }
      }),
      engine.status.listen((status) {
        if (_closing) return;
        if (status == SttStatus.error) {
          _captureFailed();
        } else if (status == SttStatus.listening &&
            state.status == SttStatus.starting) {
          emit(state.copyWith(status: SttStatus.listening));
        }
      }),
    ]);
    return engine;
  }

  void _captureFailed() {
    if (!_closing) emit(state.copyWith(status: SttStatus.error, rms: 0));
  }

  void _onSegment(SttSegment segment) {
    final text = segment.text.trim();
    if (_closing || !state.busy || text.isEmpty) return;
    final transcript = _confirmedTranscript.isEmpty
        ? text
        : '$_confirmedTranscript $text';
    if (segment.isFinal) _confirmedTranscript = transcript;
    _reparse(transcript);
  }

  Future<void> stop() async {
    if (_closing || state.status != SttStatus.listening) return;
    emit(state.copyWith(status: SttStatus.stopping, rms: 0));
    try {
      await _engine!.stop();
      // Drain final segments already queued on the broadcast stream.
      await Future<void>.delayed(Duration.zero);
      if (!_closing && state.status == SttStatus.stopping) {
        emit(state.copyWith(status: SttStatus.idle));
      }
    } catch (_) {
      _captureFailed();
    }
  }

  void onTranscriptEdited(String text) {
    if (_closing || state.busy || state.draft == null) return;
    _confirmedTranscript = text.trim();
    _reparse(text);
  }

  void _reparse(String text) {
    final previous = _parsed?.items ?? const <VoiceDraftItem>[];
    final reviewed = <(String, VoiceDraftItem), Queue<VoiceDraftItem?>>{};
    for (var i = 0; i < previous.length; i++) {
      final item = previous[i];
      (reviewed[(item.entry.raw, item)] ??= Queue()).add(_reviewed[i]);
    }
    final parsed = _parsed = _parser.parse(
      transcript: text,
      nowIst: state.nowIst,
      cigPrice: _appSettings.cigPrice,
      teaPrice: _appSettings.teaPrice,
      recentEvents: _recentEvents,
    );
    _reviewed = [
      for (final item in parsed.items)
        switch (reviewed[(item.entry.raw, item)]) {
          final Queue<VoiceDraftItem?> queue when queue.isNotEmpty =>
            queue.removeFirst(),
          _ => item,
        },
    ];
    _publishDraft(text);
  }

  void _publishDraft(String transcript) {
    final parsed = _parsed!;
    emit(
      state.copyWith(
        transcript: transcript,
        draft: VoiceDraftResult(
          normalizedText: parsed.normalizedText,
          ignoredPlans: parsed.ignoredPlans,
          warnings: parsed.warnings,
          hasUnparsedFallback: parsed.hasUnparsedFallback,
          items: _reviewed.whereType<VoiceDraftItem>().toList(),
        ),
      ),
    );
  }

  void toggleItem(int index) => _editItem(
    index,
    (item) => VoiceDraftItem(
      entry: item.entry,
      dateOverride: item.dateOverride,
      note: item.note,
      included: !item.included,
    ),
  );

  void removeItem(int index) => _editItem(index, (_) => null);

  void updateItemAmount(int index, double? amount) {
    if (amount != null && (!amount.isFinite || amount <= 0)) return;
    _editItem(index, (item) => _withEntry(item, item.entry.withAmount(amount)));
  }

  void updateItemTime(int index, String? time) {
    final minutes = minutesOf(time);
    if (time != null && (minutes == null || minutes >= 24 * 60)) return;
    _editItem(index, (item) {
      final entry = item.entry;
      return _withEntry(
        item,
        ParsedEntry(
          type: entry.type,
          raw: entry.raw,
          qty: entry.qty,
          unit: entry.unit,
          label: entry.label,
          amount: entry.amount,
          category: entry.category,
          time: minutes == null ? null : hhmmOf(minutes),
          approx: entry.approx,
          note: entry.note,
          source: entry.source,
        ),
      );
    });
  }

  VoiceDraftItem _withEntry(VoiceDraftItem item, ParsedEntry entry) =>
      VoiceDraftItem(
        entry: entry,
        dateOverride: item.dateOverride,
        note: item.note,
        included: item.included,
      );

  void _editItem(int index, VoiceDraftItem? Function(VoiceDraftItem) edit) {
    if (_closing || state.busy || index < 0) return;
    var visible = 0;
    for (var i = 0; i < _reviewed.length; i++) {
      final item = _reviewed[i];
      if (item == null) continue;
      if (visible++ != index) continue;
      _reviewed[i] = edit(item);
      _publishDraft(state.transcript);
      return;
    }
  }

  QuickLogOutcome? commit() {
    if (_closing || !state.canCommit) return null;
    return QuickLogOutcome(
      const VoiceDraftBuilder().toEvents(
        state.items,
        nowIst: state.nowIst,
        nextId: idFactory,
      ),
    );
  }

  Future<void> endSession() => _shutdown ??= _releaseEngine();

  Future<void> _releaseEngine() async {
    _closing = true;
    try {
      try {
        await Future.wait(
          _subscriptions.map((subscription) => subscription.cancel()),
        );
      } finally {
        await _engine?.dispose();
      }
    } catch (_) {
      // Closing the sheet already ended review.
    }
  }

  @override
  Future<void> close() async {
    await endSession();
    await super.close();
  }
}
