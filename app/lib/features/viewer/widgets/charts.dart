import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../domain/derivations/weight.dart';
import '../../../domain/viewer/metrics.dart';
import '../../../domain/viewer/nights.dart';
import 'viewer_page.dart';

TextPainter _tp(String s, TextStyle st) => TextPainter(
  text: TextSpan(text: s, style: st),
  textDirection: TextDirection.ltr,
)..layout();

void _dashedH(Canvas c, double x0, double x1, double y, Paint p) {
  for (var x = x0; x < x1; x += 7) {
    c.drawLine(Offset(x, y), Offset(math.min(x + 4, x1), y), p);
  }
}

/// Legend entry: a swatch in the mark's shape, then the name.
class LegendItem extends StatelessWidget {
  const LegendItem(this.swatch, this.label, {super.key});
  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: 5),
      Text(label, style: small(context)),
    ],
  );
}

/// Daily bars with a value label on each bar and a dashed average line
/// labelled at the right. Missing days get a dim 2 px stub and "—".
class BarsWithAverage extends StatelessWidget {
  const BarsWithAverage({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    required this.format,
    this.avg,
    this.avgLabel,
    this.height = 118,
  });

  final List<double?> values;
  final List<String> labels;
  final Color color;
  final String Function(double) format;
  final double? avg;
  final String? avgLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final semantic = [
      for (var i = 0; i < values.length; i++)
        '${labels[i]} ${values[i] == null ? 'not logged' : format(values[i]!)}',
    ].join(', ');
    return Semantics(
      label: '$semantic${avgLabel == null ? '' : '. $avgLabel'}',
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size(double.infinity, height),
          painter: _BarsPainter(
            values: values,
            labels: labels,
            color: color,
            format: format,
            avg: avg,
            avgLabel: avgLabel,
            colors: context.colors,
            missing: context.series.missing,
            valueStyle: context.text.caption.copyWith(
              fontSize: 11,
              color: context.colors.textSoft,
            ),
            axisStyle: context.text.caption.copyWith(
              fontSize: 11,
              color: context.colors.textDim,
            ),
            avgStyle: context.text.caption.copyWith(fontSize: 10),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.format,
    required this.avg,
    required this.avgLabel,
    required this.colors,
    required this.missing,
    required this.valueStyle,
    required this.axisStyle,
    required this.avgStyle,
  });

  final List<double?> values;
  final List<String> labels;
  final Color color;
  final String Function(double) format;
  final double? avg;
  final String? avgLabel;
  final AppColors colors;
  final Color missing;
  final TextStyle valueStyle;
  final TextStyle axisStyle;
  final TextStyle avgStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const axisH = 18.0;
    const labelH = 15.0;
    final base = size.height - axisH;
    final maxBar = base - labelH - 4;
    final max = values.whereType<double>().fold<double>(0, math.max);
    final n = values.length;
    const gap = 10.0;
    final avgY0 = avg != null && max > 0;
    // The avg tag lives in its own right-hand gutter, so it never sits on
    // a bar or a value label.
    final tag = avgY0 && avgLabel != null ? _tp(avgLabel!, avgStyle) : null;
    final plotW = size.width - (tag == null ? 0 : tag.width + 6);
    final colW = (plotW - gap * (n - 1)) / n;
    final barW = math.min(26.0, colW);
    double h(double v) => max <= 0 ? 0 : v / max * maxBar;
    final fill = Paint();
    final avgY = avgY0 ? base - h(avg!) : null;

    // 1. The average line goes under everything else.
    if (avgY != null) {
      _dashedH(
        canvas,
        0,
        plotW,
        avgY,
        Paint()
          ..color = colors.textMuted
          ..strokeWidth = 1.5,
      );
    }

