import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dims.dart';
import 'app_text.dart';

export 'app_colors.dart';
export 'app_dims.dart';
export 'app_text.dart';

ThemeData buildTheme({FontApplier? display, FontApplier? body}) {
  const c = AppColors.dark;
  final t = AppText.build(c, display: display, body: body);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.dark(
      surface: c.surface,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.info,
      error: c.warn,
      onSurface: c.text,
      outline: c.border,
    ),
    dividerColor: c.divider,
    splashFactory: InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: c.text,
      displayColor: c.text,
      fontFamily: t.caption.fontFamily,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface2,
      contentTextStyle: t.caption.copyWith(color: c.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.bg,
      labelStyle: t.caption,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    extensions: [c, t, AppDims.standard],
  );
}

extension ThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  AppText get text => Theme.of(this).extension<AppText>()!;
  AppDims get dims => Theme.of(this).extension<AppDims>()!;
}
