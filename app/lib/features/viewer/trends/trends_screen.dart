import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../domain/viewer/insights.dart';
import '../../../domain/viewer/metrics.dart';
import '../viewer_cubit.dart';
import '../widgets/charts.dart';
import '../widgets/viewer_page.dart';

/// Trends tab: Smoking | Sleep & body.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key, this.sleep = false});

  /// Open on "Sleep & body" (`/trends?seg=sleep`).
  final bool sleep;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  late int _seg = widget.sleep ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ViewerCubit>().state;
    if (!s.loaded) return const SizedBox.shrink();
    final m = s.week!;
    return ViewerPage(
      children: [
        TitleRow(title: 'Trends', trailing: rangeLabel(m.days)),
        _Segmented(
          labels: const ['Smoking', 'Sleep & body'],
          index: _seg,
          onChanged: (i) => setState(() => _seg = i),
        ),
        if (_seg == 0)
          ..._smoking(context, m, s.settings.cigPrice)
        else
          ..._sleep(context, m),
      ],
    );
  }

  List<Widget> _smoking(BuildContext context, WeekMetrics m, double price) {
    final total = m.cigTotal;
    if (total == null) {
      return [
        const VCard(child: NotLogged('No cigarettes logged in these 7 days.')),
      ];
    }
    final letters = dayLetters(m.days);
    final dows = [for (final d in m.days) dow3(parseDate(d)!)];
    int? hi;
    int? lo;
    for (var i = 0; i < m.days.length; i++) {
      final v = m.cigs[i];
      if (v == null) continue;
      if (hi == null || v > m.cigs[hi]!) hi = i;
      if (lo == null || v < m.cigs[lo]!) lo = i;
    }
    final timed = m.timedTotal;
    final peak = peakSentence(m);
    final perWeek = total * price;
    final perMonth = (m.cigAvg! * 30 * price / 50).round() * 50;
    final tobacco = m.tobaccoSpend;
    return [
      VCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cigarettes this week',
                        style: small(context, size: 12),
                      ),
                      Text(trimNum(total), style: context.text.statXl),
                    ],
                  ),
                ),
                Text(
                  '${trimNum(m.cigAvg)} a day\nhigh ${trimNum(m.cigs[hi!])} ${dows[hi]} · low ${trimNum(m.cigs[lo!])} ${dows[lo]}',
                  textAlign: TextAlign.right,
                  style: small(context, size: 12).copyWith(height: 1.45),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BarsWithAverage(
              values: m.cigs,
              labels: letters,
              color: context.series.smoke,
              format: trimNum,
              avg: m.cigAvg,
              avgLabel: 'avg ${trimNum(m.cigAvg)}',
            ),
          ],
        ),
      ),
      VCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardHead(
              'When in the day',
              note: '${trimNum(timed)} timed of ${trimNum(total)}',
            ),
            const SizedBox(height: 6),
            if (timed == 0)
              const NotLogged(
                'No cigarette has a time yet, so there is no time-of-day pattern.',
              )
            else ...[
              HourHistogram(hours: m.hours),
              const SizedBox(height: 6),
              if (peak != null) Sentence(peak.lead, peak.rest),
            ],
          ],
        ),
      ),
      Pair(
        VCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Smoked with a tea', style: small(context, size: 12)),
              const SizedBox(height: 6),
              Text(
                timed == 0 ? dash : '${trimNum(m.paired)} of ${trimNum(timed)}',
                style: context.text.statM,
              ),
              const SizedBox(height: 6),
              _Meter(
                share: timed == 0 ? 0 : m.paired / timed,
                color: context.series.smoke,
              ),
              const SizedBox(height: 6),
              Text(
                timed == 0
                    ? 'needs times'
                    : '${(m.paired / timed * 100).round()}% of timed cigarettes',
                style: small(context),
              ),
            ],
          ),
        ),
        _OfficeCard(m: m),
      ),
      VCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'What it costs, est.',
                    style: small(context, size: 12),
                  ),
                ),
                Text(
                  '≈ ${rupees((perWeek / 50).round() * 50)} / week',
                  style: context.text.statS,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${trimNum(total)} × ~${rupees(price)}. About ${rupees(perMonth)} a month at this pace. '
              '${tobacco == null ? 'Nothing is logged as tobacco spend.' : (tobacco < perWeek - 1 ? 'Only ${rupees(tobacco)} is logged as tobacco; the rest sits inside delivery orders or isn\'t logged.' : '${rupees(tobacco)} is logged as tobacco.')}',
              style: small(context, size: 12).copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sleep(BuildContext context, WeekMetrics m) {
    final b = m.bedtime;
    final sent = sleepSentence(m);
    final w = m.weight;
    final kg = w.values.whereType<double>().toList();
    final stepsHave = m.steps.whereType<double>().toList();
    final dows = [for (final d in m.days) dow3(parseDate(d)!)];
    String stepsNote() {
      final missing = [
        for (var i = 0; i < m.days.length; i++)
          if (m.steps[i] == null) dows[i],
      ];
      var lowI = -1;
      for (var i = 0; i < m.days.length; i++) {
        final v = m.steps[i];
        if (v != null && (lowI < 0 || v < m.steps[lowI]!)) lowI = i;
      }
      final low = lowI < 0
          ? ''
          : '${dows[lowI]} ${rupees(m.steps[lowI]).substring(1)}, the low.';
      if (missing.isEmpty) return low;
      return '${joinAnd(missing)} not logged. $low'.trim();
    }

    return [
      VCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CardHead('When you slept', note: 'band = your usual bedtime'),
            const SizedBox(height: 6),
            if (m.sleepDays == 0)
              const NotLogged('No nights logged in these 7 days.')
            else ...[
              SleepWindows(
                days: m.days,
                nights: m.nights,
                hours: m.sleep,
                bedtime: b,
              ),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.colors.divider),
                  ),
                ),
                child: Row(
                  children: [
                    _Stat('Average', '${trimNum(m.sleepAvg)} h'),
                    _Stat(
                      'Bedtime spread',
                      b == null || b.count < 2
                          ? dash
                          : '±${duration(b.sdMin.round())}',
                    ),
                    _Stat('Nights 7h+', '${m.longNights} of ${m.sleepDays}'),
                  ],
                ),
              ),
              if (sent != null) ...[
                const SizedBox(height: 6),
                Sentence(sent.lead, sent.rest),
              ],
            ],
          ],
        ),
      ),
      Pair(
        VCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Weight', style: small(context, size: 12)),
              const SizedBox(height: 6),
              _ValueUnit(
                w.avg == null ? dash : trimNum(w.avg),
                w.avg == null ? '' : ' kg avg',
              ),
              const SizedBox(height: 6),
              WeightDots(week: w),
              const SizedBox(height: 6),
              Text(
                w.avg == null
                    ? 'Not weighed these 7 days.'
                    : 'Axis ${trimNum(w.lo)}–${trimNum(w.hi)} kg. '
                          '${kg.length < 2 ? '' : '${trimNum(kg.reduce(math.min), digits: 2)} → ${trimNum(kg.reduce(math.max), digits: 2)}: '}'
                          'watch the average, not single days.',
                style: small(context),
              ),
            ],
          ),
        ),
        VCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Steps', style: small(context, size: 12)),
              const SizedBox(height: 6),
              _ValueUnit(
                m.stepsAvg == null ? dash : '${trimNum(m.stepsAvg! / 1000)}k',
                m.stepsAvg == null ? '' : ' avg',
              ),
              const SizedBox(height: 6),
              MiniBars(values: m.steps, color: context.series.sleep),
              const SizedBox(height: 6),
              Text(
                stepsHave.isEmpty ? 'Not logged these 7 days.' : stepsNote(),
                style: small(context),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                label: labels[i],
                child: ExcludeSemantics(
                  child: Material(
                    color: i == index ? c.border : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onChanged(i),
                      child: SizedBox(
                        height: 40,
                        child: Center(
                          child: Text(
                            labels[i],
                            style: context.text.caption.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: i == index ? c.text : c.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.share, required this.color});
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Container(
      height: 8,
      color: context.series.missing,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: share.clamp(0, 1),
        child: Container(color: color),
      ),
    ),
  );
}

class _OfficeCard extends StatelessWidget {
  const _OfficeCard({required this.m});
  final WeekMetrics m;

  @override
  Widget build(BuildContext context) {
    final o = m.office;
    final f = m.off;
    final max = math.max(o.avg ?? 0, f.avg ?? 0);
    Widget row(String name, double? v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(name, style: small(context, size: 12)),
          ),
          Expanded(
            child: v == null
                ? Text(dash, style: small(context, dim: true))
                : FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: max == 0
                        ? 0.02
                        : (v / max * 0.85).clamp(0.02, 1),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.series.smoke,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
          ),
          if (v != null)
            Text(
              trimNum(v),
              style: context.text.caption.copyWith(
                fontSize: 12,
                color: context.colors.text,
              ),
            ),
        ],
      ),
    );
    return VCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Office vs off days', style: small(context, size: 12)),
          const SizedBox(height: 6),
          row('Office', o.avg),
          row('Off', f.avg),
          Text('a day · ${o.days} vs ${f.days} days', style: small(context)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: small(context)),
        Text(value, style: context.text.statS),
      ],
    ),
  );
}

class _ValueUnit extends StatelessWidget {
  const _ValueUnit(this.value, this.unit);
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: value,
      style: context.text.statM,
      children: [
        TextSpan(
          text: unit,
          style: context.text.caption.copyWith(color: context.colors.textDim),
        ),
      ],
    ),
  );
}
