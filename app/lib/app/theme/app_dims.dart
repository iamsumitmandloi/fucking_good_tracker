import 'package:material_ui/material_ui.dart';

/// Spacing and radius tokens from design/DESIGN.md.
@immutable
class AppDims extends ThemeExtension<AppDims> {
  const AppDims();

  static const standard = AppDims();

  // Spacing
  double get screenH => 18;
  double get screenTop => 28;
  double get gap => 10;
  double get gapL => 12;
  double get cardPad => 14;
  double get cardPadL => 16;

  // Radii
  double get rCard => 18;
  double get rHero => 20;
  double get rBusCard => 22;
  double get rSheet => 28;
  double get rChip => 8;
  double get rChipL => 12;
  double get rButton => 14;
  double get rPill => 20;

  // Sizes
  double get minTouch => 44;
  double get tileHeight => 104;
  double get navHeight => 76;
  double get buttonH => 48;
  double get buttonHL => 56;
  double get iconSize => 20;
  double get iconStroke => 1.8;

  @override
  AppDims copyWith() => this;

  @override
  AppDims lerp(ThemeExtension<AppDims>? other, double t) => this;
}
