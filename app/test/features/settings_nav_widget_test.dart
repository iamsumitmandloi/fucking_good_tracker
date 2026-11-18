import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:starting_again/core/feature_flags.dart';
import 'package:starting_again/data/remote/sheet_config.dart';
import 'package:starting_again/features/busmode/busmode_screen.dart';

import '../support/app_harness.dart';
import '../support/fake_sheet_server.dart';

void main() {
  testWidgets('Settings: token never shown; Test connection; Save', (
    tester,
  ) async {
    final h = await AppHarness.create();
    await h.pump(tester, '/settings');

    // The URL is shown; the token never is, only a mask.
    expect(find.text(testUrl), findsOneWidget);
    expect(find.textContaining(testToken), findsNothing);
    expect(find.text('•••• saved · type to replace'), findsOneWidget);

    await tester.tap(find.text('Test connection'));
    await h.settle(tester);
    expect(
      find.text('OK · Connected. No "Start Here" tab found.'),
      findsOneWidget,
    );
    // Only the tab it needs (then the normal Events refresh follows).
    expect(
      h.server.requested.map((u) => u.queryParameters['tabs']),
      contains('Start Here'),
    );

    await tester.tap(find.text('Save'));
    await h.settle(tester);
    expect(find.text('Saved'), findsOneWidget);
    // Saving with an empty token field keeps the stored token.
    final cfg = await tester.runAsync(() => h.deps.config.load());
    expect(cfg!.token, testToken);

    await h.dispose(tester);
  });

  testWidgets('Settings: wrong token shows a readable error', (tester) async {
    final h = await AppHarness.create();
    await tester.runAsync(
      () => h.deps.config.save(const SheetConfig(url: testUrl, token: 'nope')),
    );
    await h.pump(tester, '/settings');
    await tester.tap(find.text('Test connection'));
    await h.settle(tester);
    expect(find.textContaining('OK ·'), findsNothing);
    expect(find.textContaining('nope'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('Today → Up next "Bus mode" opens Bus mode', (tester) async {
    FeatureFlags.logging = true; // Today and Bus mode only exist with it
    addTearDown(() => FeatureFlags.logging = false);
    final h = await AppHarness.create();
    await h.pump(tester, '/today');
    final button = find.widgetWithText(OutlinedButton, 'Bus mode');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BusModeScreen), findsOneWidget);
    await h.dispose(tester);
  });
}
