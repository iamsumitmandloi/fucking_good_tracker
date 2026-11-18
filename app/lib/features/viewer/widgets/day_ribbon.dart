import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/app_theme.dart';
import '../../../domain/viewer/day_view.dart';

/// The Day tab's 24-hour ribbon: lanes Sleep / Bus / Smoke / Food / ₹ on a
/// 00:00–24:00 axis. Marks stay thin; every mark has a ≥ 24 px tap target,
/// and a tap reports the mark (its detail goes in a line under the ribbon,
/// never a floating tooltip).
class DayRibbon extends StatelessWidget {
  const DayRibbon({
    super.key,
    required this.marks,
    required this.onSelect,
    this.selected,
  });

  final List<RibbonMark> marks;
  final RibbonMark? selected;
  final ValueChanged<RibbonMark> onSelect;

  static const labelW = 50.0;
  static const axisH = 14.0;

  /// Lane heights, in [Lane] order.
  static const laneH = [22.0, 22.0, 30.0, 26.0, 30.0];
  static const laneNames = ['Sleep', 'Bus', 'Smoke', 'Food', '₹ spent'];

  static double get height => axisH + laneH.reduce((a, b) => a + b);

  static double laneTop(Lane l) {
    var y = axisH;
    for (var i = 0; i < l.index; i++) {
      y += laneH[i];
    }
    return y;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final trackW = w - labelW;
        final geo = _Geometry(trackW);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final m = geo.hit(marks, d.localPosition);
            if (m != null) onSelect(m);
          },
          child: CustomPaint(
            size: Size(w, height),
            painter: _RibbonPainter(
              marks: marks,
              selected: selected,
              geo: geo,
              colors: context.colors,
              series: context.series,
              labelStyle: context.text.caption.copyWith(fontSize: 11),
              tickStyle: context.text.caption.copyWith(
                fontSize: 10,
                color: context.colors.textDim,
              ),
              countStyle: context.text.caption.copyWith(
                fontSize: 9,
                color: context.colors.textSoft,
              ),
              onSelect: onSelect,
            ),
          ),
        );
      },
    );
  }
}

class _Geometry {
  _Geometry(this.trackW);
  final double trackW;

  double x(num minute) => DayRibbon.labelW + minute / 1440 * trackW;

