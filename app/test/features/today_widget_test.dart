import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:starting_again/core/feature_flags.dart';

import '../support/app_harness.dart';

void main() {
  // Exercises the write paths, which Phase 7 keeps behind the flag.
  setUpAll(() => FeatureFlags.logging = true);
  tearDownAll(() => FeatureFlags.logging = false);

  group('Today widgets', () {
    testWidgets('tile tap → count, outbox row, undo line; undo restores', (
      tester,
    ) async {
      final h = await AppHarness.create();
      await h.pump(tester, '/today');

      final cig = find.byKey(const Key('tile-cig'));
      expect(
        find.descendant(of: cig, matching: find.text('—')),
        findsOneWidget,
      );

      await tester.tap(cig);
      await h.settle(tester);
      expect(
        find.descendant(of: cig, matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.text('Logged 1 cigarette · 18:02 · ₹25'), findsOneWidget);
      final rows = await tester.runAsync(
        () => h.deps.db.select(h.deps.db.outbox).get(),
      );
      expect(rows, hasLength(1));

      await tester.tap(find.byKey(const Key('undo-button')));
      await h.settle(tester);
      expect(
        find.descendant(of: cig, matching: find.text('—')),
        findsOneWidget,
      );
      final after = await tester.runAsync(
        () => h.deps.db.select(h.deps.db.outbox).get(),
      );
      expect(after, isEmpty);

      await h.dispose(tester);
    });

    testWidgets('quick log: type → preview → Log → written', (tester) async {
      final h = await AppHarness.create();
      await h.pump(tester, '/today');

      await tester.tap(find.byKey(const Key('quicklog-fab')));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Log anything'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('quicklog-input')),
        '1 cig + tea 45',
      );
      await h.settle(tester);
      expect(find.text('Cigarette × 1'), findsOneWidget);
      expect(find.text('Tea × 1'), findsOneWidget);
      expect(find.text('One payment, split for counts'), findsOneWidget);
      expect(find.text('Log 2 entries'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quicklog-submit')));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await h.settle(tester);

      expect(find.text('Log anything'), findsNothing);
      expect(find.text('Logged 2 entries · 18:02 · ₹45'), findsOneWidget);
      final cig = find.byKey(const Key('tile-cig'));
      expect(
        find.descendant(of: cig, matching: find.text('1')),
        findsOneWidget,
      );
      final rows = await tester.runAsync(
        () => h.deps.db.select(h.deps.db.outbox).get(),
      );
      expect(rows, hasLength(2));

      await h.dispose(tester);
    });

    testWidgets('bus button: Board → Arrived', (tester) async {
      final h = await AppHarness.create();
      await h.pump(tester, '/today');
      final button = find.byKey(const Key('bus-button'));
      await tester.ensureVisible(button);
      expect(
        find.descendant(of: button, matching: find.text('Board')),
        findsOneWidget,
      );
      await tester.tap(button);
      await h.settle(tester);
      expect(
        find.descendant(of: button, matching: find.text('Arrived')),
        findsOneWidget,
      );
      expect(find.text('On the bus'), findsOneWidget);
      await h.dispose(tester);
    });
  });
}
