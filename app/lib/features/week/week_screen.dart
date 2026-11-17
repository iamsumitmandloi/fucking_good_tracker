import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_sync.dart';
import '../../app/sync_status.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../data/repo/events_repository.dart';
import '../../data/repo/legacy_repository.dart';
import '../../domain/derivations/week.dart';
import '../../domain/derivations/weight.dart';
import 'week_cubit.dart';

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => WeekCubit(
        events: c.read(),
        legacy: c.read(),
        settings: c.read(),
        clock: c.read(),
      ),
      child: const _WeekView(),
    );
  }
}

/// "Wed 11 – Tue 17 Nov".
String rangeLabel(List<String> days) {
  if (days.isEmpty) return '';
  final a = parseDate(days.first)!;
  final b = parseDate(days.last)!;
  final left = a.month == b.month
      ? DateFormat('EEE d').format(a)
      : DateFormat('EEE d MMM').format(a);
  return '$left – ${DateFormat('EEE d MMM').format(b)}';
}

/// Pull-to-refresh for Week and Money: Events + legacy tabs (forced).
Future<void> refreshWithLegacy(BuildContext context) async {
  final events = context.read<EventsRepository>();
  final legacy = context.read<LegacyRepository>();
  await context.read<AppSync>().syncNow([
    events.refresh,
    () => legacy.refresh(force: true),
  ]);
}

class _WeekView extends StatelessWidget {
  const _WeekView();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<WeekCubit>().state;
    final d = context.dims;
    final stats = s.stats;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => refreshWithLegacy(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(d.screenH, d.screenTop, d.screenH, 24),
          children: [
            const SyncBanner(),
            ScreenHeader(
              caption: stats == null
                  ? ''
                  : '${rangeLabel(stats.days)} · ${stats.daysLogged} of ${stats.days.length} days logged',
              title: 'Week',
            ),
            SizedBox(height: d.gapL),
            if (stats != null) ...[
              if (s.flags.isNotEmpty) ...[
                _FlagsCard(state: s),
                SizedBox(height: d.gap),
              ],
              _CigCard(
                stats: stats,
                budget: s.settings.cigBudget,
                price: s.settings.cigPrice,
              ),
              SizedBox(height: d.gap),
              _SleepCard(stats: stats),
              SizedBox(height: d.gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _WeightCard(w: s.weight!)),
                    SizedBox(width: d.gap),
                    Expanded(child: _NotLoggedCard(stats: stats)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title, style: context.text.label),
      const SizedBox(width: 8),
      if (trailing != null)
        Expanded(
          child: Text(
            trailing!,
            textAlign: TextAlign.right,
            style: context.text.caption,
          ),
        ),
    ],
  );
}

class _CigCard extends StatelessWidget {
  const _CigCard({
    required this.stats,
    required this.budget,
    required this.price,
  });
  final WeekStats stats;
  final int budget;
  final double price;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = stats.cigTotal;
    final values = stats.cigs;
    final max = values.whereType<double>().fold<double>(
      1,
      (a, b) => b > a ? b : a,
    );

