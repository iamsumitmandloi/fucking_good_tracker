import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/sync_status.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/formatters.dart';
import '../../domain/derivations/burn.dart';
import '../../domain/event.dart';
import '../../domain/quicklog/build_events.dart';
import '../week/week_screen.dart' show rangeLabel, refreshWithLegacy;
import 'money_cubit.dart';

class MoneyScreen extends StatelessWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => MoneyCubit(
        events: c.read(),
        legacy: c.read(),
        settings: c.read(),
        clock: c.read(),
      ),
      child: const _MoneyView(),
    );
  }
}

class _MoneyView extends StatelessWidget {
  const _MoneyView();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MoneyCubit>().state;
    final d = context.dims;
    final b = s.burn;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => refreshWithLegacy(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(d.screenH, d.screenTop, d.screenH, 24),
          children: [
            const SyncBanner(),
            ScreenHeader(
              caption: b == null
                  ? ''
                  : '${rangeLabel(s.days)} · ${b.entries} ${b.entries == 1 ? 'entry' : 'entries'}',
              title: 'Money',
            ),
            SizedBox(height: d.gapL),
            if (b != null) ...[
              _BurnCard(b: b),
              SizedBox(height: d.gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _PayLaterCard(b: b)),
                    SizedBox(width: d.gap),
                    Expanded(child: _SmokingCard(state: s)),
                  ],
                ),
              ),
              SizedBox(height: d.gap),
              _TodayList(state: s),
            ],
          ],
        ),
      ),
    );
  }
}

class _BurnCard extends StatelessWidget {
  const _BurnCard({required this.b});
  final Burn b;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = [
      (b.delivery, c.warn, null as Color?),
      (b.other, c.info, null as Color?),
      (b.oneOffs, c.borderStrong, const Color(0xFF6A727C)),
    ];
    final pct = [for (final p in parts) b.share(p.$1)];
    String percent(double? f) => f == null ? dash : '${(f * 100).round()}%';
    final oneOffName = b.oneOffLabels.isEmpty
        ? 'One-offs and bills'
        : 'One-offs: ${b.oneOffLabels.take(2).join(', ')}${b.oneOffLabels.length > 2 ? '…' : ''}';
    final deliveryShare = b.deliveryShareOfDayToDay;
    return AppCard(
      padding: EdgeInsets.all(context.dims.cardPadL),
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
                    Text('Day-to-day burn', style: context.text.caption),
                    const SizedBox(height: 2),
                    NumberWithUnit(
                      rupees(b.perDay),
                      b.perDay == null ? '' : '/day',
                      style: context.text.statXl,
                    ),
                  ],
                ),
              ),
              Text(
                b.total == null
                    ? 'Nothing spent\nthis week'
                    : '${rupees(b.dayToDay)} this week\n${rupees(b.total)} incl. one-offs',
                textAlign: TextAlign.right,
                style: context.text.caption.copyWith(height: 1.4),
              ),
            ],
          ),
          if (b.total != null && b.total! > 0) ...[
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Delivery apps ${percent(pct[0])}, everything else ${percent(pct[1])}, one-offs ${percent(pct[2])} of the week',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (var i = 0; i < parts.length; i++)
                        if ((pct[i] ?? 0) > 0) ...[
                          if (i > 0 &&
                              parts
                                  .take(i)
                                  .any((p) => (b.share(p.$1) ?? 0) > 0))
                            const SizedBox(width: 2),
                          Expanded(
                            flex: (pct[i]! * 1000).round().clamp(1, 1000),
                            child: ColoredBox(color: parts[i].$2),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Legend(
              color: parts[0].$2,
              label:
                  'Delivery apps · ${b.deliveryCount} ${b.deliveryCount == 1 ? 'order' : 'orders'}',
              value: b.delivery,
            ),
            _Legend(
              color: parts[1].$2,
              label: 'Canteen, tea, singles, street food',
              value: b.other,
            ),
            _Legend(
              color: parts[2].$2,
              border: parts[2].$3,
              label: oneOffName,
              value: b.oneOffs,
            ),
            if (deliveryShare != null && b.deliveryCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Delivery orders are ${percent(deliveryShare)} of day-to-day spend.',
                style: context.text.bodyS.copyWith(
                  color: deliveryShare >= 0.4 ? c.warn : c.textSoft,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
    this.border,
  });
  final Color color;
  final Color? border;
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: border == null ? null : Border.all(color: border!),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        Text(rupees(value), style: context.text.label),
      ],
    ),
  );
}

class _PayLaterCard extends StatelessWidget {
  const _PayLaterCard({required this.b});
  final Burn b;

  @override
  Widget build(BuildContext context) => StatCard(
    label: 'Pay later · LazyPay',
    radius: context.dims.rCard,
    padding: context.dims.cardPad,
    value: Text(rupees(b.payLater), style: context.text.statM),
    caption: b.payLaterCount == 0
        ? 'No pay-later charges this week.'
        : '${b.payLaterCount} ${b.payLaterCount == 1 ? 'charge' : 'charges'} this week.',
  );
}

class _SmokingCard extends StatelessWidget {
  const _SmokingCard({required this.state});
  final MoneyState state;

  @override
  Widget build(BuildContext context) {
    final m = state.smokingPerMonth;
    return StatCard(
      label: 'Smoking, est.',
      radius: context.dims.rCard,
      padding: context.dims.cardPad,
      value: NumberWithUnit(
        m == null ? dash : '≈ ${rupeesCompact(m)}',
        m == null ? '' : '/mo',
        style: context.text.statM,
        unitSize: 13,
      ),
      caption: m == null
          ? 'No cigarettes logged this week.'
          : "At this week's ${trimNum(state.cigsWeek)}, ${rupees(state.settings.cigPrice)} each.",
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({required this.state});
  final MoneyState state;

  String _title(Event e) {
    final l = e.label?.trim();
    if (l != null && l.isNotEmpty) return l;
    return logLine(e);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = state.todayEntries;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'Today · ${rupees(state.todaySpend)}',
              style: context.text.caption,
            ),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Nothing spent today.', style: context.text.bodyS),
            )
          else
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.divider),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title(list[i]),
                              style: context.text.body.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              [
                                ?list[i].time,
                                if (list[i].source == 'lazypay') 'pay later',
                                if (list[i].approx) 'approx',
                              ].join(' · '),
                              style: context.text.caption.copyWith(
                                color: c.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      rupees(list[i].amountInr, decimals: true),
                      style: context.text.label,
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
