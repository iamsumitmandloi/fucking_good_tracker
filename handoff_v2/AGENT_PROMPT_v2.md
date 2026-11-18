# Starting Again: Phase 7 brief (read-only viewer)

Phases 0–5 are done. After using the app, I've changed direction. Read this whole file, then `design/DESIGN_v2.md`, the six files in `design/v2/`, and `LOGGING_AGENT.md`, before touching code. All the earlier rules in `CLAUDE.md` still apply: no git writes without asking me, `dart format` + `flutter analyze` (zero issues) + `flutter test` green after every change, update `PROGRESS.md`, record decisions in `DECISIONS.md`.

## What changed
1. **The app is now a read-only viewer.** Logging happens outside the app (an agent writes rows into the sheet using `LOGGING_AGENT.md`). No AI or LLM anywhere in the app.
2. **Don't delete the logging code.** Put every write path behind one flag, `FeatureFlags.logging = false`: tiles' +1 actions, quick log sheet and FAB, bus Board/Arrived button, Bus mode/Study writes, undo, outbox enqueueing. With the flag off, no screen can create, edit or void an event, and the Study tab is hidden. The flag must be the only switch needed to bring them back later.
3. **Events is the only data source.** I've already backfilled 11–17 Nov into Events (226 rows, ids `bf-2026-11-DD-NNN`), reconciled to Daily Summary: cigarettes, tea, spending and steps match on every day. Do **not** read Daily Summary, Timeline or Spending any more; remove them from the fetch and keep any legacy-parser code unused. **Never write to the sheet in this phase, not even `dev-` rows.**
4. **New semantics in Events (they override the PRD):**
   - **Money lives only on `type: spend` rows** (`amount_inr` + `category`). Consumption rows (cigarette, tea, meal…) carry no money. Total spend = sum of `amount_inr` over spend rows.
   - **Spend categories:** `tobacco, tea, food_out, groceries, quick_commerce, transport, personal_care, bills, one_off, other`. Day-to-day burn excludes `bills` and `one_off`. (`SPEND_CATEGORIES` in `backend/Code.gs` is outdated but not enforced. Leave the backend alone.)
   - **Sleep is one row per night:** `date` + `time` = bedtime, `end_time` = wake, `qty` = hours. A bedtime ≥ 12:00 means the night crosses midnight, and the wake date is the next day. A night belongs to its **wake date** ("slept the night before").
   - **`time` can be empty** (untimed entry). Count it in totals, but don't draw it on a time axis; it goes in "Logged without a time".
   - **Ignore** ids starting `test-`, rows of type `note` for metrics (show them only in lists), and apply `void` rows (label = id of the cancelled row).
   - All values arrive as strings; `approx` arrives as `"TRUE"`/`"FALSE"`.
5. **Fetch only `tabs=Events`** on refresh (rule 1 of the old brief still applies: cache-first in drift).

## Phase 7 steps (each ends with a gate you run yourself, then continue)
**7.0 Recon:** read everything listed above. Fetch Events live (GET only) and confirm 226 `bf-` rows plus my own app rows. Write `PLAN_v2.md`: screens → widgets → derivations → tests. Gate: plan written, live read OK.

**7.1 Read-only switch:** implement `FeatureFlags.logging` as above; the new 5-tab shell (Day, Week, Trends, Money, Insights) per the design; Settings unchanged. Gate: no write entry point reachable (add a widget test that walks every tab and finds no `+1`, FAB, Board button or quick-log route), analyze clean, tests green.

**7.2 Derivations:** pure functions in `domain/`, fully unit-tested with the real data (export the live Events JSON to `fixtures/events_backfill.json`, gitignored). Definitions:
- **Day:** calendar date, IST.
- **Cigarettes:** sum `qty` of cigarette rows per date. Timed share = rows with a time.
- **Tea pairing:** cigarette rows whose `(date, time)` equals a tea row's `(date, time)`.
- **Sleep:** hours = `qty`, else end − start across midnight. Bedtime spread = population SD of bedtime minutes (bedtimes after midnight count as +1440).
- **Commute:** pair `bus_board`/`bus_arrive` in time order per date; office day = ≥ 1 leg.
- **Averages:** mean over days that **have** data; missing days are skipped, never zero.
- **Insight confidence:** 1 dot if the smaller group has < 5 days; 2 if < 10; 3 for direct counts or ≥ 10 days; 4–5 reserved for ≥ 21 days with a consistent direction.

Expected values for 11–17 Nov (tests must assert these):

| metric | expected |
|---|---|
| cigarettes per day | 13, 5, 11, 6, 5, 4, 6 (total 50, avg 7.14); timed 17 |
| tea pairing | 8 of 17 timed |
| office vs off days | 7.8 vs 5.5 cigarettes a day |
| sleep by wake date | 6, 7.6, 6, 6, 6.1, 6, 7.5 h (avg 6.46); mean bedtime ≈ 00:43; spread ≈ 99 min; 2 nights ≥ 7 h |
| commute (min) | 150, 145, 140, —, —, 175, 170 (office-day avg 156) |
| day-to-day ₹ | 1654, 225, 1010, 1467.14, 1583, 515, 404 (total 6,858.14, avg ≈ 980) |
| one-offs | 2,347.51 (Thu, one_off) + 1,537.14 (Sun, bills) |
| categories (day-to-day) | quick_commerce 4,134 · food_out 1,553.14 · tobacco 716 · transport 195 · groceries 100 · tea 80 · personal_care 80 |
| pay later (`source` lazypay) | 1,821.14 |
| weight | avg 88.12 kg (7 days) |
| steps | avg 9,779 (6 days; Sat missing) |

If any number differs, find out why before changing a test, and tell me if the data, not the code, is wrong.

**7.3 Screens:** build Day (interactive ribbon + ‹ › day switch), Week ribbons, Trends (Smoking | Sleep & body segmented), Money, Insights, matching `design/v2/` and `DESIGN_v2.md` closely. Ribbons, sleep windows and the histogram: CustomPainter with hit-testing. Bars may use fl_chart if they match the design. Gate: side-by-side review of every screen against its design file in `PROGRESS.md`; widget tests for the Day ribbon tap → detail line and the day switcher; numbers on screen equal the 7.2 table.

**7.4 Polish:** empty and partial states (a day with no events, a metric never logged), loading from cache with no spinner, pull-to-refresh, offline banner. Release APK builds. Gate: analyze clean, all tests green, APK built.

## Stop only for
Needing secrets, any git operation, a contradiction between this brief and the data that you can't settle with evidence, or the end of 7.4. Then report: what's done, how to run, test count, anything unverified.

## Start now
Begin 7.0.
