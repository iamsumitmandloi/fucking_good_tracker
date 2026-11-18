# Starting Again

A personal Android/iOS app over the "Starting Again · Daily Life Tracker" Google Sheet. Since Phase 7 it is a **read-only viewer** of the sheet's Events tab: a logging agent writes the rows (rules in [`handoff_v2/LOGGING_AGENT.md`](handoff_v2/LOGGING_AGENT.md)), and the app shows what the days looked like. It works offline from its own cache and refreshes through an Apps Script web app.

- Current brief: [`handoff_v2/AGENT_PROMPT_v2.md`](handoff_v2/AGENT_PROMPT_v2.md), design [`handoff_v2/design/`](handoff_v2/design/), plan [`PLAN_v2.md`](PLAN_v2.md).
- Original requirements: [`handoff/PRD.md`](handoff/PRD.md). Design: [`handoff/design/`](handoff/design/).
- How it is built: [`PLAN.md`](PLAN.md). Why things are the way they are: [`DECISIONS.md`](DECISIONS.md). Where the build stands: [`PROGRESS.md`](PROGRESS.md).
- The Flutter app is in [`app/`](app/). The `fucking_good_tracker/` folder is an unused default project.

## What it does

| Tab | What you get |
|---|---|
| Day | KPIs vs your 7-day average (cigarettes, last night's sleep, day-to-day spend, commute), a 24-hour ribbon (tap a mark to see what and when), things logged without a time, the day's entries. ‹ › switches days. |
| Week | Seven day-ribbons stacked, weekly totals and two plain-language takeaways. Tap a row to open that day. |
| Trends | Smoking (daily bars, time of day, tea pairing, office vs off days, cost) and Sleep & body (sleep windows with your usual bedtime, weight on a fixed axis, steps). |
| Money | Day-to-day burn (bills and one-offs left out), where it went, pay later. |
| Insights | Pattern cards with confidence dots, and a grid of what's logged, partial or missing. |
| Settings | Sheet URL and token (secure storage, shown only as ••••), prices, sync log. Open it from the "synced from Events" line on Day. |

The app never writes to the sheet. Every write path from Phases 1–5 (Today's +1 tiles, Quick log, bus card, Study, Bus mode, undo, outbox) is still in the code behind one switch, `FeatureFlags.logging`, off by default (see "Logging build" below).

Every screen reads from the phone's database. The network only refreshes that cache from the Events tab (on app resume, when the connection comes back, and on pull-to-refresh).

## Setup

You need Flutter 3.50 stable or newer (Dart ≥ 3.13.7); check with `flutter --version`.

```sh
git clone https://github.com/iamsumitmandloi/fucking_good_tracker.git
cd fucking_good_tracker
cp secrets.example.json secrets.json     # then put the real values in it
cd app
flutter pub get
```

`secrets.json` holds `SHEET_URL` (the Apps Script `/exec` URL) and `SHEET_TOKEN`. It is gitignored. Never commit it, paste it, or screenshot it. You can also leave it with dummy values and enter the URL and token in the app under Settings.

The backend (`handoff/backend/Code.gs`) is set up once by the sheet owner; see PRD §7.

## Run

From `app/`:

```sh
flutter run --dart-define-from-file=../secrets.json
```

### Build flags

| Flag | Effect |
|---|---|
| `--dart-define=LOGGING=true` | Logging build: brings back Today (first tab), Study (last tab), Quick log, the bus card, Bus mode and the outbox. |
| `--dart-define=START_AT=/week` | Opens on another tab (`/day`, `/week`, `/trends`, `/trends?seg=sleep`, `/money`, `/insights`). |
| `--dart-define=TODAY=2026-11-17` | Pins "today" (23:00 IST) to compare the screens with the design files. Dev only. |

### Dev build (logging build, for checks against the live sheet)

```sh
flutter run --dart-define-from-file=../secrets.json --dart-define=LOGGING=true --dart-define=DEV_IDS=true
```

Every entry this build creates gets an id starting with `dev-`. Stats ignore those rows, so a check never pollutes your numbers. Today shows an orange "DEV IDS" tag so you can't mistake it for the real app. Delete the `dev-` rows from the Events tab afterwards; the app drops them from its cache on the next refresh.

## Test

From `app/`:

```sh
dart format .
flutter analyze        # must say "No issues found!"
flutter test           # all green
```

Tests never touch the network: a fake Apps Script server (`app/test/support/fake_sheet_server.dart`) stands in for the sheet, including the POST → 302 → GET dance.

### Check the numbers against the live sheet

```sh
cd app && dart run tool/live_check.dart            # week ending 2026-11-17
cd app && dart run tool/live_check.dart 2026-11-24 # any week
```

It only reads (GET) and prints totals: cigarettes, sleep, weight, burn, pay later, and data problems in the old tabs. The URL and token are read from `secrets.json` and never printed. (This checks the v1 legacy-merged numbers.)

To refresh the test fixture with the live Events tab (GET only; the file is gitignored because it is personal data):

```sh
cd app && dart run tool/export_events.dart   # → app/fixtures/events_backfill.json
```

The viewer tests (`test/domain/viewer_test.dart`, `test/features/viewer_widget_test.dart`) assert the Phase 7 table (11–17 Nov) on it, and skip with a message when it is missing.

## Install on a phone

**Android.** (Built on 18 Nov; accept the SDK licences once with `flutter doctor --android-licenses` on a new machine.)

```sh
flutter build apk --release --dart-define-from-file=../secrets.json
```

Copy `app/build/app/outputs/flutter-apk/app-release.apk` to the phone and open it (allow "install unknown apps" for your file manager), or run `flutter install` with the phone connected. The APK carries your sheet URL and token (seeded from `secrets.json`), so don't share it.

**iOS.** Open `app/ios/Runner.xcworkspace` in Xcode, pick your team under Signing & Capabilities, connect the iPhone and run. A free Apple ID build works for 7 days; TestFlight needs a paid account.

## Owner checks still open

The exact steps are under "Owner to verify" in [`PROGRESS.md`](PROGRESS.md):

1. In the sheet, type a header (e.g. "Value") in **Start Here!B1**. Until then the Up-next card can't see Current focus / Next action.
2. Settings → Test connection shows OK.
3. Bus mode offline → reconnect → one study row per card (logging dev build).
4. Quick log 5 notes offline → reconnect → exactly 5 rows, once (logging dev build).

Items 3–4 only matter if logging is switched back on.
