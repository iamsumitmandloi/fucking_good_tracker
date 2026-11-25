# PLAN: Starting Again

Source of truth: `handoff/PRD.md`, `handoff/design/`. Build brief rules: `CLAUDE.md`. Status: `PROGRESS.md`.
Decisions with evidence: `DECISIONS.md`.

## 1. File tree (`app/lib`)

```
app/lib/
  main.dart                      bootstrap: open db, read config, start SyncService, runApp
  app/
    app.dart                     MaterialApp.router, dark theme, RepositoryProviders
    router.dart                  go_router: StatefulShellRoute (Today/Study/Week/Money) + /bus, /settings; Quick log = modal sheet
    theme/
      app_colors.dart            ThemeExtension<AppColors> (DESIGN.md colour table)
      app_text.dart              ThemeExtension<AppText> (Space Grotesk display/numbers, Inter body)
      app_dims.dart              spacing (screen 18, gap 10/12), radii (18/20/28, chip 8-12, pill 18-20), minTouch 44
      app_theme.dart             ThemeData.dark wired to the extensions
    widgets/                     shared: AppCard, StatCard, QuickTile, PillButton, SyncDot, EmptyState, OfflineBanner, icons
  core/
    result.dart                  sealed Result<T> / Failure (network, timeout, unauthorised, server(msg), parse)
    clock.dart                   Clock interface (now in IST) + fixed clock for tests
    ids.dart                     uuid v4; isDevId(id) => id.startsWith('dev-')
    formatters.dart              ₹ (intl en_IN), 1h 20m, HH:mm, "—" for null
    cells.dart                   string-cell parsing: num?, bool ("TRUE"/"FALSE"), date, HH:mm
  data/
    remote/
      sheet_config.dart          URL + token: dart-define seed -> flutter_secure_storage; masked token
      sheet_api.dart             fetchTabs(List<String>), postEvents(List<Event>); 302 -> GET Location; 20 s timeout
      dto.dart                   TabsResponse, PostResponse (added/skipped)
    local/
      db.dart                    drift AppDatabase: events, outbox, study_bank, start_here, legacy_rows, meta
      daos/                      events_dao, outbox_dao, study_dao, meta_dao
    repo/
      events_repository.dart     watch(range), log(events), undo(id), refresh() (Events tab)
      study_repository.dart      watchBank(), watchStartHere(), refresh() (Study Bank + Start Here)
      legacy_repository.dart     refresh() (Daily Summary, Timeline, Spending) -> legacy_rows; adapter output
      settings_repository.dart   target date, cig budget/price, tea price, supplements, protein target, bus run size
    sync/
      sync_service.dart          flush outbox; triggers: resume, connectivity regained, pull-to-refresh, 10 s debounce
      backoff.dart               2^n s, cap 300 s, reset on success
  domain/
    event.dart                   Event model + toJson/fromSheetRow (strings in, typed out)
    event_type.dart              enum mirroring Code.gs EVENT_TYPES
    effective_events.dart        drop dev- ids, void events and their targets
    derivations/
      daily_stats.dart           counts per type per date, spend per date
      commute.dart               bus legs from board/arrive pairs
      sleep.dart                 sleep windows (bed -> next wake, across midnight)
      burn.dart                  daily burn, split, pay later
      weight.dart                dots + 7-day avg + fixed >= 4 kg axis
      study_progress.dart        assessed, tier counts, sessions, T1 pace, countdown
      leitner.dart               due date per question; bus queue
    quicklog/
      parser.dart                regex grammar -> List<ParsedEntry>; unparsed -> note
    legacy/
      legacy_cell.dart           "~6–6.25 h" etc -> (value?, approx, raw); never throws
      legacy_adapter.dart        legacy rows -> synthetic read-only Events (source 'legacy', approx flags, data-bug flags)
    study_question.dart          Study Bank row model (follow-ups / answer points split on ';')
  features/
    today/      today_cubit.dart, today_screen.dart, widgets/ (tiles, bus card, up-next, sleep/spend cards, undo line)
    quicklog/   quicklog_cubit.dart, quicklog_sheet.dart
    study/      study_cubit.dart, study_screen.dart, session_timer.dart
    busmode/    busmode_cubit.dart, busmode_screen.dart, summary_view.dart
    week/       week_cubit.dart, week_screen.dart, charts/ (CustomPainter: bars, sleep rows, weight dots)
    money/      money_cubit.dart, money_screen.dart, stacked_bar.dart
    settings/   settings_cubit.dart, settings_screen.dart
app/test/   mirrors lib/ (unit + widget); fixtures built in Dart, real-data fixtures read from ../fixtures only when present
```

## 2. Data flow

```
          ┌──────────── UI (cubits) ────────────┐
          │ reads: drift streams only            │ writes: repo.log(...)
          ▼                                      ▼
   EventsRepository.watch*()          drift transaction: insert events(sync=pending) + outbox row
          ▲                                      │
          │ upsert server rows                   ▼ schedule flush (10 s debounce)
   refresh(): SheetApi.fetchTabs([needed])   SyncService.flush(): outbox batch -> SheetApi.postEvents
          ▲                                      │  ok: ids in added ∪ skipped -> delete outbox row, mark event synced
          │                                      │  network/timeout: keep, backoff 2^n (cap 5 min)
   Apps Script /exec  ◄──────────────────────────┘  ok:false: keep, store error in meta; unauthorised = stop until Settings change
```

