import 'package:material_ui/material_ui.dart';

/// Colour tokens from design/DESIGN.md. Dark only.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.bgBus,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.textSoft,
    required this.accent,
    required this.onAccent,
    required this.onAccentMuted,
    required this.accentWell,
    required this.info,
    required this.warn,
    required this.warnWell,
    required this.warnBorder,
    required this.busCard,
    required this.busEntry,
    required this.busBorder,
    required this.busWell,
    required this.busChip,
    required this.busTextMuted,
    required this.track,
    required this.barIdle,
    required this.scrim,
  });

  static const dark = AppColors(
    bg: Color(0xFF0E1012),
    bgBus: Color(0xFF0B1218),
    surface: Color(0xFF171A1E),
    surface2: Color(0xFF1F2329),
    border: Color(0xFF2A2F36),
    borderStrong: Color(0xFF3A414A),
    divider: Color(0xFF22262C),
    text: Color(0xFFEDEEF0),
    textMuted: Color(0xFFA3AAB4),
    textDim: Color(0xFF7D858F),
    textSoft: Color(0xFFC4C9D0),
    accent: Color(0xFFC8F169),
    onAccent: Color(0xFF0E1012),
    onAccentMuted: Color(0xFF2A3310),
    accentWell: Color(0xFF2B3317),
    info: Color(0xFF7CC4FF),
    warn: Color(0xFFFFA94D),
    warnWell: Color(0xFF2A1C10),
    warnBorder: Color(0xFF5A3A1E),
    busCard: Color(0xFF121C25),
    busEntry: Color(0xFF12202B),
    busBorder: Color(0xFF22394A),
    busWell: Color(0xFF1A3245),
    busChip: Color(0xFF15202A),
    busTextMuted: Color(0xFFA3B8C8),
    track: Color(0xFF262B32),
    barIdle: Color(0xFF4A525C),
    scrim: Color(0x8C050607),
  );

  final Color bg;
  final Color bgBus;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color borderStrong;
  final Color divider;
  final Color text;
  final Color textMuted;
  final Color textDim;

  /// #C4C9D0: body copy inside cards, chart value labels.
  final Color textSoft;
  final Color accent;
  final Color onAccent;

  /// #2A3310: secondary text on the lime Up-next card.
  final Color onAccentMuted;

  /// #2B3317: "CURRENT FOCUS" chip background.
  final Color accentWell;
  final Color info;
  final Color warn;
  final Color warnWell;
  final Color warnBorder;
  final Color busCard;

  /// Bus mode entry card on the Study tab (#12202B).
  final Color busEntry;
  final Color busBorder;
  final Color busWell;
  final Color busChip;
  final Color busTextMuted;

  /// Progress track (#262B32).
  final Color track;

  /// Week bars above budget (#4A525C).
  final Color barIdle;
  final Color scrim;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => this;
}
