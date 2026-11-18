import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/deps.dart';
import 'core/clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_IN');
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0E1012),
    ),
  );
  final deps = await AppDeps.create(
    connectivity: Connectivity(),
    clock: _clock,
  );
  runApp(StartingAgainApp(deps: deps, initialLocation: _startAt));
}

/// `--dart-define=START_AT=/week` opens on another tab (screenshots, checks).
/// Empty → the default tab (Day, or Today when logging is on).
const _startAtRaw = String.fromEnvironment('START_AT');
const String? _startAt = _startAtRaw == '' ? null : _startAtRaw;

/// `--dart-define=TODAY=2026-11-17` pins "today" (23:00 IST that day) so the
/// screens can be compared with the design files. Dev builds only.
const _todayRaw = String.fromEnvironment('TODAY');
final Clock _clock = () {
  final d = parseDate(_todayRaw);
  return d == null
      ? const SystemClock()
      : FixedClock.ist(d.year, d.month, d.day, 23);
}();