- Cold start: UI subscribes to drift; cached rows render on first frame. Refresh runs after first frame, never blocks.
- Each screen asks only for its tabs: Today/Week/Money → `Events` (+ legacy tabs on Week/Money, cached once and refreshed rarely); Study/Bus → `Study Bank,Start Here,Events`.
- Refresh merges: server rows replace local rows with the same id and `sync=synced`; local `pending` rows are never overwritten. Synced local rows missing on the server (e.g. a deleted `dev-` row) are removed.
- Undo: event still in outbox → delete event + outbox row. Already synced → log `void` (label = target id).
- Stats always run on `effectiveEvents`: no `dev-` ids, no `void` events, no voided targets.

## 3. Derived metrics

| Metric | Computation |
|---|---|
| Cig count today | Σ qty of `cigarette` for today (qty empty → 1). Warn colour when > budget (Settings, default 5). |
| Tea / water / protein | Σ `tea` qty; Σ `water_ml` qty (shown in L, "—" if no event); `meal`/`snack` with unit `g` (case-insensitive) for breakfast protein, "—" if none. |
| Steps | `max` of `steps` qty for today (matching sheet `MAXIFS`). |
| Supplements x/N | normalised distinct `supplement` labels today ∩ Settings list (default 4 from Supplement Reference). |
| Bus legs | today's `bus_board`/`bus_arrive` sorted by time; each board pairs with the next arrive. Leg = arrive − board (across midnight if negative +24 h). Last event board → state Riding (CTA "Arrived"); 1 completed leg → CTA "Board home"; 2 → "Done" (disabled). Total = Σ completed legs. |
| Sleep window | per `sleep` event (time = bedtime, date = calendar date of bedtime) → first `wake` after it within 18 h, or `sleep.end_time` fallback (`wakeDate = date` if `end_time >= bed`, else `+1 day`). Row labelled by wake date. Approx if either approx. Orange when bedtime ≥ 02:00 and < 12:00. |
| Spent today | Σ `amount_inr` of today's events (app writes a separate `spend` row per payment per sheet rule). |
| Daily burn | Σ amount where category ∉ {bills, one_off} ÷ days in range (7). Split: delivery (`food_delivery`, `quick_commerce`, `delivery`) / everything else / one-offs (`bills` + `one_off`). |
| Pay later | Σ amount where source = `lazypay` in range. |
| Weight | dots per day (last weight that day); 7-day avg = mean of days that have a value; axis = [floor(min)-…] widened to ≥ 4 kg span, centred on the avg. |
| Not logged | per metric: days in range with ≥ 1 event / 7, orange when 0. |
| Assessed | distinct `study` labels with note ∈ {blank, shaky, nailed} that exist in Study Bank. |
| Tier counts | assessed ∩ Tier N / total Tier N. |
| Sessions | count of `study` events with note = `session`. |
| T1 pace | ceil(remaining T1 / days left); days left = target − today (target from Settings, default 2026-11-30). "—" when days left ≤ 0. |
| Leitner | per question, rating events in time order. Blank/Shaky → due = rating date + 1, streak = 0. Nailed → streak += 1; due = date + 4 (streak 1) or + 10 (streak ≥ 2). |
| Bus queue | Tier-1 questions with due ≤ today. Order: never-seen first (Study Bank row order), then most overdue first, ties by row order. A run takes the first N (Settings, default 10). |
| Legacy | `legacy_cell.parse`: first number; range → midpoint; `~` or range → approx; N/A / text → null + raw kept. |

## 4. Risks

1. **Legacy tabs superseded by `Events` backfill.** `Events` now holds 453 rows across `2026-11-11`–`2026-11-24`, and `Today` row 17 states `Daily Summary`, `Timeline`, and `Spending` are historical snapshots. Risk of missing 11–17 Nov data is resolved.
2. **Sheet formula parity:** `Today` & `Daily Review` sum `amount_inr` only where `type = "spend"`. Mitigation: app writes `spend` rows separately from activity rows ("One event for each activity. One spend event for each payment.").
3. **Apps Script latency 1–3 s and occasional HTML error pages** (non-JSON 200). Mitigation: parse failure → typed `Failure.server`, outbox keeps rows.
4. **Clock/timezone**: device may not be IST. Mitigation: `Clock` converts to Asia/Kolkata (+05:30 fixed, no DST) for `date`/`time`.
5. **Study Bank size (501 rows)** on every Study open. Mitigation: cache in drift; refresh only on pull or when older than 6 h.
6. **Duplicate posts after a timeout** (server wrote, reply lost). Mitigation: idempotent by id; `skipped` counts as success.
7. **Home widget (Phase 6)** writes from a background isolate. Mitigation: widget callback writes to drift outbox via the same repository; verify on Android first.
