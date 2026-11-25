import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/deps.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/app_icon.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../domain/event.dart';
import '../../domain/event_type.dart';
import '../../domain/quicklog/build_events.dart';
import '../../domain/quicklog/parser.dart';
import '../../domain/voice/voice_contracts.dart';
import 'quicklog_cubit.dart';
import 'voice_session_cubit.dart';

/// Opens the "Log anything" sheet. Returns the events to log, or null when
/// dismissed. The caller writes them.
Future<QuickLogOutcome?> showQuickLog(
  BuildContext context, {
  String prefill = '',
  String Function() idFactory = newEventId,
  bool autoStartVoice = false,
}) {
  return showModalBottomSheet<QuickLogOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    barrierColor: const Color(0x8C050607),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(context.dims.rSheet),
      ),
      side: BorderSide(color: context.colors.border),
    ),
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (c) => QuickLogCubit(
            events: c.read(),
            settings: c.read(),
            clock: c.read(),
            prefill: prefill,
            idFactory: idFactory,
          ),
        ),
        BlocProvider(
          create: (c) {
            final deps = c.read<AppDeps>();
            return VoiceSessionCubit(
              models: deps.voiceModels,
              createEngine: deps.createSttEngine,
              parser: deps.voiceDraftParser,
              clock: deps.clock,
              settings: deps.settings,
              events: deps.events,
              idFactory: idFactory,
            );
          },
        ),
      ],
      child: QuickLogSheet(prefill: prefill, autoStartVoice: autoStartVoice),
    ),
  );
}

class QuickLogSheet extends StatefulWidget {
  const QuickLogSheet({
    super.key,
    this.prefill = '',
    this.autoStartVoice = false,
  });

  final String prefill;
  final bool autoStartVoice;

  @override
  State<QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<QuickLogSheet> {
  late final _controller = TextEditingController(text: widget.prefill)
    ..selection = TextSelection.collapsed(offset: widget.prefill.length);
  final _transcript = TextEditingController();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStartVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toggleMic();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _transcript.dispose();
    super.dispose();
  }

  void _toggleMic() {
    final voice = context.read<VoiceSessionCubit>();
    FocusScope.of(context).unfocus();
    if (voice.state.status == SttStatus.listening) {
      unawaited(voice.stop());
    } else {
      unawaited(voice.start(initialTranscript: _controller.text));
    }
  }