    // 2. Bars, day labels; value labels collected for step 3.
    final labelRects = <(Rect, TextPainter)>[];
    for (var i = 0; i < n; i++) {
      final cx = i * (colW + gap) + colW / 2;
      final v = values[i];
      final label = _tp(labels[i], axisStyle);
      label.paint(canvas, Offset(cx - label.width / 2, base + 4));
      if (v == null) {
        canvas.drawRect(
          Rect.fromLTWH(cx - barW / 2, base - 2, barW, 2),
          fill..color = missing,
        );
        final t = _tp(dash, valueStyle.copyWith(color: colors.textDim));
        labelRects.add((
          Rect.fromLTWH(
            cx - t.width / 2,
            base - 4 - t.height,
            t.width,
            t.height,
          ),
          t,
        ));
        continue;
      }
      final bh = math.max(h(v), v > 0 ? 2.0 : 0.0);
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          cx - barW / 2,
          base - bh,
          cx + barW / 2,
          base,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        fill..color = color,
      );
      final t = _tp(format(v), valueStyle);
      labelRects.add((
        Rect.fromLTWH(
          cx - t.width / 2,
          base - bh - 3 - t.height,
          t.width,
          t.height,
        ),
        t,
      ));
    }

    // 3. Value labels on a surface backing, so the line never cuts them.
    for (final (r, t) in labelRects) {
      canvas.drawRect(r.inflate(1.5), fill..color = colors.surface);
      t.paint(canvas, r.topLeft);
    }

    // 4. The avg tag, centred on the line in the gutter.
    if (avgY != null && tag != null) {
      tag.paint(canvas, Offset(size.width - tag.width, avgY - tag.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.avg != avg || old.labels != labels;
}

/// Timed cigarettes per hour, 06–24 (earlier when there is data before
/// 06:00). Empty hours are 2 px dim stubs.
class HourHistogram extends StatelessWidget {
  const HourHistogram({super.key, required this.hours});
  final Map<int, double> hours;

  @override
  Widget build(BuildContext context) {
    final first = math.min(6, hours.keys.fold<int>(24, math.min));
    final cols = [for (var h = first; h < 24; h++) h];
    final max = hours.values.fold<double>(0, math.max);
    final s = context.series;
    final ticks = [for (var h = first; h <= 24; h += 3) h];
    return Semantics(
      label: [
        for (final h in cols)
          if ((hours[h] ?? 0) > 0) '${trimNum(hours[h])} at ${hhmmOf(h * 60)}',
      ].join(', '),
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < cols.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        height: (hours[cols[i]] ?? 0) > 0
                            ? math.max(4, hours[cols[i]]! / max * 52)
                            : 2,
                        decoration: BoxDecoration(
                          color: (hours[cols[i]] ?? 0) > 0
                              ? s.smoke
                              : s.missing,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final h in ticks)
                  Text(
                    h.toString().padLeft(2, '0'),
                    style: small(context, dim: true, size: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One row per night, bar from bed to wake on a 20:00 → 12:00 axis, with a
/// shaded band for the usual bedtime (mean ± 1 SD).
class SleepWindows extends StatelessWidget {
  const SleepWindows({
    super.key,
    required this.days,
    required this.nights,
    required this.hours,
    this.bedtime,
  });

  final List<String> days;
  final List<Night> nights;
  final List<double?> hours;
  final BedtimeStats? bedtime;

  static const span = 960; // 20:00 → 12:00
  static const labelW = 34.0;
  static const valueW = 36.0;

  /// Minutes after 20:00 on the evening before [wakeDate].
  static int offset(Night n) => (n.bedScaled ?? 0) - 1200;

  @override
  Widget build(BuildContext context) {
    final s = context.series;
    return LayoutBuilder(
      builder: (context, box) {
        final trackW = box.maxWidth - labelW - valueW;
        double x(num m) => (m.clamp(0, span)) / span * trackW;
        final b = bedtime;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: labelW, right: valueW),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final t in ['20', '00', '04', '08', '12'])
                    Text(t, style: small(context, dim: true, size: 10)),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Stack(
              children: [
                if (b != null && b.count > 1)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: labelW + x(b.meanScaled - b.sdMin - 1200),
                    width: math.max(
                      2,
                      x(b.meanScaled + b.sdMin - 1200) -
                          x(b.meanScaled - b.sdMin - 1200),
                    ),
                    child: CustomPaint(painter: _BandPainter(s.band, s.sleep)),
                  ),
                Column(
                  children: [
                    for (var i = 0; i < days.length; i++)
                      _nightRow(context, i, x, trackW),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _nightRow(
    BuildContext context,
    int i,
    double Function(num) x,
    double trackW,
  ) {
    final d = parseDate(days[i])!;
    final label = '${dow2(d).substring(0, 1)} ${d.day}';
    final ns = [
      for (final n in nights)
        if (n.wakeDate == days[i] && n.bedMin != null && n.durationMin != null)
          n,
    ];
    final h = hours[i];
    return Semantics(
      label: h == null
          ? '$label: not logged'
          : '$label: ${[for (final n in ns) '${hhmmOf(n.bedMin!)} to ${n.wakeMin == null ? '?' : hhmmOf(n.wakeMin!)}'].join(', ')}, ${trimNum(h)} hours',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 24,
          child: Row(
            children: [
              SizedBox(
                width: labelW,
                child: Text(label, style: small(context)),
              ),
              SizedBox(
                width: trackW,
                height: 12,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final n in ns)
                      Positioned(
                        left: x(offset(n)),
                        top: 0,
                        width: math.max(
                          3,
                          x(offset(n) + n.durationMin!) - x(offset(n)),
                        ),
                        height: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.series.sleep,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: valueW,
                child: Text(
                  h == null ? dash : '${trimNum(h)}h',
                  textAlign: TextAlign.right,
                  style: small(context).copyWith(
                    color: h == null
                        ? context.colors.textDim
                        : context.colors.textSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.fill, this.edge);
  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final p = Paint()
      ..color = edge
      ..strokeWidth = 1;
    for (final x in [0.5, size.width - 0.5]) {
      for (var y = 0.0; y < size.height; y += 6) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + 3, size.height)),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) => false;
}

/// Weight dots on a fixed axis (≥ 4 kg) with a dashed average line.
class WeightDots extends StatelessWidget {
  const WeightDots({super.key, required this.week});
  final WeightWeek week;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: [
        for (final v in week.values)
          v == null ? 'not weighed' : '${trimNum(v, digits: 2)} kg',
      ].join(', '),
      child: ExcludeSemantics(
        child: CustomPaint(
          size: const Size(double.infinity, 58),
          painter: _WeightPainter(week, context.colors),
        ),
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter(this.w, this.c);
  final WeightWeek w;
  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = c.border,
    );
    if (w.lo == null) return;
    const pad = 6.0;
    double y(double v) =>
        pad + (w.hi! - v) / (w.hi! - w.lo!) * (size.height - 2 * pad);
    _dashedH(
      canvas,
      0,
      size.width,
      y(w.avg!),
      Paint()
        ..color = c.textMuted
        ..strokeWidth = 1.5,
    );
    final n = w.values.length;
    for (var i = 0; i < n; i++) {
      final v = w.values[i];
      if (v == null) continue;
      final cx = 6 + (n == 1 ? 0 : i / (n - 1)) * (size.width - 12);
      final o = Offset(cx, y(v));
      canvas.drawCircle(o, 6, Paint()..color = c.surface);
      canvas.drawCircle(o, 4, Paint()..color = c.text);
    }
  }

  @override
  bool shouldRepaint(_WeightPainter old) => old.w != w;
}

/// Small daily bars (steps); missing days are dim 2 px stubs.
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.color,
    this.height = 58,
  });
  final List<double?> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = values.whereType<double>().fold<double>(0, math.max);
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: values[i] == null || max == 0
                    ? 2
                    : math.max(2, values[i]! / max * (height - 2)),
                decoration: BoxDecoration(
                  color: values[i] == null ? context.series.missing : color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One hue, largest first, amount and share right-aligned.
class RankedBars extends StatelessWidget {
  const RankedBars({
    super.key,
    required this.items,
    required this.total,
    required this.color,
  });
  final List<CategoryTotal> items;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = items.isEmpty ? 1.0 : items.first.amount;
    return Column(
      children: [
        for (final c in items) ...[
          Semantics(
            label:
                '${c.name} ${rupees(c.amount)}, ${(c.amount / total * 100).round()} percent',
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          style: context.text.caption.copyWith(
                            fontSize: 13,
                            color: context.colors.text,
                          ),
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: rupees(c.amount),
                          style: context.text.caption.copyWith(
                            fontSize: 13,
                            color: context.colors.textSoft,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          children: [
                            TextSpan(
                              text: ' ${(c.amount / total * 100).round()}%',
                              style: TextStyle(color: context.colors.textDim),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  LayoutBuilder(
                    builder: (context, box) => Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.colors.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: math.max(
                          box.maxWidth * 0.02,
                          box.maxWidth * c.amount / max,
                        ),
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 5 dots, the first [level] filled.
class ConfidenceDots extends StatelessWidget {
  const ConfidenceDots(this.level, {super.key});
  final int level;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Confidence $level of 5',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i < level ? c.textSoft : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.series.bus),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Metric × day: filled = logged, dashed = partial, dim = missing.
class CoverageGrid extends StatelessWidget {
  const CoverageGrid({super.key, required this.rows, required this.days});
  final List<CoverageRow> rows;
  final List<String> days;

  static const nameW = 104.0;

  @override
  Widget build(BuildContext context) {
    final letters = dayLetters(days);
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: nameW),
            for (final l in letters) ...[
              const SizedBox(width: 4),
              SizedBox(
                width: 18,
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: small(context, dim: true, size: 10),
                ),
              ),
            ],
          ],
        ),
        for (final r in rows)
          Semantics(
            label:
                '${r.name}: ${r.note}. ${[for (var i = 0; i < days.length; i++) '${letters[i]} ${r.cells[i].name}'].join(', ')}',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 20,
                child: Row(
                  children: [
                    SizedBox(
                      width: nameW,
                      child: Text(
                        r.name,
                        style: context.text.caption.copyWith(
                          color: context.colors.textSoft,
                        ),
                      ),
                    ),
                    for (final cell in r.cells) ...[
                      const SizedBox(width: 4),
                      CoverageCell(cell),
                    ],
                    Expanded(
                      child: Text(
                        r.note,
                        textAlign: TextAlign.right,
                        style: small(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CoverageCell extends StatelessWidget {
  const CoverageCell(
    this.state, {
    super.key,
    this.width = 18,
    this.height = 14,
  });
  final Coverage state;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return switch (state) {
      Coverage.logged => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: c.textSoft,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      Coverage.missing => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: c.divider,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      Coverage.partial => CustomPaint(
        size: Size(width, height),
        painter: DashedRectPainter(c.textMuted, 3),
      ),
    };
  }
}

/// Dashed rounded outline (partial cells, "no time" badges).
class DashedRectPainter extends CustomPainter {
  DashedRectPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 5) {
        canvas.drawPath(m.extractPath(d, math.min(d + 2.5, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(DashedRectPainter old) => old.color != color;
}
