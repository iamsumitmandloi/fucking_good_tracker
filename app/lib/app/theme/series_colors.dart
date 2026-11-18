import 'package:material_ui/material_ui.dart';

/// Data colours from handoff_v2/design/DESIGN_v2.md (validated on the dark
/// surface #171A1E). Marks only: text never wears a series colour, and the
/// lime accent is never used for data.
@immutable
class SeriesColors extends ThemeExtension<SeriesColors> {
  const SeriesColors();

  static const standard = SeriesColors();

  Color get sleep => const Color(0xFF3987E5);
  Color get smoke => const Color(0xFFD95926);
  Color get food => const Color(0xFF199E70);
  Color get money => const Color(0xFFC98500);
  Color get bus => const Color(0xFF5D646E);

  /// "With no time" badge text (#F1C7A8) on the warn well.
  Color get untimedText => const Color(0xFFF1C7A8);

  /// Missing-data placeholder (#2A2F36).
  Color get missing => const Color(0xFF2A2F36);

  /// Ribbon lane track (#1F2329).
  Color get lane => const Color(0xFF1F2329);

  /// Usual-bedtime band: sleep at 14 % alpha.
  Color get band => const Color(0x243987E5);

  @override
  SeriesColors copyWith() => this;

  @override
  SeriesColors lerp(ThemeExtension<SeriesColors>? other, double t) => this;
}
