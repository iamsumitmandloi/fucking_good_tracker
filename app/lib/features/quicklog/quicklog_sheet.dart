import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

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
import 'quicklog_cubit.dart';

/// Opens the "Log anything" sheet. Returns the events to log, or null when
/// dismissed. The caller writes them.
Future<List<Event>?> showQuickLog(
  BuildContext context, {
  String prefill = '',
  String Function() idFactory = newEventId,
}) {
  return showModalBottomSheet<List<Event>>(
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
    builder: (_) => BlocProvider(
      create: (c) => QuickLogCubit(
        events: c.read(),
        settings: c.read(),
        clock: c.read(),
        prefill: prefill,
        idFactory: idFactory,
      ),
      child: QuickLogSheet(prefill: prefill),
    ),
  );
}

class QuickLogSheet extends StatefulWidget {
  const QuickLogSheet({super.key, this.prefill = ''});

  final String prefill;

  @override
  State<QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<QuickLogSheet> {
  late final _controller = TextEditingController(text: widget.prefill)
    ..selection = TextSelection.collapsed(offset: widget.prefill.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    if (t != null) cubit.pickTime(hhmmOf(t.hour * 60 + t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<QuickLogCubit>().state;
    final cubit = context.read<QuickLogCubit>();
    final c = context.colors;
    final n = s.entries.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                  Expanded(child: Text('Log anything', style: context.text.h2)),
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
                        "Type it like you'd text it",
                        style: context.text.caption,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('quicklog-input'),
                        controller: _controller,
                        autofocus: true,
                        onChanged: cubit.setText,
                        textInputAction: TextInputAction.done,
                        style: context.text.body.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                        ),
                        cursorColor: c.accent,
                        decoration: InputDecoration(
                          hintText: '1 cig + tea 45',
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
                            borderSide: BorderSide(color: c.accent, width: 1.5),
                          ),
                        ),
                      ),
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
                            onTap: () => cubit.setMode(WhenMode.fifteenAgo),
                          ),
                          _Pill(
                            label: '~ Approx',
                            selected: s.mode == WhenMode.approx,
                            onTap: () => cubit.setMode(WhenMode.approx),
                          ),
                          _Pill(
                            label:
                                s.mode == WhenMode.pick && s.pickedTime != null
                                ? s.pickedTime!
                                : 'Pick time',
                            selected: s.mode == WhenMode.pick,
                            onTap: () => _pick(context),
                          ),
                        ],
                      ),
                      if (s.usuals.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Repeat a usual', style: context.text.caption),
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
                label: n == 0
                    ? 'Log'
                    : 'Log $n ${n == 1 ? 'entry' : 'entries'}',
                height: 54,
                radius: 16,
                onPressed: n == 0
                    ? null
                    : () => Navigator.of(context).pop(cubit.build()),
              ),
            ],
          ),
        ),
      ),
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