  void _submit(QuickLogOutcome? outcome) {
    if (_submitted || outcome == null) return;
    _submitted = true;
    Navigator.of(context).pop(outcome);
  }

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<QuickLogCubit>();
    final now = cubit.state.nowIst;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null && context.mounted) {
      cubit.pickTime(hhmmOf(t.hour * 60 + t.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<QuickLogCubit>().state;
    final cubit = context.read<QuickLogCubit>();
    final voiceCubit = context.watch<VoiceSessionCubit>();
    final voice = voiceCubit.state;
    final reviewingVoice = voice.draft != null;
    final c = context.colors;
    final n = s.entries.length;
    final included = voice.includedCount;
    return PopScope<QuickLogOutcome>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(voiceCubit.endSession());
      },
      child: BlocListener<VoiceSessionCubit, VoiceSessionState>(
        listenWhen: (previous, next) => previous.transcript != next.transcript,
        listener: (_, state) {
          if (_transcript.text == state.transcript) return;
          _transcript.value = TextEditingValue(
            text: state.transcript,
            selection: TextSelection.collapsed(offset: state.transcript.length),
          );
        },
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.borderStrong,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Log anything', style: context.text.h2),
                      ),
                      _VoiceMic(state: voice, onTap: _toggleMic),
                      const SizedBox(width: 6),
                      _RoundIcon(
                        icon: AppIcons.close,
                        label: 'Close',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            reviewingVoice
                                ? 'Transcript'
                                : "Type it like you'd text it",
                            style: context.text.caption,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            key: Key(
                              reviewingVoice
                                  ? 'voice-transcript'
                                  : 'quicklog-input',
                            ),
                            controller: reviewingVoice
                                ? _transcript
                                : _controller,
                            autofocus:
                                !reviewingVoice && !widget.autoStartVoice,
                            readOnly: reviewingVoice && voice.busy,
                            onChanged: reviewingVoice
                                ? voiceCubit.onTranscriptEdited
                                : cubit.setText,
                            minLines: 1,
                            maxLines: reviewingVoice ? 4 : 1,
                            textInputAction: TextInputAction.done,
                            style: context.text.body.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                            ),
                            cursorColor: c.accent,
                            decoration: InputDecoration(
                              hintText: reviewingVoice
                                  ? 'Speak or edit the transcript'
                                  : '1 cig + tea 45',
                              hintStyle: context.text.body.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: c.textDim,
                              ),
                              filled: true,
                              fillColor: c.bg,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 15,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: c.borderStrong),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: c.accent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (voice.modelMissing) ...[
                            const SizedBox(height: 12),
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Download Whisper base (~160 MB) in Settings for offline voice',
                                    style: context.text.bodyS,
                                  ),
                                  const SizedBox(height: 8),
                                  OutlineButton(
                                    label: 'Open Settings',
                                    onPressed: () => context.push('/settings'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (voice.status == SttStatus.error) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Could not record. Check microphone access and try again.',
                              style: context.text.bodyS.copyWith(color: c.warn),
                            ),
                          ],
                          if (reviewingVoice) ...[
                            const SizedBox(height: 16),
                            _VoiceReview(state: voice, cubit: voiceCubit),
                          ] else ...[
                            const SizedBox(height: 16),
                            _Preview(state: s),
                            const SizedBox(height: 16),
                            Text('When', style: context.text.caption),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Pill(
                                  label: 'Now · ${formatTime(s.nowIst)}',
                                  selected: s.mode == WhenMode.now,
                                  onTap: () => cubit.setMode(WhenMode.now),
                                ),
                                _Pill(
                                  label: '15 min ago',
                                  selected: s.mode == WhenMode.fifteenAgo,
                                  onTap: () =>
                                      cubit.setMode(WhenMode.fifteenAgo),
                                ),
                                _Pill(
                                  label: '~ Approx',
                                  selected: s.mode == WhenMode.approx,
                                  onTap: () => cubit.setMode(WhenMode.approx),
                                ),
                                _Pill(
                                  label:
                                      s.mode == WhenMode.pick &&
                                          s.pickedTime != null
                                      ? s.pickedTime!
                                      : 'Pick time',
                                  selected: s.mode == WhenMode.pick,
                                  onTap: () => _pick(context),
                                ),
                              ],
                            ),
                            if (s.usuals.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Repeat a usual',
                                style: context.text.caption,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final u in s.usuals)
                                    _UsualChip(
                                      text: u.chipText,
                                      onTap: () => cubit.addUsual(u),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      AppIcon(AppIcons.clock, size: 16, color: c.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Saved offline · syncs to the sheet when the bus gets signal',
                          style: context.text.caption,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  PrimaryButton(
                    key: const Key('quicklog-submit'),
                    label: reviewingVoice && included == 0
                        ? 'Confirm & log'
                        : reviewingVoice
                        ? 'Confirm & log $included ${included == 1 ? 'entry' : 'entries'}'
                        : n == 0
                        ? 'Log'
                        : 'Log $n ${n == 1 ? 'entry' : 'entries'}',
                    height: 54,
                    radius: 16,
                    onPressed: reviewingVoice
                        ? (voice.canCommit
                              ? () => _submit(voiceCubit.commit())
                              : null)
                        : (n == 0 || voice.busy
                              ? null
                              : () => _submit(QuickLogOutcome(cubit.build()))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceMic extends StatelessWidget {
  const _VoiceMic({required this.state, required this.onTap});

  final VoiceSessionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final listening = state.status == SttStatus.listening;
    return IconButton(
      key: const Key('voice-mic'),
      tooltip: listening ? 'Stop recording' : 'Start voice logging',
      onPressed: listening || !state.busy ? onTap : null,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 44),
        backgroundColor: listening ? c.accent : c.surface2,
      ),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            AppIcons.mic,
            size: 20,
            color: listening ? c.onAccent : c.text,
          ),
          if (listening) ...[
            const SizedBox(width: 4),
            for (final scale in [0.6, 1.0, 0.75])
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 2,
                height: 4 + 16 * state.rms * scale,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: c.onAccent,
              ),
          ],
        ],
      ),
    );
  }
}

