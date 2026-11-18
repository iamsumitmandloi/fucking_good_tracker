# PLAN v2: read-only viewer (Phase 7)

Brief: `handoff_v2/AGENT_PROMPT_v2.md`. Design: `handoff_v2/design/DESIGN_v2.md` + `handoff_v2/design/v2/*.dc.html`. Logging rules the data follows: `handoff_v2/LOGGING_AGENT.md`. CLAUDE.md rules still apply; on top: **no writes to the sheet at all in this phase**.

## 7.0 Recon (done 18 Nov)
- Live GET `tabs=Events`: 229 rows = 226 `bf-` + `test-1` + 2 app notes (uuid). Types: spend 62, note 29, cigarette 27, snack 18, supplement 16, tea 15, meal 13, bus_board/arrive 10/10, sleep 7, weight 7, steps 6, work 5, exercise 2, coffee 1, energy 1. Dates 11–17 Nov.
- `app/tool/export_events.dart` (GET only) wrote `app/fixtures/events_backfill.json` (gitignored by `fixtures/`).
- Every number in the brief's 7.2 table checked against the raw rows before writing code (they match; pairing and timed counts are sums of `qty`).

## Data rules (override the PRD)
- Source: Events only. Drop `test-` and `dev-` ids, apply `void`. `note` rows: lists only, never metrics.
- Money: only `type: spend` rows. Day-to-day = spend minus `bills`/`one_off`. Pay later = `source == lazypay`.
- Sleep: one row per night (`date`+`time` = bed, `end_time` = wake, `qty` = h). Bed ≥ 12:00 → wake is next day. Night belongs to its wake date.
- `time` empty = untimed: counted in totals, never drawn on a time axis.
- Averages: mean over days that have data. Missing ≠ 0 anywhere.
- Week = the 7 days ending today (IST). Tests pin the clock to 17 Nov.

## 7.1 Read-only switch
- `lib/core/feature_flags.dart`: `FeatureFlags.logging` (default `false`, `--dart-define=LOGGING=true` turns it on; tests may set it).
- Guards, all keyed on that one flag:
  - `EventsRepository.log` / `undo` throw `ReadOnlyError` when off (last line of defence).
  - `SyncService.flush` returns `blocked` when off; the outbox is kept, never sent.
  - Router: `/today`, `/study`, `/bus`, `/session` only exist when on. Quick log, FAB, tiles, Board button live only on Today/Study/Bus mode, so they are unreachable.
- Shell: off → Day · Week · Trends · Money · Insights. On → Today first, Study last (7 tabs).
- v1 Week/Money screens (legacy-merged) are replaced by v2 and removed; legacy adapter + repo stay, unused (Today still uses them when logging is on).
- Refresh: Events only (resume, reconnect, pull-to-refresh). Settings unchanged (Test connection still reads Start Here only when tapped).
- Gate test: walk all 5 tabs → no `+1`, no FAB, no Board button, no QuickLogSheet; `/today`, `/bus`, `/session` not routable; `log()` throws; a seeded outbox is not POSTed.

## 7.2 Derivations (`lib/domain/viewer/`, pure, unit-tested on the real fixture)
| file | functions |
|---|---|
| `viewer_events.dart` | `viewerEvents(all)` (effective − `test-`), `DayIndex` (events grouped by date) |
| `nights.dart` | `Night` (bed/wake date+min, hours, approx), `nights(events)`, `sleepByWakeDate(days)`, `bedtimeStats` (mean, population SD, after-midnight +1440), segments clipped to a calendar day |
| `metrics.dart` | per-day `cigs`, `cigsTimed`, `commute` (board/arrive paired in time order), `dayToDay`, `steps`, `weight` (reuse `weightWeek`), `hourHistogram`, `teaPairing`, `officeVsOff`, `oneOffs`, `categories`, `payLater`, `WeekMetrics` bundle |
| `day_view.dart` | `DayView` for the Day tab: KPIs vs 7-day averages, ribbon lanes (sleep, bus, smoke grouped by minute, food, money), untimed chips, chronological entries |
| `insights.dart` | `confidence()`, insight cards, week takeaways, coverage grid |

Tests assert the brief's table exactly (fixture-based, skipped with a clear message when the fixture is absent) plus small synthetic cases: untimed, voids, test ids, midnight-crossing sleep, missing days.

## 7.3 Screens (`lib/features/v2/`)
| tab | widgets |
|---|---|
| Day (`/day`) | ‹ › day switch, sync line (tap → Settings), 4 KPI tiles, `DayRibbon` (CustomPainter + hit-test → detail line), untimed chips, entries list |
| Week (`/week`) | 3 KPI tiles, `WeekRibbons` (7 compact ribbons + cigs/₹ column + "+N no time" badge), legend, 2 takeaways |
| Trends (`/trends`) | segmented Smoking / Sleep & body. Smoking: `BarsWithAverage`, `HourHistogram`, tea pairing, office vs off, cost. Sleep: `SleepWindows` + band, stats, weight dots on fixed axis, steps bars |
| Money (`/money`) | burn bars with ◆ one-off days, `RankedBars`, top-category sentence, pay later |
| Insights (`/insights`) | cards + `ConfidenceDots`, `CoverageGrid` |

Data colours as `SeriesColors` tokens (sleep #3987e5, smoke #d95926, food #199e70, money #c98500, bus #5D646E). Text never in series colours. Charts are CustomPainters/plain widgets (no new packages).
Gate: widget tests for ribbon tap → detail line and ‹ › switch; numbers on screen = 7.2 table; side-by-side review notes in PROGRESS.

## 7.4 Polish
Empty day / never-logged metric states, cache-first render (no spinner), pull-to-refresh on every tab, offline banner, release APK. Gate: analyze clean, tests green, APK built.
