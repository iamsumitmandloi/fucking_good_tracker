import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../domain/viewer/insights.dart';
import '../../../domain/viewer/metrics.dart';
import '../../../domain/viewer/viewer_events.dart';
import '../viewer_cubit.dart';
import '../widgets/charts.dart';
import '../widgets/viewer_page.dart';

/// Money tab: day-to-day burn, where it went, pay later.
class MoneyViewScreen extends StatelessWidget {
  const MoneyViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ViewerCubit>().state;
    if (!s.loaded) return const SizedBox.shrink();
    final m = s.week!;
    final dows = [for (final d in m.days) dow3(parseDate(d)!)];
    final oneOffDays = {for (final o in m.oneOffs) o.date};
    final letters = dayLetters(m.days);
    final total = m.dayToDayTotal;
    return ViewerPage(
      children: [
        TitleRow(title: 'Money', trailing: rangeLabel(m.days)),
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
                          'Day-to-day burn',
                          style: small(context, size: 12),
                        ),
                        m.burnAvg == null
                            ? Text(dash, style: context.text.statXl)
                            : NumberWithUnit(
                                rupees(m.burnAvg),
                                '/day',
                                style: context.text.statXl,
                                unitSize: 15,
                              ),
                      ],
                    ),
                  ),
                  Text(
                    [
                      total == null
                          ? 'Nothing logged'
                          : '${rupees(total)} this week',
                      if (m.oneOffTotal != null)
                        '+ ${rupees(m.oneOffTotal)} one-offs',
                    ].join('\n'),
                    textAlign: TextAlign.right,
                    style: small(context, size: 12).copyWith(height: 1.45),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (total == null)
                const NotLogged('No spend rows in these 7 days.')
              else
                BarsWithAverage(
                  values: m.dayToDay,
                  labels: [
                    for (var i = 0; i < m.days.length; i++)
                      '${letters[i]}${oneOffDays.contains(m.days[i]) ? '◆' : ''}',
                  ],
                  color: context.series.money,
                  format: kAmount,
                  avg: m.burnAvg,
                  avgLabel: 'avg ${rupees(m.burnAvg)}',
                  height: 122,
                ),
              if (m.oneOffs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '◆ one-offs not in the bars: ${[for (final o in m.oneOffs) '${dows[m.days.indexOf(o.date)]} ${o.text.isEmpty ? SpendCat.name(o.category) : o.text} ${rupees(o.amount)}'].join(' · ')}',
                  style: small(context),
                ),
              ],
            ],
          ),
        ),
        VCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardHead('Where it went', note: 'day-to-day only'),
              const SizedBox(height: 8),
              if (m.categories.isEmpty || total == null || total == 0)
                const NotLogged('Nothing to split yet.')
              else ...[
                RankedBars(
                  items: m.categories,
                  total: total,
                  color: context.series.money,
                ),
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: context.colors.divider),
                    ),
                  ),
                  child: _topSentence(m.categories.first, total),
                ),
              ],
            ],
          ),
        ),
        VCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay later · LazyPay',
                      style: small(context, size: 12),
                    ),
                    Text(
                      m.payLater == null
                          ? 'No pay-later charges this week'
                          : [
                              if (m.payLaterMerchants.isNotEmpty)
                                m.payLaterMerchants.join(', '),
                              '${m.payLaterCount} ${m.payLaterCount == 1 ? 'charge' : 'charges'}',
                            ].join(' · '),
                      style: small(context, dim: true),
                    ),
                  ],
                ),
              ),
              Text(
                rupees(m.payLater),
                style: context.text.statS.copyWith(fontSize: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topSentence(CategoryTotal top, double total) {
    final pct = (top.amount / total * 100).round();
    final verb = top.name.endsWith('s') ? 'are' : 'is';
    final parts = <String>[
      if (top.orders > 1)
        '${top.orders} ${top.category == SpendCat.quickCommerce ? 'orders' : 'entries'}'
            '${top.weekend > 0 ? ', ${rupees(top.weekend)} of them on Sat–Sun' : ''}.',
      if (top.category == SpendCat.quickCommerce)
        "The contents of most orders aren't itemised.",
    ];
    return Sentence('${top.name} $verb $pct% of it.', parts.join(' '));
  }
}

/// Insights tab: pattern cards with confidence, plus what's logged.
class InsightsBody extends StatelessWidget {
  const InsightsBody({super.key, required this.m, required this.daysWithData});
  final WeekMetrics m;
  final int daysWithData;

  @override
  Widget build(BuildContext context) {
    final cards = insightCards(m);
    return ViewerPage(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Insights', style: titleStyle(context)),
            const SizedBox(height: 2),
            Text(
              daysWithData >= 21
                  ? '$daysWithData days in.'
                  : '$daysWithData ${daysWithData == 1 ? 'day' : 'days'} in. Patterns firm up after about 3 weeks.',
              style: small(context, size: 12),
            ),
          ],
        ),
        if (cards.isEmpty)
          const VCard(
            radius: 16,
            child: NotLogged('Not enough logged this week for a pattern yet.'),
          ),
        for (final c in cards)
          VCard(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.title,
                        style: context.text.label.copyWith(
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConfidenceDots(c.confidence),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  c.body,
                  style: small(context, size: 12).copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        VCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "What's logged",
                      style: context.text.label.copyWith(fontSize: 14),
                    ),
                  ),
                  const _Key(Coverage.logged, 'logged'),
                  const SizedBox(width: 8),
                  const _Key(Coverage.partial, 'part'),
                  const SizedBox(width: 8),
                  const _Key(Coverage.missing, 'missing'),
                ],
              ),
              const SizedBox(height: 6),
              CoverageGrid(rows: m.coverage, days: m.days),
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.colors.divider),
                  ),
                ),
                child: Text(
                  'Tell the logging agent: a time on every entry, plus water, breakfast protein and study minutes.',
                  style: small(context, size: 12).copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.state, this.label);
  final Coverage state;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CoverageCell(state, width: 8, height: 8),
      const SizedBox(width: 3),
      Text(label, style: small(context, dim: true, size: 10)),
    ],
  );
}