class _VoiceReview extends StatelessWidget {
  const _VoiceReview({required this.state, required this.cubit});

  final VoiceSessionState state;
  final VoiceSessionCubit cubit;

  @override
  Widget build(BuildContext context) {
    final draft = state.draft!;
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Review draft', style: context.text.label),
          if (state.busy) ...[
            const SizedBox(height: 6),
            Text(switch (state.status) {
              SttStatus.starting => 'Starting microphone…',
              SttStatus.stopping => 'Finishing transcription…',
              _ => 'Listening… Tap the mic to stop and review.',
            }, style: context.text.caption),
          ],
          if (draft.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            AppCard(
              color: colors.warnWell,
              borderColor: colors.warnBorder,
              child: Text(
                draft.warnings.join('\n'),
                style: context.text.caption.copyWith(color: colors.warn),
              ),
            ),
          ],
          if (draft.ignoredPlans.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final plan in draft.ignoredPlans)
                  Tag('Skipped plan: $plan'),
              ],
            ),
          ],
          for (final (index, item) in draft.items.indexed) ...[
            const Divider(height: 12),
            _VoiceReviewRow(
              key: ValueKey((index, item.entry.raw, item.entry.type)),
              item: item,
              index: index,
              state: state,
              cubit: cubit,
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceReviewRow extends StatelessWidget {
  const _VoiceReviewRow({
    super.key,
    required this.item,
    required this.index,
    required this.state,
    required this.cubit,
  });

  static final _amountPattern = RegExp(r'^\d{0,10}(?:\.\d{0,2})?$');

  final VoiceDraftItem item;
  final int index;
  final VoiceSessionState state;
  final VoiceSessionCubit cubit;

  Future<void> _pickTime(BuildContext context) async {
    final current =
        minutesOf(item.entry.time) ??
        (state.nowIst.hour * 60 + state.nowIst.minute);
    FocusScope.of(context).unfocus();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (context.mounted && time != null) {
      cubit.updateItemTime(index, hhmmOf(time.hour * 60 + time.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final amount = entry.amount;
    final unlinked = entry.type == EventType.spend;
    final title = unlinked && amount != null
        ? '${entry.title} · ${rupees(amount, decimals: true)}'
        : entry.title;
    final today = formatDate(state.nowIst);
    final date = item.dateOverride;
    final tags = [
      if (entry.approx) '~ approx',
      if (date != null && date != today)
        date == addDays(today, -1) ? 'yesterday' : date,
      if (unlinked) 'Unlinked spend',
      if (entry.source == 'lazypay') 'Pay later',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Checkbox(
                key: Key('voice-include-$index'),
                semanticLabel: 'Include ${entry.title}',
                value: item.included,
                onChanged: state.busy ? null : (_) => cubit.toggleItem(index),
              ),
            ),
            Expanded(child: Text(title, style: context.text.bodyS)),
            if (!state.busy) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 92,
                child: TextFormField(
                  key: Key('voice-amount-$index'),
                  initialValue: amount == null
                      ? ''
                      : trimNum(amount, digits: 2),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, value) => _amountPattern.hasMatch(value.text)
                          ? value
                          : oldValue,
                    ),
                  ],
                  decoration: const InputDecoration(
                    constraints: BoxConstraints(minHeight: 44),
                    labelText: 'Amount ₹',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                  ),
                  style: context.text.bodyS,
                  onChanged: (text) {
                    final value = double.tryParse(text);
                    cubit.updateItemAmount(
                      index,
                      value == null || value <= 0 ? null : value,
                    );
                  },
                ),
              ),
              _RoundIcon(
                icon: AppIcons.close,
                label: 'Remove ${entry.title}',
                onTap: () => cubit.removeItem(index),
                size: 16,
                plain: true,
              ),
            ] else if (!unlinked && amount != null)
              Text(rupees(amount, decimals: true), style: context.text.caption),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final label in tags) Tag(label),
              if (state.busy && entry.time != null) Tag(entry.time!),
              if (!state.busy) ...[
                TextButton(
                  key: Key('voice-time-$index'),
                  onPressed: () => _pickTime(context),
                  child: Text(entry.time ?? 'Add time'),
                ),
                if (entry.time != null)
                  TextButton(
                    onPressed: () => cubit.updateItemTime(index, null),
                    child: const Text('Clear time'),
                  ),
              ],
            ],
          ),
        ),
        if (!state.busy && unlinked && item.included && (amount ?? 0) <= 0)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              'Enter an amount to log this spend.',
              style: context.text.caption.copyWith(color: context.colors.warn),
            ),
          ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.state});
  final QuickLogState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = state.entries;
    final events = state.preview;
    final parsedCount = state.parsed.entries.length;
    final total = state.total;
    final rows = <Widget>[
      for (var i = 0; i < entries.length; i++)
        _PreviewRow(
          entry: entries[i],
          event: events[i],
          today: state.today,
          onRemove: i >= parsedCount
              ? () => context.read<QuickLogCubit>().removeExtra(i - parsedCount)
              : null,
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Try: 1 cig + tea 45 · lunch 130 · weight 87.9 · slept 22:30',
                style: context.text.caption,
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.divider),
                  rows[i],
                ],
                if (total != null && (entries.length > 1)) ...[
                  Divider(height: 1, color: c.divider),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.parsed.splitTotal != null
                                ? 'One payment, split for counts'
                                : 'Total',
                            style: context.text.caption,
                          ),
                        ),
                        Text(
                          rupees(total, decimals: true),
                          style: context.text.statS.copyWith(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.entry,
    required this.event,
    required this.today,
    this.onRemove,
  });

  final ParsedEntry entry;
  final Event event;
  final String today;
  final VoidCallback? onRemove;

  static const _timeInTitle = {
    EventType.sleep,
    EventType.wake,
    EventType.busBoard,
    EventType.busArrive,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = entry.type == EventType.note;
    final when = [
      if (entry.time != null && !_timeInTitle.contains(entry.type))
        'at ${entry.time}',
      if (event.date != today) 'yesterday',
      if (entry.source == 'lazypay') 'pay later',
    ].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text.rich(
                TextSpan(
                  text: '${entry.approx ? '~ ' : ''}${entry.title}',
                  children: [
                    if (when.isNotEmpty)
                      TextSpan(text: '  $when', style: context.text.caption),
                  ],
                ),
                style: context.text.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: note ? c.textMuted : c.text,
                ),
              ),
            ),
          ),
          if (entry.amount != null)
            Text(
              rupees(entry.amount, decimals: true),
              style: context.text.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: c.textMuted,
              ),
            ),
          if (onRemove != null)
            _RoundIcon(
              icon: AppIcons.close,
              label: 'Remove ${entry.title}',
              onTap: onRemove!,
              size: 16,
              plain: true,
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.accent : Colors.transparent,
        shape: StadiumBorder(
          side: selected ? BorderSide.none : BorderSide(color: c.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: context.text.body.copyWith(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? c.onAccent : c.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsualChip extends StatelessWidget {
  const _UsualChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(
            text,
            style: context.text.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 20,
    this.plain = false,
  });

  final AppIcons icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: plain ? Colors.transparent : c.surface2,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AppIcon(icon, size: size, color: c.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
