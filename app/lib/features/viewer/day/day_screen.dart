import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_icon.dart';
import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../domain/viewer/day_view.dart';
import '../viewer_cubit.dart';
import '../widgets/day_ribbon.dart';
import '../widgets/viewer_page.dart';

/// Day tab: "What did my day look like?"
class DayScreen extends StatelessWidget {
  const DayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ViewerCubit>().state;
    if (!s.loaded) return const SizedBox.shrink();
    final date = s.dayShown;
    final first = s.dates.isEmpty ? s.today : s.dates.first;
    final view = dayView(s.events, date);
    return _DayBody(
      key: ValueKey(date),
      view: view,
      refreshedAt: s.refreshedAt,
      canPrev: date.compareTo(first) > 0,
      canNext: date.compareTo(s.today) < 0,
      isToday: date == s.today,
    );
  }
}

class _DayBody extends StatefulWidget {
  const _DayBody({
    super.key,
    required this.view,
    required this.refreshedAt,
    required this.canPrev,
    required this.canNext,
    required this.isToday,
  });

  final DayView view;
  final DateTime? refreshedAt;
  final bool canPrev;
  final bool canNext;
  final bool isToday;

  @override
  State<_DayBody> createState() => _DayBodyState();
}

class _DayBodyState extends State<_DayBody> {
  RibbonMark? _selected;
  bool _all = false;

  void _go(int delta) =>
      context.read<ViewerCubit>().showDay(addDays(widget.view.date, delta));

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final s = context.series;
    return ViewerPage(
      top: 22,
      children: [
        _Header(
          label: dayLabel(v.date),
          refreshedAt: widget.refreshedAt,
          onPrev: widget.canPrev ? () => _go(-1) : null,
          onNext: widget.canNext ? () => _go(1) : null,
        ),
        if (v.isEmpty)
          _EmptyDay(isToday: widget.isToday)
        else ...[
          _kpis(context, v),
          VCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CardHead('Your day, 00:00 → 24:00', note: 'tap a mark'),
                const SizedBox(height: 6),
                DayRibbon(
                  marks: v.marks,
                  selected: _selected,
                  onSelect: (m) => setState(() => _selected = m),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _selected?.detail ??
                          (v.marks.isEmpty
                              ? 'Nothing with a time this day.'
                              : 'Tap any mark on the ribbon to see what and when.'),
                      key: const ValueKey('ribbon-detail'),
                      style: context.text.caption.copyWith(
                        fontSize: 13,
                        color: context.colors.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (v.untimedCigs > 0 ||
              v.untimedSpendCount > 0 ||
              v.untimed.isNotEmpty)
            _Untimed(view: v),
          _Entries(
            view: v,
            showAll: _all,
            onMore: () => setState(() => _all = true),
            colors: {
              EntryKind.smoke: s.smoke,
              EntryKind.food: s.food,
              EntryKind.money: s.money,
              EntryKind.bus: s.bus,
              EntryKind.sleep: s.sleep,
              EntryKind.other: context.colors.textDim,
            },
          ),
        ],
      ],
    );
  }

  Widget _kpis(BuildContext context, DayView v) {
    final s = context.series;
    final colors = [s.smoke, s.sleep, s.money, s.bus];
    final tiles = [
      for (var i = 0; i < v.kpis.length; i++)
        KpiTile(
          color: colors[i],
          label: v.kpis[i].label,
          value: v.kpis[i].value,
          delta: v.kpis[i].delta,
        ),
    ];
    return Column(
      children: [
        Pair(tiles[0], tiles[1]),
        const SizedBox(height: 8),
        Pair(tiles[2], tiles[3]),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.label,
    required this.refreshedAt,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final DateTime? refreshedAt;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final sync = refreshedAt == null
        ? 'Read-only · not synced yet'
        : 'Read-only · synced from Events ${formatTime(refreshedAt!.toUtc().add(istOffset))}';
    return Row(
      children: [
        _RoundButton(
          key: const Key('day-prev'),
          icon: AppIcons.chevronLeft,
          label: 'Previous day',
          onTap: onPrev,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                label,
                style: context.text.h2.copyWith(
                  fontSize: 24,
                  letterSpacing: -0.24,
                ),
              ),
              const SizedBox(height: 2),
              Semantics(
                button: true,
                label: '$sync. Open settings',
                child: ExcludeSemantics(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.push('/settings'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(sync, style: small(context, size: 12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _RoundButton(
          key: const Key('day-next'),
          icon: AppIcons.chevron,
          label: 'Next day',
          onTap: onNext,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final AppIcons icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: c.surface,
          shape: CircleBorder(side: BorderSide(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AppIcon(
                  icon,
                  size: 18,
                  stroke: 2,
                  color: onTap == null
                      ? c.textDim.withValues(alpha: 0.4)
                      : c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.isToday});
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return VCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday ? 'Nothing logged yet today' : 'Nothing logged this day',
            style: context.text.label,
          ),
          const SizedBox(height: 4),
          Text(
            isToday
                ? 'Tell the logging agent what happened. It shows up here after the next sync; pull down to sync now.'
                : 'No rows in Events for this date. Use ‹ to go back further.',
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}

class _Untimed extends StatelessWidget {
  const _Untimed({required this.view});
  final DayView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.series;
    Widget badge(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.warnWell,
        border: Border.all(color: c.warnBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: small(context, size: 12).copyWith(color: s.untimedText),
      ),
    );
    Widget chip(String text) => Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: small(context, size: 12).copyWith(color: c.textSoft),
      ),
    );
    final n = view.untimedCigs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logged without a time', style: small(context, size: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (n > 0)
              badge(
                '${trimNum(n)} ${n == 1 ? 'cigarette' : 'cigarettes'} with no time',
              ),
            if (view.untimedSpendCount > 0)
              chip(
                '${view.untimedSpendCount} ${view.untimedSpendCount == 1 ? 'payment' : 'payments'} · ${rupees(view.untimedSpend)}',
              ),
            for (final u in view.untimed) chip(u),
          ],
        ),
      ],
    );
  }
}

class _Entries extends StatelessWidget {
  const _Entries({
    required this.view,
    required this.showAll,
    required this.onMore,
    required this.colors,
  });

  final DayView view;
  final bool showAll;
  final VoidCallback onMore;
  final Map<EntryKind, Color> colors;

  static const _first = 6;

  @override
  Widget build(BuildContext context) {
    final rows = view.entries;
    final shown = showAll ? rows : rows.take(_first).toList();
    final more = rows.length - shown.length;
    final c = context.colors;
    return VCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        children: [
          for (final e in shown)
            Container(
              constraints: const BoxConstraints(minHeight: 30),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.divider)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      hhmmOf(e.minute),
                      style: context.text.caption.copyWith(
                        fontSize: 13,
                        color: c.textDim,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Swatch(colors[e.kind]!),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.caption.copyWith(
                        fontSize: 13,
                        color: c.text,
                      ),
                    ),
                  ),
                  if (e.amount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      rupees(e.amount),
                      style: context.text.caption.copyWith(fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          if (more > 0)
            InkWell(
              onTap: onMore,
              child: Container(
                alignment: Alignment.centerLeft,
                constraints: const BoxConstraints(minHeight: 44),
                child: Text(
                  '+$more more timed ${more == 1 ? 'entry' : 'entries'} · show all',
                  style: small(context, size: 12),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  rows.isEmpty
                      ? 'No timed entries this day'
                      : 'All timed entries shown',
                  style: small(context, size: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
