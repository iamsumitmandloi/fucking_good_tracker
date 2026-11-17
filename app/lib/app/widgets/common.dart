import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

/// Surface card: #171A1E, 1px #2A2F36 border, radius 18.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.color,
    this.borderColor,
    this.onTap,
    this.dashed = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(radius ?? context.dims.rCard);
    Widget content = Padding(
      padding: padding ?? EdgeInsets.all(context.dims.cardPad),
      child: child,
    );
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: r, child: content);
    }
    final decorated = Material(
      color: color ?? c.surface,
      shape: dashed
          ? null
          : RoundedRectangleBorder(
              borderRadius: r,
              side: BorderSide(color: borderColor ?? c.border),
            ),
      borderRadius: dashed ? r : null,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
    if (!dashed) return decorated;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(
        color: borderColor ?? c.borderStrong,
        radius: radius ?? context.dims.rCard,
      ),
      child: decorated,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Lime filled button (48–56 tall).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 48,
    this.background,
    this.foreground,
    this.radius = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color? background;
  final Color? foreground;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = foreground ?? c.onAccent;
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background ?? c.accent,
          foregroundColor: fg,
          disabledBackgroundColor: c.surface2,
          disabledForegroundColor: c.textDim,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: context.text.button,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Text(label, style: context.text.button.copyWith(color: fg)),
      ),
    );
  }
}

/// Outlined button, #3A414A border.
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 44,
    this.color,
    this.borderColor,
    this.fill,
    this.radius = 12,
    this.borderWidth = 1,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color? color;
  final Color? borderColor;
  final Color? fill;
  final double radius;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.text;
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: fill,
          side: BorderSide(
            color: borderColor ?? c.borderStrong,
            width: borderWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(44, 44),
        ),
        child: Text(label, style: context.text.label.copyWith(color: fg)),
      ),
    );
  }
}

/// Screen title block: caption over a 32/700 heading.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.caption,
    required this.title,
    this.trailing,
  });

  final String caption;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: context.text.caption.copyWith(
                  fontSize: 13,
                  letterSpacing: 0.26,
                ),
              ),
              const SizedBox(height: 2),
              Text(title, style: context.text.h1),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A list or card with nothing in it yet. Never shows a 0.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.action,
  });

  final String title;
  final String message;
  final AppIcons? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      dashed: true,
      color: Colors.transparent,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, color: context.colors.textMuted),
            const SizedBox(height: 10),
          ],
          Text(title, style: context.text.label),
          const SizedBox(height: 4),
          Text(message, style: context.text.caption),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// Small stat block: label / big number / caption.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.onTap,
    this.radius = 16,
    this.padding = 12,
  });

  final String label;
  final Widget value;
  final String? caption;
  final VoidCallback? onTap;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: radius,
      padding: EdgeInsets.all(padding),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.caption),
          const SizedBox(height: 4),
          value,
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: context.text.caption),
          ],
        ],
      ),
    );
  }
}

/// Small rounded tag (11/600).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.background, this.color});

  final String text;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? context.colors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: context.text.chip.copyWith(color: color)),
    );
  }
}

/// Number with a dimmer suffix, e.g. "0/4" or "₹962/day".
class NumberWithUnit extends StatelessWidget {
  const NumberWithUnit(
    this.value,
    this.unit, {
    super.key,
    this.style,
    this.unitSize = 16,
    this.color,
  });

  final String value;
  final String unit;
  final TextStyle? style;
  final double unitSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = (style ?? context.text.statL).copyWith(color: color);
    return Text.rich(
      TextSpan(
        text: value,
        style: s,
        children: [
          TextSpan(
            text: unit,
            style: s.copyWith(
              fontSize: unitSize,
              color: context.colors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
