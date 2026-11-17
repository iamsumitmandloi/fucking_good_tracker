# PROGRESS

**Current phase:** 3 (Today + Quick log) in progress.
**Last update:** 2026-11-17 IST
**Mode:** offline build. `secrets.json` holds DUMMY values (owner's call, 17 Nov). Every live gate is replaced by a fake-server test; the live checks are listed under "Owner to verify".

## Toolchain
- Flutter 3.47.9 stable (fvm default), Dart 3.13.7, DevTools 2.60.0
- Xcode 27.2, Android SDK 37.0.0 (some Android licences not accepted: run `flutter doctor --android-licenses` before the release APK)

## Phase 0: Recon ✅ (live read deferred)
- Root `.gitignore`, `PLAN.md`, `DECISIONS.md`, `CLAUDE.md`
- Live read + header capture: **deferred to owner** (dummy secrets)

## Phase 1: Foundation ✅
- `app/` created (com.sumitmandloi / starting_again). Packages via `flutter pub add`.
- Theme tokens (`AppColors`, `AppText`, `AppDims` ThemeExtensions), router + 4-tab shell, Settings (URL/token → secure storage, masked, Test connection, sync log, preferences)
- `SheetApi` (302 → GET Location, 20 s timeout, typed failures), drift schema, `EventsRepository` (cache-first, merge), `SyncService` (debounce 10 s, backoff 2^n ≤ 5 min, idempotent)
- Tests: SheetApi (200 / 302 / ok:false / timeout / 5xx / HTML), outbox flush + retry + debounce, undo before/after sync, refresh merge, Event JSON round-trip
- Gate: tests green ✅ · simulator run → checked in Phase 5 · live "Test connection" + dev write → **owner**

## Phase 2: Study + Bus mode ✅
- Study tab (countdown, assessed x/N, tier, sessions, T1 pace, focus from Start Here, 25-min timer, Log it, browse bank)
- Bus mode (Leitner queue, reveal → rate, one `study` event per card, offline, exit keeps progress, summary)
- Tests: Leitner, queue order, Study Bank + Start Here parsing, progress maths (16/day on 17 Nov), gate test (3 cards offline → reconnect → exactly 3 dev- rows), widget tests
- Gate: green (56 tests) ✅ · live airplane-mode run → **owner**

## Phase 3: Today + Quick log 🟡 IN PROGRESS (paused 17 Nov 19:56)
Written, NOT yet analyzed or tested:
- `app/lib/domain/derivations/sleep.dart` (sleep windows, bed → next wake ≤ 18 h, label = wake date, late = bed ≥ 02:00)
- `app/lib/domain/derivations/daily_stats.dart` (DaySummary, nulls for missing; protein = meal with unit `g`)
- `app/lib/domain/derivations/commute.dart` (bus legs; used by Bus mode, tested indirectly)
- `app/lib/domain/quicklog/parser.dart` (regex grammar; combo split "1 cig + tea 45" → ₹25 + ₹20; unparsed → note)

Next, in order:
1. Run `dart format . && flutter analyze` in `app/`; fix issues in the 4 files above.
2. Write `app/test/domain/parser_test.dart` (≥ 30 cases: habits, combos, water, meals/spend, weight/sleep/wake, bus "office reached 10:40", "tea at 16:30", fallbacks "After lunch" / "~12:30 (AM/PM unconfirmed)" → note) + sleep/commute/daily_stats tests.
3. TodayCubit + TodayScreen (replace placeholder in `features/today/`): tiles, 6 s undo, cig warn > budget, bus Board→Arrived→Done card, Up-next (lime), sleep + spend cards, sync dot, FAB → Quick log, long-press tile → Quick log.
4. QuickLog sheet (`features/quicklog/`): preview, time chips (Now / 15 min ago / ~Approx / pick), "Repeat a usual" = top 5 labels in 14 days, explicit time later than now → yesterday.
5. Tests: tile → outbox, undo before/after sync, two bus legs, gate (5 mixed entries offline → reconnect → 5 rows once, dev- ids, type note).
Then Phase 4 (Week + Money + legacy adapter), 5 (polish, release APK, README), 6 (home widget, 21:00 nudge).

Known gotcha: widget tests must settle the fake-async zone before closing drift (see `test/support/app_harness.dart` `dispose`), or the run hangs.

## Dev rows written to the live sheet
None (no live access).

## Owner to verify (live)
1. Phase 0: GET `tabs=Start Here,Study Bank,Events`; compare headers with DECISIONS.md assumptions.
2. Phase 1: Settings → Test connection shows OK; one `dev-phase1-<ts>` note lands.
3. Phase 2: Bus mode 3 cards in airplane mode → reconnect → 3 study rows (use a dev build; see README).
