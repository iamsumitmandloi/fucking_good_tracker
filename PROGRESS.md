# PROGRESS

**Current phase:** 5 (polish + release) next. Phases 0–4 done.
**Last update:** 2026-11-17 IST
**Mode:** offline build. `secrets.json` holds DUMMY values (owner's call, 17 Nov). Every live gate is replaced by a fake-server test; the live checks are listed under "Owner to verify".

## Toolchain
- Flutter 3.50.0 stable (plain `flutter`, no fvm), Dart 3.14.0, DevTools 2.61.0 (was 3.47.9 via fvm; see DECISIONS 10–11)
- 2026-11-17 resume check on the new machine: `secrets.json` copied from example (dummy), `pub get` ok, Material imports migrated to `material_ui`, analyze 0 issues, 56/56 tests green. Phase 3 step 1 (analyze the 4 new files) is therefore done.
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

## Phase 3: Today + Quick log ✅
- Domain: `derivations/sleep.dart`, `daily_stats.dart`, `commute.dart`, `quicklog/parser.dart` (analyzed, tested, 6 parser fixes: DECISIONS 12), `quicklog/build_events.dart` (time chips, "later than now → yesterday", Repeat-a-usual, undo-line text)
- Today (`features/today/`): `TodayCubit` + `TodayScreen` + `today_widgets.dart`
  - 6 tiles (cig/tea/water tap = +1, meal → Quick log by time of day, supplements checklist, breakfast protein); dashed when never logged; "—" when nothing today
  - cig number turns warn above the budget; 6 s undo line ("Logged 1 cigarette · 18:02 · ₹25 · Undo"), else "Last: …"
  - bus card Board → Arrived → Board home → Arrived → Done; Up-next (lime) from Start Here with countdown; sleep card (approx "est.", orange after 02:00); spend card (today + week, taps to Money)
  - header "Tue 17 Nov · Day N" + sync dot; offline banner; pull-to-refresh; FAB and long-press → Quick log; refreshes Study tabs when older than 6 h (for Up next)
- Quick log (`features/quicklog/`): live preview of every entry, split-payment footer, When chips (Now · HH:mm / 15 min ago / ~ Approx / Pick time), Repeat-a-usual chips (top 5 labels, 14 days) add to the preview, "Log N entries". The sheet returns events; Today writes them (one undo for the batch).
- `DEV_IDS` build flag (`--dart-define=DEV_IDS=true`): every new id gets `dev-` for live checks (DECISIONS 19)
- Tests (+109 → 165 total): parser 61 cases, derivations 16, build_events/usuals 17, Today cubit 10 incl. the gate, Today widgets 3
- Gate: green ✅ fake-server gate test: 5 mixed entries offline → flush fails, outbox 5 → reconnect → one POST, 5 `dev-` rows, second flush + refresh add nothing · live airplane-mode run → **owner**

## Phase 4: Week + Money + legacy adapter ✅
- Domain: `derivations/burn.dart` (day-to-day burn excl. bills/one_off, delivery / everything else / one-offs split, pay later = lazypay), `derivations/weight.dart` (last per day, avg of days with a value, axis ≥ 4 kg centred on the rounded avg), `derivations/week.dart` (7 days ending today, cig bars with null gaps, sleep rows on the 21:00→11:00 track, not-logged counts)
- Legacy: `legacy/legacy_cell.dart` (first number, range midpoint, `~`/range → approx, N/A/text → missing, raw kept, never throws), `legacy/legacy_adapter.dart` (header-pattern column matching, Daily Summary / Spending / Timeline → read-only `legacy-` events, Events tab wins per date+metric, 16 Nov data-bug flags)
- Week tab: header "Wed 11 – Tue 17 Nov · N of 7 days logged", cigarette bars (lime ≤ budget, grey above, "—" gaps) + trend sentence, sleep-window rows (orange when bedtime ≥ 02:00) + late-night sentence, weight dots + dashed avg line on the fixed axis, Not-logged card, "Sheet data to check" card for legacy flags
- Money tab: ₹/day burn, week and incl.-one-offs totals, stacked bar + legend, delivery-share sentence, Pay later card, Smoking est. card, today's entries
- Shared `features/shared/merged_events.dart`; pull-to-refresh on Week/Money also force-refreshes the legacy tabs; Today's "Day N" now counts legacy history
- Charts are plain widgets + one CustomPainter (no fl_chart)
- Tests (+23 → 188 total): legacy cell/dates/adapter/merge 9, week/weight/burn 10, Week + Money widgets 3, Today Day N with legacy 1
- Gate: green ✅ · real-number check (48 cigs, ₹10,616.79 for 11–17 Nov) needs the live legacy read → **owner**

Next, in order (Phase 5: polish + release):
1. Pass over all screens against the `.dc.html` files (spacing, type, 44 px targets, no emoji, empty/offline states); add a small "DEV build" marker when `DEV_IDS` is on.
2. Remaining widget tests from PRD §8 not yet covered (Settings save/mask, Study → Bus mode navigation).
3. Run on the iOS simulator / Android emulator (`flutter run --dart-define-from-file=../secrets.json`); fix anything visual.
4. `flutter doctor --android-licenses` (owner, interactive) → `flutter build apk --release`.
5. Root README: setup, run, dev build, tests, side-load, owner checks.
Then Phase 6 (home widget, 21:00 nudge).

Known gotcha: widget tests must settle the fake-async zone before closing drift (see `test/support/app_harness.dart` `dispose`), or the run hangs. Keep widget tests in their own files (no shared drift setUp/tearDown with plain tests).

## Dev rows written to the live sheet
None (no live access).

## Owner to verify (live)
1. Phase 0: GET `tabs=Start Here,Study Bank,Events`; compare headers with DECISIONS.md assumptions.
2. Phase 1: Settings → Test connection shows OK; one `dev-phase1-<ts>` note lands.
3. Phase 2: Bus mode 3 cards in airplane mode → reconnect → 3 study rows. Use a dev build: `flutter run --dart-define-from-file=../secrets.json --dart-define=DEV_IDS=true`.
4. Phase 3: same dev build, airplane mode → Quick log 5 `note` entries (any text the parser won't read, e.g. "dev check 1" … "dev check 5") → reconnect → exactly 5 `dev-` note rows appear once in Events. Delete them afterwards; the app drops them from cache on the next refresh.
5. Phase 4: GET `tabs=Daily Summary,Timeline,Spending`; compare the real headers with DECISIONS 21. Then open Week and Money for 11–17 Nov: expect 48 cigarettes and ₹10,617 incl. one-offs (PLAN risk 2). If a number differs, note which column; the adapter's patterns are one list per field.