    // First and last logged days, for one plain sentence.
    String? insight;
    var good = true;
    final logged = [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) i,
    ];
    if (logged.length >= 2) {
      final a = values[logged.first]!;
      final b = values[logged.last]!;
      String dow(int i) => DateFormat('EEE').format(parseDate(stats.days[i])!);
      if (b < a) {
        insight =
            'Down from ${trimNum(a)} on ${dow(logged.first)} to ${trimNum(b)} on ${dow(logged.last)}.';
      } else if (b > a) {
        good = false;
        insight =
            'Up from ${trimNum(a)} on ${dow(logged.first)} to ${trimNum(b)} on ${dow(logged.last)}.';
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            'Cigarettes',
            trailing: total == null
                ? 'Not logged this week'
                : '${trimNum(total)} total · ≈ ${rupees(total * price)} at ${rupees(price)} each',
          ),
          const SizedBox(height: 10),
          Semantics(
            label: [
              for (var i = 0; i < values.length; i++)
                '${DateFormat('EEEE').format(parseDate(stats.days[i])!)} ${values[i] == null ? 'not logged' : trimNum(values[i])}',
            ].join(', '),
            child: ExcludeSemantics(
              child: SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < values.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              values[i] == null ? dash : trimNum(values[i]),
                              style: context.text.chip.copyWith(
                                color: values[i] == null
                                    ? c.textDim
                                    : c.textSoft,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (values[i] != null)
                              Container(
                                height: (values[i]! / max * 74).clamp(2, 74),
                                decoration: BoxDecoration(
                                  color: values[i]! <= budget
                                      ? c.accent
                                      : c.barIdle,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                    bottom: Radius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _DayLabels(days: stats.days, gap: 10),
          if (insight != null) ...[
            const SizedBox(height: 10),
            Text(
              insight,
              style: context.text.bodyS.copyWith(
                color: good ? c.accent : c.warn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayLabels extends StatelessWidget {
  const _DayLabels({required this.days, this.gap = 0});
  final List<String> days;
  final double gap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < days.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(
          child: Text(
            dow2(parseDate(days[i])!),
            textAlign: TextAlign.center,
            style: context.text.chip.copyWith(
              color: context.colors.textDim,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    ],
  );
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.stats});
  final WeekStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avg = stats.sleepAvg;
    final late = [
      for (final r in stats.sleep)
        if (r.late && r.window != null) r,
    ];
    final small = context.text.chip.copyWith(fontWeight: FontWeight.w400);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            'Sleep window',
            trailing: avg == null
                ? 'Not logged this week'
                : 'avg ≈ ${trimNum(avg)} h · 7 h+ on ${stats.nights7h} ${stats.nights7h == 1 ? 'night' : 'nights'}',
          ),
          const SizedBox(height: 8),
          for (final r in stats.sleep)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      dow2(parseDate(r.date)!),
                      style: small.copyWith(color: c.textDim),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _SleepTrack(row: r)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 38,
                    child: Text(
                      r.hours == null
                          ? dash
                          : '${r.approx ? '~' : ''}${trimNum(r.hours)}h',
                      textAlign: TextAlign.right,
                      style: small.copyWith(
                        color: r.hours == null ? c.textDim : c.textSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 34, right: 46),
            child: LayoutBuilder(
              builder: (context, box) {
                const marks = [
                  ('21:00', 0.0),
                  ('00:00', 3 / 14),
                  ('04:00', 7 / 14),
                  ('08:00', 11 / 14),
                  ('11:00', 1.0),
                ];
                return SizedBox(
                  height: 14,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final (label, f) in marks)
                        Positioned(
                          left: (box.maxWidth * f - 14).clamp(
                            -6,
                            box.maxWidth - 22,
                          ),
                          child: Text(
                            label,
                            style: small.copyWith(
                              fontSize: 10,
                              color: c.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (late.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              late
                  .map(
                    (r) =>
                        '${DateFormat('EEE').format(parseDate(r.window!.bedDate)!.subtract(Duration(days: minutesOf(r.window!.bed)! < 12 * 60 ? 1 : 0)))} night: asleep ${r.approx ? '~' : ''}${r.window!.bed}.',
                  )
                  .join(' '),
              style: context.text.bodyS.copyWith(color: c.warn),
            ),
          ],
        ],
      ),
    );
  }
}

class _SleepTrack extends StatelessWidget {
  const _SleepTrack({required this.row});
  final SleepRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bar = row.bar;
    return LayoutBuilder(
      builder: (context, box) => Container(
        height: 10,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(5),
        ),
        child: bar == null
            ? null
            : Stack(
                children: [
                  Positioned(
                    left: box.maxWidth * bar.$1,
                    width: (box.maxWidth * (bar.$2 - bar.$1)).clamp(
                      4,
                      box.maxWidth,
                    ),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: row.late ? c.warn : c.info,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.w});
  final WeightWeek w;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final swing = w.swing;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weight', style: context.text.label),
          const SizedBox(height: 6),
          NumberWithUnit(
            w.avg == null ? dash : trimNum(w.avg),
            w.avg == null ? '' : ' kg avg',
            style: context.text.statM,
            unitSize: 12,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: Semantics(
              label: w.isEmpty
                  ? 'No weights this week'
                  : 'Weight dots, ${w.values.whereType<double>().length} days, average ${trimNum(w.avg)} kilograms',
              child: CustomPaint(
                painter: _WeightPainter(
                  w: w,
                  dot: c.textSoft,
                  avgLine: c.accent,
                  axis: c.border,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            w.isEmpty
                ? 'Not logged this week.'
                : 'Axis ${trimNum(w.lo, digits: 0)}–${trimNum(w.hi, digits: 0)} kg.'
                      '${swing == null ? '' : ' Daily swing ${trimNum(swing)} kg is noise; watch the line.'}',
            style: context.text.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter({
    required this.w,
    required this.dot,
    required this.avgLine,
    required this.axis,
  });

  final WeightWeek w;
  final Color dot;
  final Color avgLine;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 4.0;
    final h = size.height - 1;
    canvas.drawLine(Offset(0, h), Offset(size.width, h), Paint()..color = axis);
    if (w.isEmpty) return;
    double y(double v) => pad + (w.hi! - v) / (w.hi! - w.lo!) * (h - 2 * pad);
    final ay = y(w.avg!);
    final dash = Paint()
      ..color = avgLine
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, ay),
        Offset((x + 3).clamp(0, size.width), ay),
        dash,
      );
    }
    final n = w.values.length;
    final p = Paint()..color = dot;
    for (var i = 0; i < n; i++) {
      final v = w.values[i];
      if (v == null) continue; // a gap, never 0
      final x = 3.5 + (size.width - 7) * (n == 1 ? 0.5 : i / (n - 1));
      canvas.drawCircle(Offset(x, y(v)), 3.5, p);
    }
  }

  @override
  bool shouldRepaint(_WeightPainter old) =>
      old.w != w ||
      old.dot != dot ||
      old.avgLine != avgLine ||
      old.axis != axis;
}

class _NotLoggedCard extends StatelessWidget {
  const _NotLoggedCard({required this.stats});
  final WeekStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = stats.days.length;
    Widget row(String label, String value, bool none) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.text.bodyS.copyWith(color: c.textMuted),
            ),
          ),
          Text(
            value,
            style: context.text.bodyS.copyWith(color: none ? c.warn : c.text),
          ),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Not logged', style: context.text.label),
          const SizedBox(height: 6),
          for (final e in stats.notLogged.entries)
            row(e.key, '${e.value}/$n', e.value == 0),
          row(
            'Study sessions',
            '${stats.studySessions}',
            stats.studySessions == 0,
          ),
        ],
      ),
    );
  }
}

class _FlagsCard extends StatelessWidget {
  const _FlagsCard({required this.state});
  final WeekState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      color: c.warnWell,
      borderColor: c.warnBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sheet data to check',
            style: context.text.label.copyWith(color: c.warn),
          ),
          const SizedBox(height: 6),
          for (final f in state.flags)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${dayShort(parseDate(f.date)!)}: ${f.text}',
                style: context.text.bodyS,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Old tabs are read-only here; numbers above use the column value.',
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}
