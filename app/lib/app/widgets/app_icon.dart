import 'package:flutter/widgets.dart';

/// Stroke icons traced from the design files (24×24 viewBox, 1.8 stroke).
enum AppIcons {
  cigarette,
  tea,
  water,
  meal,
  pill,
  protein,
  bus,
  plus,
  close,
  chevron,
  today,
  study,
  week,
  money,
  clock,
  settings,
  edit,
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.stroke = 1.8,
    this.semanticLabel,
  });

  final AppIcons icon;
  final double size;
  final Color? color;
  final double stroke;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color!;
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _IconPainter(icon, c, stroke),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painter);
    return Semantics(label: semanticLabel, child: painter);
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.stroke);

  final AppIcons icon;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in _paths(icon)) {
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.stroke != stroke;
}

Path _line(List<double> pts) {
  final p = Path()..moveTo(pts[0], pts[1]);
  for (var i = 2; i < pts.length; i += 2) {
    p.lineTo(pts[i], pts[i + 1]);
  }
  return p;
}

Path _rrect(double x, double y, double w, double h, double r) =>
    Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)));

const _cw = true;

List<Path> _paths(AppIcons icon) {
  switch (icon) {
    case AppIcons.cigarette:
      return [
        _rrect(3, 14, 13, 4, 0),
        _line([19, 14, 19, 18]),
        _line([21.5, 14, 21.5, 18]),
        Path()
          ..moveTo(18, 5)
          ..cubicTo(18, 7, 20.5, 7, 20.5, 9.5),
      ];
    case AppIcons.tea:
      return [
        Path()
          ..moveTo(4, 8)
          ..lineTo(16, 8)
          ..lineTo(16, 14)
          ..arcToPoint(const Offset(11, 19), radius: const Radius.circular(5))
          ..lineTo(9, 19)
          ..arcToPoint(const Offset(4, 14), radius: const Radius.circular(5))
          ..close(),
        Path()
          ..moveTo(16, 10)
          ..lineTo(18, 10)
          ..arcToPoint(const Offset(18, 14), radius: const Radius.circular(2))
          ..lineTo(16, 14),
      ];
    case AppIcons.water:
      return [
        Path()
          ..moveTo(12, 3)
          ..cubicTo(12, 3, 18, 9.5, 18, 14)
          ..arcToPoint(const Offset(6, 14), radius: const Radius.circular(6))
          ..cubicTo(6, 9.5, 12, 3, 12, 3)
          ..close(),
      ];
    case AppIcons.meal:
      return [
        Path()
          ..moveTo(3, 11)
          ..lineTo(21, 11)
          ..arcToPoint(const Offset(3, 11), radius: const Radius.circular(9))
          ..close(),
        Path()
          ..moveTo(9, 7)
          ..cubicTo(9, 5.8, 10.2, 5.8, 10.2, 4.6),
        Path()
          ..moveTo(13.5, 7)
          ..cubicTo(13.5, 5.8, 14.7, 5.8, 14.7, 4.6),
      ];
    case AppIcons.pill:
      return [
        Path()
          ..moveTo(10.5, 20.5)
          ..lineTo(3.5, 13.5)
          ..arcToPoint(
            const Offset(10.5, 6.5),
            radius: const Radius.circular(5),
            clockwise: _cw,
          )
          ..lineTo(17.5, 13.5)
          ..arcToPoint(
            const Offset(10.5, 20.5),
            radius: const Radius.circular(5),
            clockwise: _cw,
          )
          ..close(),
        _line([7, 10, 14, 17]),
      ];
    case AppIcons.protein:
      return [
        Path()
          ..moveTo(12, 3)
          ..cubicTo(15.5, 3, 18, 9, 18, 13)
          ..arcToPoint(const Offset(6, 13), radius: const Radius.circular(6))
          ..cubicTo(6, 9, 8.5, 3, 12, 3)
          ..close(),
      ];
    case AppIcons.bus:
      return [
        _rrect(4, 4, 16, 13, 2),
        _line([4, 11, 20, 11]),
        _line([8, 20, 8, 17]),
        _line([16, 20, 16, 17]),
      ];
    case AppIcons.plus:
      return [
        _line([12, 5, 12, 19]),
        _line([5, 12, 19, 12]),
      ];
    case AppIcons.close:
      return [
        _line([6, 6, 18, 18]),
        _line([18, 6, 6, 18]),
      ];
    case AppIcons.chevron:
      return [
        _line([9, 6, 15, 12, 9, 18]),
      ];
    case AppIcons.today:
      return [
        _rrect(4, 4, 16, 16, 4),
        _line([4, 10, 20, 10]),
      ];
    case AppIcons.study:
      return [
        Path()
          ..moveTo(4, 5)
          ..arcToPoint(const Offset(6, 3), radius: const Radius.circular(2))
          ..lineTo(20, 3)
          ..lineTo(20, 19)
          ..lineTo(6, 19)
          ..arcToPoint(
            const Offset(4, 21),
            radius: const Radius.circular(2),
            clockwise: false,
          )
          ..close(),
        _line([4, 19, 4, 5]),
      ];
    case AppIcons.week:
      return [
        _line([3, 17, 9, 11, 13, 15, 21, 7]),
        _line([15, 7, 21, 7, 21, 13]),
      ];
    case AppIcons.money:
      return [
        _line([6, 4, 18, 4]),
        _line([6, 9, 18, 9]),
        Path()
          ..moveTo(6, 4)
          ..lineTo(9, 4)
          ..arcToPoint(const Offset(9, 14), radius: const Radius.circular(5))
          ..lineTo(6, 14)
          ..lineTo(14, 20),
      ];
    case AppIcons.clock:
      return [
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 10)),
        _line([12, 7, 12, 12, 15, 14]),
      ];
    case AppIcons.settings:
      return [
        _line([4, 7, 13, 7]),
        _line([19, 7, 20, 7]),
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(16, 7), radius: 2.5)),
        _line([4, 17, 5, 17]),
        _line([11, 17, 20, 17]),
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(8, 17), radius: 2.5)),
      ];
    case AppIcons.edit:
      return [
        _line([4, 20, 8, 19, 19, 8, 16, 5, 5, 16, 4, 20]),
      ];
  }
}
