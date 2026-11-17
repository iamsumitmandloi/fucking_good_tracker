import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

typedef FontApplier = TextStyle Function(TextStyle base);

/// Type tokens from design/DESIGN.md: Space Grotesk for display and numbers,
/// Inter for body. Fonts are applied through [display]/[body] so tests can
/// swap google_fonts out.
@immutable
class AppText extends ThemeExtension<AppText> {
  const AppText({
    required this.h1,
    required this.h2,
    required this.statXl,
    required this.statL,
    required this.statM,
    required this.statS,
    required this.cardTitle,
    required this.question,
    required this.body,
    required this.bodyS,
    required this.label,
    required this.caption,
    required this.chip,
    required this.nav,
    required this.button,
    required this.overline,
    required this.mono,
  });

  factory AppText.build(
    AppColors c, {
    FontApplier? display,
    FontApplier? body,
  }) {
    final FontApplier d =
        display ?? (s) => GoogleFonts.spaceGrotesk(textStyle: s);
    final FontApplier b = body ?? (s) => GoogleFonts.inter(textStyle: s);
    const tab = [FontFeature.tabularFigures()];
    TextStyle disp(double size, FontWeight w, {double? height, double? ls}) =>
        d(
          TextStyle(
            fontSize: size,
            fontWeight: w,
            height: height,
            letterSpacing: ls,
            color: c.text,
            fontFeatures: tab,
          ),
        );
    TextStyle inter(double size, FontWeight w, Color color, {double? height}) =>
        b(
          TextStyle(
            fontSize: size,
            fontWeight: w,
            color: color,
            height: height,
          ),
        );
    return AppText(
      h1: disp(32, FontWeight.w700, ls: -0.64, height: 1.1),
      h2: disp(22, FontWeight.w700, height: 1.2),
      statXl: disp(34, FontWeight.w700, height: 1),
      statL: disp(28, FontWeight.w600, height: 1),
      statM: disp(22, FontWeight.w600, height: 1.1),
      statS: disp(18, FontWeight.w600, height: 1.2),
      cardTitle: disp(19, FontWeight.w700, height: 1.2),
      question: disp(22, FontWeight.w600, height: 1.3),
      body: inter(15, FontWeight.w600, c.text),
      bodyS: inter(13, FontWeight.w400, c.textSoft, height: 1.45),
      label: inter(14, FontWeight.w600, c.text),
      caption: inter(12, FontWeight.w400, c.textMuted, height: 1.35),
      chip: inter(11, FontWeight.w600, c.textMuted),
      nav: inter(11, FontWeight.w500, c.textMuted),
      button: inter(15, FontWeight.w700, c.onAccent),
      overline: inter(
        12,
        FontWeight.w600,
        c.onAccent,
      ).copyWith(letterSpacing: 0.48),
      mono: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.accent),
    );
  }

  final TextStyle h1;
  final TextStyle h2;
  final TextStyle statXl;
  final TextStyle statL;
  final TextStyle statM;
  final TextStyle statS;
  final TextStyle cardTitle;
  final TextStyle question;
  final TextStyle body;
  final TextStyle bodyS;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle chip;
  final TextStyle nav;
  final TextStyle button;
  final TextStyle overline;
  final TextStyle mono;

  @override
  AppText copyWith() => this;

  @override
  AppText lerp(ThemeExtension<AppText>? other, double t) => this;
}
