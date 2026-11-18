import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_sync.dart';
import '../../../app/sync_status.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../domain/viewer/metrics.dart';

/// Scrollable tab body: offline banner on top, pull-to-refresh (Events
/// only; the outbox is never sent while logging is off), 16 px gutters.
class ViewerPage extends StatelessWidget {
  const ViewerPage({super.key, required this.children, this.top = 24});

  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: context.colors.accent,
        backgroundColor: context.colors.surface,
        onRefresh: () => context.read<AppSync>().syncNow(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, top, 16, 24),
          children: [
            const SyncBanner(),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// "Wed 11 – Tue 17 Nov".
String rangeLabel(List<String> days) {
  final a = parseDate(days.first)!;
  final b = parseDate(days.last)!;
  final left = a.month == b.month ? dayShort(a) : dayHeader(a);
  return '$left – ${dayHeader(b)}';
}

/// First letter of each weekday: "W T F S S M T".
List<String> dayLetters(List<String> days) => [
  for (final d in days) dow2(parseDate(d)!).substring(0, 1),
];

/// Page title row: big title left, small caption right (Trends, Money).
class TitleRow extends StatelessWidget {
  const TitleRow({super.key, required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(title, style: titleStyle(context))),
        if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(trailing!, style: context.text.caption),
          ),
      ],
    );
  }
}

TextStyle titleStyle(BuildContext context) =>
    context.text.h1.copyWith(fontSize: 30, letterSpacing: -0.6);

/// Card with the v2 radius and padding.
class VCard extends StatelessWidget {
  const VCard({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.onTap,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(radius);
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(onTap: onTap, borderRadius: r, child: body);
    }
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

/// Card header: title left (14/600), small dim note right.
class CardHead extends StatelessWidget {
  const CardHead(this.title, {super.key, this.note});
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(title, style: context.text.label.copyWith(fontSize: 14)),
        ),
        if (note != null) Text(note!, style: small(context, dim: true)),
      ],
    );
  }
}

/// 11 px caption, muted or dim.
TextStyle small(BuildContext context, {bool dim = false, double size = 11}) =>
    context.text.caption.copyWith(
      fontSize: size,
      color: dim ? context.colors.textDim : context.colors.textMuted,
      height: 1.35,
    );

/// "**Lead.** muted rest" at 13 px.
class Sentence extends StatelessWidget {
  const Sentence(this.lead, this.rest, {super.key});
  final String lead;
  final String rest;

  @override
  Widget build(BuildContext context) {
    final base = context.text.caption.copyWith(
      fontSize: 13,
      height: 1.45,
      color: context.colors.text,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: lead,
            style: base.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: rest.startsWith(',') || rest.startsWith(' ')
                ? rest
                : ' $rest',
            style: base.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Small square colour key. Identity lives here, never in the text.
class Swatch extends StatelessWidget {
  const Swatch(
    this.color, {
    super.key,
    this.width = 8,
    this.height = 8,
    this.radius = 2,
  });
  final Color color;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Day tab KPI: swatch + label, big value, comparison line.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    required this.delta,
  });
  final Color color;
  final String label;
  final String value;
  final String delta;

  @override
  Widget build(BuildContext context) {
    return VCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Swatch(color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: small(context, size: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value, style: context.text.statM.copyWith(fontSize: 24)),
          const SizedBox(height: 2),
          Text(
            delta,
            style: small(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Week tab summary tile: label, value, caption.
class MiniStat extends StatelessWidget {
  const MiniStat(this.label, this.value, this.caption, {super.key});
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return VCard(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: small(context)),
          Text(value, style: context.text.statS.copyWith(fontSize: 20)),
          Text(
            caption,
            style: small(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Two equal columns with an 8 px gap.
class Pair extends StatelessWidget {
  const Pair(this.left, this.right, {super.key});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    ),
  );
}

/// Shown on a chart card when the metric has never been logged.
class NotLogged extends StatelessWidget {
  const NotLogged(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, style: small(context, size: 12)),
  );
}

/// Day-to-day amounts on bars: 1654 → "1.7k", 225 → "225".
String kAmount(double v) =>
    v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}';

/// Number of logged days in a series.
int loggedDays(List<Object?> xs) => xs.where((x) => x != null).length;

/// The week's metrics or an empty set while drift loads.
WeekMetrics emptyWeek(String today) => weekMetrics(const [], daysEnding(today));
