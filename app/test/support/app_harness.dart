import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:starting_again/app/app.dart';
import 'package:starting_again/app/deps.dart';
import 'package:starting_again/app/theme/app_theme.dart';
import 'package:starting_again/core/clock.dart';
import 'package:starting_again/data/remote/sheet_config.dart';

import 'fake_sheet_server.dart';

/// Theme without google_fonts (no network in tests).
final testTheme = buildTheme(display: (s) => s, body: (s) => s);

class AppHarness {
  AppHarness._(this.server, this.deps);

  final FakeSheetServer server;
  final AppDeps deps;

  static Future<AppHarness> create({
    Map<String, List<Map<String, dynamic>>>? tabs,
    Clock? clock,
  }) async {
    await initializeDateFormatting('en_IN');
    final server = FakeSheetServer(tabs: tabs);
    final deps = await AppDeps.create(
      clock: clock ?? testClock(),
      db: memoryDb(),
      config: MemorySheetConfigStore(
        const SheetConfig(url: testUrl, token: testToken),
      ),
      client: server.client,
      startSync: false,
    );
    return AppHarness._(server, deps);
  }

  Future<void> pump(WidgetTester tester, String location) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      StartingAgainApp(deps: deps, theme: testTheme, initialLocation: location),
    );
    await settle(tester);
  }

  /// Lets drift (real async) and the UI catch up.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Let queries started in the fake-async zone finish before closing,
    // otherwise db.close() waits on them forever.
    await settle(tester);
    deps.sync.dispose();
    final closing = deps.db.close();
    await settle(tester);
    await tester.runAsync(() => closing);
    await tester.binding.setSurfaceSize(null);
  }
}