  /// The mark under [p]: same lane, horizontal distance ≤ 12 px from a
  /// point (or inside a bar ± 6 px); nearest wins.
  RibbonMark? hit(List<RibbonMark> marks, Offset p) {
    Lane? lane;
    for (final l in Lane.values) {
      final top = DayRibbon.laneTop(l);
      if (p.dy >= top - 4 && p.dy < top + DayRibbon.laneH[l.index] + 4) {
        lane = l;
        break;
      }
    }
    if (lane == null) return null;
    RibbonMark? best;
    var bestD = double.infinity;
    for (final m in marks) {
      if (m.lane != lane) continue;
      final double d;
      if (m.end != null) {
        final a = x(m.start) - 6;
        final b = math.max(x(m.end!), x(m.start) + 6) + 6;
        if (p.dx < a || p.dx > b) continue;
        d = (p.dx - (a + b) / 2).abs();
      } else {
        d = (p.dx - x(m.start)).abs();
        if (d > 12) continue;
      }
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    return best;
  }

  Rect rectOf(RibbonMark m) {
    final top = DayRibbon.laneTop(m.lane);
    final h = DayRibbon.laneH[m.lane.index];
    if (m.end != null) {
      return Rect.fromLTRB(
        x(m.start) - 6,
        top,
        math.max(x(m.end!), x(m.start) + 6) + 6,
        top + h,
      );
    }
    return Rect.fromCenter(
      center: Offset(x(m.start), top + h / 2),
      width: 24,
      height: math.max(24, h),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({
    required this.marks,
    required this.selected,
    required this.geo,
    required this.colors,
    required this.series,
    required this.labelStyle,
    required this.tickStyle,
    required this.countStyle,
    required this.onSelect,
  });

  final List<RibbonMark> marks;
  final RibbonMark? selected;
  final _Geometry geo;
  final AppColors colors;
  final SeriesColors series;
  final TextStyle labelStyle;
  final TextStyle tickStyle;
  final TextStyle countStyle;
  final ValueChanged<RibbonMark> onSelect;

  void _text(Canvas c, String s, TextStyle st, Offset at, {double ax = 0}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(at.dx - tp.width * ax, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Axis ticks 00 06 12 18 24.
    for (var h = 0; h <= 24; h += 6) {
      final ax = h == 0 ? 0.0 : (h == 24 ? 1.0 : 0.5);
      _text(
        canvas,
        h.toString().padLeft(2, '0'),
        tickStyle,
        Offset(geo.x(h * 60), DayRibbon.axisH / 2 - 1),
        ax: ax,
      );
    }
    final fill = Paint();
    for (final l in Lane.values) {
      final top = DayRibbon.laneTop(l);
      final h = DayRibbon.laneH[l.index];
      _text(
        canvas,
        DayRibbon.laneNames[l.index],
        labelStyle,
        Offset(0, top + h / 2),
      );
      final left = geo.x(0);
      final right = geo.x(1440);
      switch (l) {
        case Lane.sleep:
        case Lane.bus:
          final r = RRect.fromLTRBR(
            left,
            top + (h - 14) / 2,
            right,
            top + (h + 14) / 2,
            const Radius.circular(4),
          );
          canvas.drawRRect(r, fill..color = series.lane);
        case Lane.smoke:
          canvas.drawLine(
            Offset(left, top + h - 4),
            Offset(right, top + h - 4),
            Paint()
              ..color = colors.border
              ..strokeWidth = 1,
          );
        case Lane.food:
        case Lane.money:
          break;
      }
    }

    for (final m in marks) {
      final top = DayRibbon.laneTop(m.lane);
      final h = DayRibbon.laneH[m.lane.index];
      final isSel = m == selected;
      switch (m.lane) {
        case Lane.sleep:
        case Lane.bus:
          final minW = m.lane == Lane.sleep ? 4.0 : 6.0;
          final r = RRect.fromLTRBR(
            geo.x(m.start),
            top + (h - 14) / 2,
            math.max(geo.x(m.end!), geo.x(m.start) + minW),
            top + (h + 14) / 2,
            const Radius.circular(4),
          );
          canvas.drawRRect(
            r,
            fill..color = m.lane == Lane.sleep ? series.sleep : series.bus,
          );
          if (isSel) _outline(canvas, r);
        case Lane.smoke:
          final barH = 8 + m.size * 5;
          final base = top + h - 4;
          final r = RRect.fromLTRBAndCorners(
            geo.x(m.start) - 2.5,
            base - math.min(barH, h - 6),
            geo.x(m.start) + 2.5,
            base,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          );
          canvas.drawRRect(r, fill..color = series.smoke);
          if (m.size > 1) {
            _text(
              canvas,
              m.size == m.size.roundToDouble()
                  ? m.size.toStringAsFixed(0)
                  : m.size.toStringAsFixed(1),
              countStyle,
              Offset(geo.x(m.start), r.top - 6),
              ax: 0.5,
            );
          }
          if (isSel) _outline(canvas, r);
        case Lane.food:
        case Lane.money:
          final d = m.lane == Lane.food
              ? (m.big ? 12.0 : 8.0)
              : (6 + math.min(14, math.sqrt(m.size) / 2)).roundToDouble();
          final c = Offset(geo.x(m.start), top + h / 2);
          canvas.drawCircle(c, d / 2 + 2, fill..color = colors.surface);
          canvas.drawCircle(
            c,
            d / 2,
            fill..color = m.lane == Lane.food ? series.food : series.money,
          );
          if (isSel) {
            canvas.drawCircle(
              c,
              d / 2 + 2,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = colors.text,
            );
          }
      }
    }
  }

  void _outline(Canvas c, RRect r) => c.drawRRect(
    r.inflate(1.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = colors.text,
  );

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final m in marks)
          CustomPainterSemantics(
            rect: geo.rectOf(m),
            properties: SemanticsProperties(
              label: m.semantics,
              button: true,
              textDirection: TextDirection.ltr,
              onTap: () => onSelect(m),
            ),
          ),
      ];

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.marks != marks ||
      old.selected != selected ||
      old.geo.trackW != geo.trackW;

  @override
  bool shouldRebuildSemantics(_RibbonPainter old) =>
      old.marks != marks || old.geo.trackW != geo.trackW;
}
