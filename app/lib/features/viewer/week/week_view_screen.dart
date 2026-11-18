import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../domain/event.dart';
import '../../../domain/viewer/day_view.dart';
import '../../../domain/viewer/insights.dart';
import '../viewer_cubit.dart';
import '../widgets/charts.dart';
import '../widgets/viewer_page.dart';

/// Week tab: "Do my days repeat?" Seven ribbons stacked.
class WeekViewScreen extends StatelessWidget {
  const WeekViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ViewerCubit>().state;
    if (!s.loaded) return const SizedBox.shrink();
    final m = s.week!;
    final takeaways = weekTakeaways(m);
    return ViewerPage(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${rangeLabel(m.days)} · ${m.daysLogged} of ${m.days.length} days logged',
              style: small(context, size: 13),
            ),
            const SizedBox(height: 2),
            Text('Week', style: titleStyle(context)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: MiniStat(
                'Cigarettes',
                trimNum(m.cigTotal),
                m.cigAvg == null ? 'not logged' : '${trimNum(m.cigAvg)} a day',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniStat(
                'Sleep',
                m.sleepAvg == null ? dash : '${trimNum(m.sleepAvg)} h',
                m.sleepAvg == null
                    ? 'not logged'
                    : 'avg · ${m.longNights} ${m.longNights == 1 ? 'night' : 'nights'} 7h+',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniStat(
                'Day-to-day',
                rupees(m.dayToDayTotal),
                m.burnAvg == null ? 'not logged' : '${rupees(m.burnAvg)} a day',
              ),
            ),
          ],
        ),
        VCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardHead('Every day, side by side', note: 'cigs · ₹'),
              const SizedBox(height: 6),
              _AxisRow(),
              for (var i = 0; i < m.days.length; i++)
                _WeekRow(
                  date: m.days[i],
                  events: s.events,
                  cigs: m.cigs[i],
                  timed: m.cigsTimed[i],
                  spend: m.dayToDay[i],
                  onTap: () {
                    context.read<ViewerCubit>().showDay(m.days[i]);
                    context.go('/day');
                  },
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  LegendItem(
                    Swatch(context.series.sleep, width: 10, height: 6),
                    'Sleep',
                  ),
                  LegendItem(
                    Swatch(context.series.bus, width: 10, height: 6),
                    'Bus',
                  ),
                  LegendItem(
                    Swatch(
                      context.series.smoke,
                      width: 4,
                      height: 10,
                      radius: 1,
                    ),
                    'Cigarettes (timed)',
                  ),
                  LegendItem(
                    Swatch(context.series.food, width: 6, height: 6, radius: 3),
                    'Food & tea',
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final t in takeaways)
          VCard(
            radius: 14,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Sentence(t.lead, t.rest),
          ),
      ],
    );
  }
}

const _labelW = 44.0;
const _rightW = 56.0;

class _AxisRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: _labelW, right: _rightW),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final t in ['00', '06', '12', '18', '24'])
          Text(t, style: small(context, dim: true, size: 10)),
      ],
    ),
  );
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.date,
    required this.events,
    required this.cigs,
    required this.timed,
    required this.spend,
    required this.onTap,
  });

  final String date;
  final List<Event> events;
  final double? cigs;
  final double? timed;
  final double? spend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = parseDate(date)!;
    final marks = dayView(events, date).marks;
    final untimed = (cigs ?? 0) - (timed ?? 0);
    final c = context.colors;
    return Semantics(
      button: true,
      label:
          '${dayHeader(d)}: ${cigs == null ? 'no cigarettes logged' : '${trimNum(cigs)} cigarettes'}'
          '${untimed > 0 ? ', ${trimNum(untimed)} without a time' : ''}, '
          '${spend == null ? 'no spend logged' : '${rupees(spend)} day-to-day'}. Open this day',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.divider)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _labelW,
                  child: Text.rich(
                    TextSpan(
                      text: '${dow3(d)}\n',
                      style: small(
                        context,
                        size: 12,
                      ).copyWith(color: c.textSoft, height: 1.15),
                      children: [
                        TextSpan(
                          text: DateFormat('d MMM').format(d),
                          style: TextStyle(color: c.textDim),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MiniRibbonPainter(
                              marks,
                              context.series,
                              c.track,
                            ),
                          ),
                        ),
                        if (untimed > 0)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CustomPaint(
                              foregroundPainter: DashedRectPainter(
                                context.series.smoke,
                                4,
                              ),
                              child: Container(
                                color: c.surface,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  '+${trimNum(untimed)} no time',
                                  style: small(context, size: 9).copyWith(
                                    color: context.series.untimedText,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _rightW,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final t in [
                        Text(
                          cigs == null ? dash : trimNum(cigs),
                          style: context.text.statS.copyWith(
                            fontSize: 14,
                            color: cigs == null ? c.textDim : c.text,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          spend == null ? dash : rupees(spend),
                          style: small(context, dim: true, size: 10),
                        ),
                      ])
                        FittedBox(fit: BoxFit.scaleDown, child: t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact ribbon: sleep on top, bus in the middle, smoke ticks from the
/// bottom, food dots. Not interactive (the row opens the Day tab).
class _MiniRibbonPainter extends CustomPainter {
  _MiniRibbonPainter(this.marks, this.s, this.mid);
  final List<RibbonMark> marks;
  final SeriesColors s;
  final Color mid;

  @override
  void paint(Canvas canvas, Size size) {
    double x(num m) => m / 1440 * size.width;
    final p = Paint();
    canvas.drawRect(Rect.fromLTWH(0, 14, size.width, 1), p..color = mid);
    for (final m in marks) {
      switch (m.lane) {
        case Lane.sleep:
          canvas.drawRRect(
            RRect.fromLTRBR(
              x(m.start),
              2,
              math.max(x(m.end!), x(m.start) + 3),
              10,
              const Radius.circular(3),
            ),
            p..color = s.sleep,
          );
        case Lane.bus:
          canvas.drawRRect(
            RRect.fromLTRBR(
              x(m.start),
              11,
              math.max(x(m.end!), x(m.start) + 4),
              18,
              const Radius.circular(3),
            ),
            p..color = s.bus,
          );
        case Lane.smoke:
          final h = math.min(6 + m.size * 4, size.height - 2);
          canvas.drawRRect(
            RRect.fromLTRBAndCorners(
              x(m.start) - 2,
              size.height - h,
              x(m.start) + 2,
              size.height,
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2),
            ),
            p..color = s.smoke,
          );
        case Lane.food:
          canvas.drawCircle(Offset(x(m.start), 23), 3, p..color = s.food);
        case Lane.money:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(_MiniRibbonPainter old) => old.marks != marks;
}
