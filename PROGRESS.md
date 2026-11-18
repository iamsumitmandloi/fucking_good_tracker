# PROGRESS

**Current phase:** 7 (read-only viewer, `handoff_v2/`) **done, 7.0–7.4**. Phase 6 dropped by the owner (18 Nov). Phases 0–5 done.
**Last update:** 2026-11-18 IST
**Mode:** real `secrets.json` (owner, 17 Nov). Phase 7 makes no writes to the sheet at all; every live call in it was a GET of `tabs=Events`.
**Plan:** `PLAN_v2.md`. Brief: `handoff_v2/AGENT_PROMPT_v2.md` (copied into the repo from the owner's Downloads).

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

## Phase 5: Polish + release ✅ (release APK built in Phase 7.4)
- Widget tests added: Settings (token never shown, Test connection reads only Start Here, Save keeps the token, wrong token), Today Up-next → Bus mode
- "DEV IDS" tag on Today in `DEV_IDS` builds
- Android: INTERNET permission in the main manifest (release builds had none), label "Starting Again", Android Gradle Plugin 9.1.0 → 9.1.1 (Flutter 3.50 minimum). `flutter build apk --release` failed on the old AGP; not re-run (owner: `flutter doctor --android-licenses`, install SDK cmdline-tools, then build)
- iOS: builds and runs on the iPhone 17 simulator via Swift Package Manager (no CocoaPods). Visual fixes from screenshots: grey dot before the first sync, shorter tile captions, undo line only 44 tall while Undo shows. The Simulator window app is missing from this Mac's Xcode (open it via Xcode → Open Developer Tool → Simulator, or install it under Xcode → Settings → Components)
- Live sheet (real secrets.json, 17 Nov): headers recorded (DECISIONS "Live API headers"); legacy adapter re-fit to them (DECISIONS 32–33); numbers verified with `app/tool/live_check.dart` (DECISIONS 34); Start Here B1 issue found (DECISIONS 35)
- README at the repo root
- Tests: 196 green, analyzer clean

Phase 6 (below) was dropped on 18 Nov in favour of Phase 7. Kept for reference:
1. Home-screen widget (`home_widget`, named in the PRD): +1 cig, +1 tea, bus button; writes through the same drift outbox. Android first; iOS needs a WidgetKit extension + App Group (owner signs in Xcode).
2. 21:00 nudge when no study event today: needs a notifications package not named in the PRD (likely `flutter_local_notifications`) → ask the owner before adding (CLAUDE.md rule 6). Android 13+ needs POST_NOTIFICATIONS.
3. Final report.

Known gotcha: widget tests must settle the fake-async zone before closing drift (see `test/support/app_harness.dart` `dispose`), or the run hangs. Keep widget tests in their own files (no shared drift setUp/tearDown with plain tests).

## Phase 7: read-only viewer ✅ (18 Nov)
### 7.0 Recon ✅
- Read the brief, DESIGN_v2, the six design files, LOGGING_AGENT.md. `PLAN_v2.md` written.
- Live GET `tabs=Events`: 229 rows = **226 `bf-`** + `test-1` + 2 owner app notes. `app/tool/export_events.dart` → `app/fixtures/events_backfill.json` (gitignored).
- Every number in the brief's table checked against the raw rows first: all match.

### 7.1 Read-only switch ✅
- `FeatureFlags.logging` (default off; `--dart-define=LOGGING=true`), guards in `EventsRepository.log/undo` and `SyncService.flush`, router without write routes (DECISIONS 38).
- Shell: Day · Week · Trends · Money · Insights (Settings unchanged, reached from the Day sync line). Fetch: Events only.
- Gate ✅ `test/features/viewer_widget_test.dart`: walks all 5 tabs (and Trends › Sleep & body, and a long-press) → no tile, `+1`, FAB, Board/Arrived, Quick log or Undo; `/today`, `/study`, `/bus`, `/session` don't open; `log()`/`undo()` throw; a queued outbox row is not POSTed (0 posts) and refresh asks only for `Events`. v1 write-path tests run with the flag on.

### 7.2 Derivations ✅
- `lib/domain/viewer/`: `viewer_events.dart`, `nights.dart`, `metrics.dart` (`WeekMetrics`), `day_view.dart`, `insights.dart`.
- `test/domain/viewer_test.dart` (21 tests): the brief's table, asserted on the live backfill: cigarettes 13 5 11 6 5 4 6 (50, 7.14, 17 timed) · pairing 8/17 · office 7.8 vs off 5.5 · sleep 6 7.6 6 6 6.1 6 7.5 (6.46, mean bed 00:43, spread 99 min, 2 nights ≥ 7 h) · commute 150 145 140 — — 175 170 (156) · day-to-day 1654 225 1010 1467.14 1583 515 404 (6,858.14, ≈ 980) · one-offs 2,347.51 Thu one_off + 1,537.14 Sun bills · categories exactly as the table · pay later 1,821.14 · weight 88.12 · steps 9,779 (6 days). Plus synthetic cases: test/dev ids, voids, missing days, untimed, midnight-crossing sleep, bus pairing, money-only-on-spend, notes, confidence.
- No number differed from the brief; no data problem found.

### 7.3 Screens ✅
- `lib/features/viewer/`: `viewer_cubit.dart` (one drift stream for all tabs), `day/`, `week/`, `trends/`, `money/`, `insights/`, `widgets/` (`DayRibbon` CustomPainter with hit-testing and per-mark semantics, mini ribbons, `BarsWithAverage`, `HourHistogram`, `SleepWindows` with the bedtime band, weight dots, steps bars, `RankedBars`, `ConfidenceDots`, `CoverageGrid`). Data colours: `SeriesColors` ThemeExtension.
- Widget tests: ribbon tap → detail line (smoke, bus, ₹, sleep); ‹ › day switch (› stops at today, ‹ at the first day with data) and Week row → Day; on-screen numbers on every tab = the 7.2 table.
- **Side-by-side review** (iPhone 17 simulator, live Events, `--dart-define=TODAY=2026-11-17`, screenshots in the session scratchpad):
  - Day: matches V2Day: KPIs read 6 / ▼ 1.1 vs 7-day avg 7.1 · ~7.5 h / ▲ 1.0 h vs avg 6.5 · ₹404 / ₹576 under avg ₹980 · 2h 50m / ▲ 14 min. Ribbon lanes, untimed chips and the entry list as designed. The list also shows timed notes (brief: notes in lists).
  - Week: matches V2Week (header, 3 tiles, 7 ribbons with "+N no time" badges, legend, both takeaways word for word). Rows are 44 px (design 40) for touch targets.
  - Trends › Smoking: matches V2Smoking (bars + avg, histogram, "Peaks at 14:00 and 16:00", 8 of 17 / 47 %, 7.8 vs 5.5, ≈ ₹1,250 / week, ₹5,350 a month). Avg tag moved into a right gutter (it covered Tuesday's label). Cost sentence says "inside delivery orders or isn't logged" instead of naming Zepto/Blinkit.
  - Trends › Sleep & body: matches V2Sleep (windows + band 23:04–03:22, 6.5 h, ±1h 39m, 2 of 7, sentence, weight 88.1 on 86–90, steps 9.8k, "Sat not logged. Sun 2,096, the low.").
  - Money: matches V2Money (₹980/day, ₹6,858 + ₹3,885 one-offs, ◆ on Thu/Sun, ranked categories, "Delivery apps are 60% of it. 6 orders, ₹2,442 of them on Sat–Sun.", LazyPay ₹1,821 · 3 charges). One-offs are named from the data ("Developer registration fee", "Electricity bill"); merchants read "Zepto, Blink, Zomato".
  - Insights: matches V2Insights (4 cards with 3/1/1/1 dots, coverage grid). Sunday card says "₹1,583 spent" (the design's "on delivery apps" includes a ₹10 drink).
  - Today (real clock, 18 Nov) shows "Nothing logged yet today" until the agent logs something.

### 7.4 Polish ✅
- Empty and partial states: empty day card; "not logged" / "—" / dim stubs everywhere a metric is missing (widget test: an empty week shows no `0` and no `₹0`).
- Cache-first: every tab renders from drift; nothing waits on the network, no spinner. Pull-to-refresh on every tab (Events only). Offline banner on every tab; read-only builds no longer promise "will sync".
- `flutter build apk --release --dart-define-from-file=../secrets.json` ✅ `app/build/app/outputs/flutter-apk/app-release.apk` (60.7 MB). Warnings only: Gradle 9.3.1, AGP 9.1.1 and Kotlin 2.4.10 will need upgrading soon.
- Gate ✅ `dart format` clean, `flutter analyze` no issues, **223 tests green** (196 + 21 domain + 6 widget).

### Not verified
- The APK was built, not installed on a phone (no Android device or emulator here).
- iOS: simulator only.

## Dev rows written to the live sheet
None by the agent (all live calls were GETs).
Not a dev row: `2c412a10-…` cigarette ₹25, 17 Nov 22:35, written by the owner tapping the Cig tile in the simulator (normal build). Delete it in the sheet if it was only a test.

## Owner to verify (live)
1. ~~Phase 0 headers~~ done 17 Nov (DECISIONS "Live API headers"). **Action:** type a header (e.g. "Value") in Start Here!B1 so Current focus / Next action reach the app (DECISIONS 35).
2. Phase 1: Settings → Test connection shows OK. (The live write path is already proven: the simulator cigarette landed in Events.)
3. Phase 2: Bus mode 3 cards in airplane mode → reconnect → 3 study rows. Use a dev build: `flutter run --dart-define-from-file=../secrets.json --dart-define=DEV_IDS=true`.
4. Phase 3: same dev build, airplane mode → Quick log 5 `note` entries (e.g. "dev check 1" … "dev check 5") → reconnect → exactly 5 `dev-` note rows, once. Delete them afterwards.
5. ~~Phase 4 numbers~~ verified 17 Nov with `cd app && dart run tool/live_check.dart` (DECISIONS 34). Re-run it any time; it only reads.
