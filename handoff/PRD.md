# PRD: Starting Again (Flutter app over a Google Sheet)

Owner: Sumit · Date: 17 Nov 2026 · Status: ready to build

## 1. What and why
A personal Android/iOS app that **reads from and writes to** the "Starting Again · Daily Life Tracker" Google Sheet. Today, logging means texting a chatbot ("1 cig", "office reached 10:40") and reading a slow, desktop-first website. The app makes logging one tap, shows the day and week with real hierarchy, and puts interview study (501-question Study Bank, target 30 Nov 2026) on the home screen, including a flash-card **Bus mode** for the ~2–3 h daily commute.

Success after 2 weeks of use:
- ≥ 90% of cigarettes, teas, meals and bus legs are logged in the app, not in chat.
- ≥ 1 study entry (session or Bus mode run) logged on ≥ 5 of 7 days.
- The app opens to usable content in < 1 s from cache, even offline.

Single user. No accounts, no multi-tenant, no Play Store/App Store release needed (side-load or TestFlight is fine).

## 2. Feasibility: verified 17 Nov 2026

| Question | Answer | Status |
|---|---|---|
| Can the app read the sheet? | Yes. An Apps Script web app's `doGet` returns JSON via `ContentService` (`backend/Code.gs`). | Verified (Apps Script docs) |
| Can the app write to the sheet? | Yes. `doPost` appends rows; deployed "Execute as: Me", so it writes with the owner's access. | Verified (docs + community) |
| Does POST behave normally? | **No.** Apps Script answers every POST with a **302**. `doPost` has already run by then; the JSON reply sits at the `Location` URL, which must be fetched with **GET**. | Verified |
| Does Flutter handle that 302? | **Not automatically.** dart:io follows 302 only for GET/HEAD. `http.post` returns the 302 response; read `location`, then `http.get` it. With Dio, set `followRedirects: false` and `validateStatus: s < 400`. | Verified (dart:io docs) |
| Auth headers? | The `doGet`/`doPost` event object lists no request headers (queryString, parameter(s), pathInfo, contentLength, postData only). The token therefore goes in the query (GET) or the JSON body (POST). | Verified (docs field list) |
| Reserved query names | `c` and `sid` are reserved and can cause HTTP 405. Never use them as params. | Verified (docs) |
| Code changes | Editing code does not update the live `/exec`. Use Deploy → Manage deployments → Edit → **New version**, which keeps the same URL. "New deployment" creates a **new URL**. | Verified (multiple sources) |
| Limits | Consumer account: 6 min per execution, 30 simultaneous executions per user. Far above a single user's needs. | Verified (quotas page) |
| Why not the Sheets API directly? | The `spreadsheets` scope is "sensitive"; an unverified app in Testing mode gets refresh tokens that expire after **7 days**, meaning weekly re-login. | Verified |
| Why not "publish to web" CSV? | It makes health data and card last-4s public. | Rejected |
| Flutter web build | Out of scope; browser CORS behaviour against Apps Script was not verified. Android/iOS only. | Not verified, avoided |
| Latency | Apps Script calls can take 1–3 s cold. Mitigated by the local cache and outbox. | **Not verified (common reports)** |
| Packages | drift 2.35.4 (8 Nov 2026), fl_chart 1.3.1 (9 Nov 2026), home_widget 0.10.0 (Sep 2026), flutter_bloc 9.1.1 (May 2025). All on pub.dev. | Verified |

**Verdict: feasible; no blockers.** The only non-obvious work is the 302 dance and the offline outbox.

## 3. Scope

### P0 (v1, must ship)
1. **Today**: quick tiles (cigarette, tea, water +250 ml, meal, supplements checklist, breakfast protein g), bus Board/Arrived button, Up-next study card, sleep summary, today's spend. Undo on every log.
2. **Quick log sheet**: free text ("1 cig + tea 45", "lunch 130", "weight 87.9", "slept 22:30") parsed **locally** (a regex grammar, no LLM) into a preview of events; time chips (Now / 15 min ago / Approx / pick); "Repeat a usual" chips built from the 5 most frequent labels in the last 14 days.
3. **Study tab**: countdown to target date, assessed x/501, tier counts, current focus from the `Start Here` tab, Start 25-min session (timer), then logs a `study` event.
4. **Bus mode**: Tier-1 cards from `Study Bank`; reveal answer points; rate Blank/Shaky/Nailed; writes one `study` event per card; simple Leitner (Blank/Shaky → due tomorrow, Nailed → +4 days, Nailed twice → +10 days), computed from events.
5. **Week tab**: cigarettes per day (bars), sleep windows, weight dots + 7-day average (fixed axis span ≥ 4 kg), "Not logged" counts.
6. **Money tab**: daily burn excluding `bills` and `one_off`, stacked split, pay-later total, today's entries.
7. **Offline-first**: local DB cache, outbox, sync on app resume, connectivity change, pull-to-refresh, and 10 s after the last local write.
8. **Settings**: Web-app URL and token (secure storage), target date, cigarette daily budget, supplement list, sync status/log.

### P1 (v1.1)
- Home-screen widget (home_widget): "+1 cig", "+1 tea", bus button.
- Read-only import of legacy tabs (`Daily Summary`, `Timeline`, `Spending`) for weeks before Events existed (§6.4).
- Notifications: evening nudge if no study event by 21:00.

### Out of scope
Flutter web, multi-user, LLM parsing, editing legacy rows, charts beyond the 4 listed, light theme.

## 4. Screens and acceptance criteria
Design source: `design/screens/*.dc.html`, tokens in `design/DESIGN.md`.

**Today**
- Cold start shows cached data instantly; a "Synced HH:MM" dot is lime when the outbox is empty, orange with a count when not.
- Tapping the Cig tile adds a `cigarette` event (qty 1, amount from Settings, default 25, category `tobacco`), increments the tile optimistically and shows an undo line for 6 s. Undo before sync removes it from the outbox; after sync it posts a `void` event.
- The Cig number turns `warn` when above the daily budget.
- The bus button cycles: no legs today → "Board" → (`bus_board`) → "Arrived" → (`bus_arrive`). Duration = arrive − board. Second leg same day = return trip. The card shows the last leg and today's total.
- The Up-next card reads `Start Here` → "Current focus" and "Next action".

**Quick log**: the parser covers at least: `N cig`, `tea`, `coffee`, `water N ml|L`, `lunch|breakfast|dinner|snack <text> <amount>`, `<amount>` alone = spend, `weight N`, `slept HH:MM`, `woke HH:MM`, `+` separated combos. Anything unparsed becomes a `note` event. The preview must show every event before the user confirms.

**Study**: assessed = distinct question ids with ≥ 1 `study` rating event. T1 pace = ceil(remaining T1 / days left).

**Bus mode**: works fully offline from cache. Exit mid-run keeps rated cards. The summary shows counts and writes nothing extra (each card was already its own event).

**Week**: a missing day renders as a gap, never 0. Sleep = from a `sleep` event (time = bedtime) to the next `wake` event; mark approx if either is approx.

**Money**: daily burn = sum(spend where category ∉ {bills, one_off}) / days in range. Pay later = spend where `source` = `lazypay`.

## 5. Architecture
```
lib/
  app/            router (go_router), theme (tokens from DESIGN.md), DI
  core/           result types, clock, id (uuid v4), formatters (₹, durations)
  data/
    remote/       SheetApi (GET tabs, POST events with the 302 handling)
    local/        drift db: events, outbox, study_bank, start_here, meta(lastSync)
    repo/         EventsRepository, StudyRepository (cache-first, then refresh)
    sync/         SyncService (outbox flush, backoff 2^n up to 5 min, idempotent by id)
  domain/         Event model, EventType enum, derivations (daily stats, sleep, commute, burn, leitner)
  features/
    today/ quicklog/ study/ busmode/ week/ money/ settings/   (bloc/cubit per feature)
```
- State: flutter_bloc (cubits are fine).
- Packages: `http`, `drift` + `drift_flutter`, `flutter_secure_storage`, `connectivity_plus`, `uuid`, `fl_chart` (or CustomPainter), `google_fonts`, `go_router`, `intl`. Resolve versions with `flutter pub add`; don't pin from memory.
- Config: URL and token are entered in Settings (secure storage). Optionally seed with `--dart-define=SHEET_URL=… --dart-define=SHEET_TOKEN=…`. **Never commit them.**
- Timezone: all `date`/`time` fields are Asia/Kolkata local strings (`yyyy-MM-dd`, `HH:mm`); `created_at` is UTC ISO.

### 5.1 SheetApi contract
```
GET  {url}?token=T                      -> {ok, generatedAt, tabs: {TabName: [ {_row, <header>: <display string>} ]}}
GET  {url}?token=T&tabs=Events,Study%20Bank
POST {url}  body {"token":T,"events":[Event...]}  (Content-Type: text/plain or application/json)
     -> 302 Location: https://script.googleusercontent.com/macros/echo?...
     -> GET Location -> {ok, added:[ids], skipped:[ids]}
```
Errors come back as HTTP 200 with `{ok:false, error}`. Treat `ok:false` as failure. Retry only on network errors or timeouts (20 s). An id in `skipped` that already exists on the server counts as success (idempotent).

Reference Dart for the POST:
```dart
final res = await client.post(url, headers: {'Content-Type': 'text/plain'}, body: jsonEncode(body));
final http.Response reply;
if (res.statusCode == 302 || res.statusCode == 303) {
  reply = await client.get(Uri.parse(res.headers['location']!));
} else {
  reply = res;
}
final json = jsonDecode(reply.body) as Map<String, dynamic>;
```

## 6. Data model

### 6.1 `Events` tab (single source of truth; created by `setupEventsTab()`)
| col | type | notes |
|---|---|---|
| id | uuid v4 | client-generated; dedupe key |
| date | `yyyy-MM-dd` | IST |
| time | `HH:mm` | IST; empty if unknown |
| end_time | `HH:mm` | for ranges (sleep, study) |
| type | enum | see 6.2 |
| qty | number | count, minutes, kg, ml, steps, g protein |
| unit | text | `cig`, `cup`, `ml`, `kg`, `min`, `g`, `steps` |
| label | text | free label, or the question id for `study`, or the target id for `void` |
| amount_inr | number | money spent, if any |
| category | enum | spend category (see Code.gs `SPEND_CATEGORIES`) |
| approx | bool | true when time or value is approximate |
| source | text | `app`, `chat`, `bank`, `lazypay`, `gmail` |
| note | text | free text; `study` rating = `blank|shaky|nailed` |
| created_at | ISO UTC | server-set |

Numbers only in number columns. "~" never goes in a cell; set `approx` instead.

### 6.2 Event types
`sleep` (time = bedtime), `wake`, `weight` (qty kg), `cigarette` (qty), `tea`, `coffee`, `water_ml` (qty ml), `meal`, `snack`, `supplement` (label = name), `bus_board`, `bus_arrive`, `exercise` (qty min, label), `steps` (qty), `work` (note), `study` (label = question id, qty = minutes, note = rating or "session"), `spend` (pure money with no habit), `energy`/`mood` (qty 1–10), `note`, `void`.

A habit event that cost money carries `amount_inr` and `category` on itself (a cigarette with ₹25). Never also add a separate `spend` row: one payment, one record.

### 6.3 Read-only tabs used
- `Study Bank`: Question ID, Source tab, Topic, Area, Tier, Type, Stars, Question, Follow-ups (`;` separated), Answer points / rubric (`;` separated), Project, Related question, Status.
- `Start Here`: two-column key/value (Current focus, Next action, Where to resume, Target date…).

### 6.4 Legacy import (P1)
`Daily Summary` cells hold text like `~7.5 (inferred…)`, `~6–6.25 h`, `N/A — weekend`. The parser takes the first number, takes the midpoint of ranges, sets approx when `~` or a range appears, and treats `N/A`/text as missing. Known data bugs to surface in the UI, not fix silently: 16 Nov commute is 90 in the column but 175 in Work text; 16 Nov steps (12,576) sit in Exercise text.

## 7. Backend setup (owner does this once, ~20 min)
1. Open the sheet → Extensions → Apps Script → paste `backend/Code.gs`.
2. Project Settings → Script properties → `TOKEN` = a 32+ char random string. Project Settings → time zone = Asia/Kolkata.
3. Run `setupEventsTab()` once and authorise.
4. Deploy → New deployment → Web app → Execute as **Me**, Who has access **Anyone** → copy the `/exec` URL.
5. Test: open `{url}?token=…&tabs=Start%20Here` in a browser and expect JSON. Then `curl -L -d '{"token":"…","events":[{"id":"test-1","date":"2026-11-17","type":"note","note":"hello"}]}' "{url}"`; expect `added:["test-1"]` and a new row.
6. Later code edits: Manage deployments → Edit → New version (same URL).

Security note: anyone with URL + token can read and write the sheet. Keep both out of git and screenshots. To rotate, change `TOKEN` in Script properties.

## 8. Testing
- Unit: quick-log parser (≥ 30 cases from the real phrases in `Timeline`), derivations (sleep across midnight, two bus legs, burn excluding bills/one_off, Leitner due dates), legacy cell parser.
- Repository: a fake SheetApi verifies the 302 path, `ok:false`, timeout and retry, idempotent re-send.
- Widget: Today tile tap → optimistic count + outbox row; Bus mode reveal → rate → next.
- Manual: airplane mode → log 5 things → reconnect → all 5 rows appear once in the sheet.

## 9. Milestones (real estimates, one dev plus an agent)
| # | Deliverable | Time |
|---|---|---|
| M0 | Backend deployed and curl-tested | 20 min |
| M1 | Project skeleton, theme tokens, SheetApi with 302 handling, drift schema, Settings | 2–3 h |
| M2 | Study tab + Bus mode reading Study Bank, writing study events | 2–3 h |
| M3 | Today + Quick log + outbox sync | 3–4 h |
| M4 | Week + Money derivations and charts | 3 h |
| M5 | Tests from §8, polish, side-load to phone | 2 h |
| P1 | Widget, legacy import, notifications | 3–4 h |

**Build order is M0 → M2 first** so the app is useful for study from day 1.

## 10. Risks and open questions
- Apps Script latency and occasional 5xx: handled by the outbox; not measured.
- Logging split-brain: if chat logging continues into the old tabs, numbers diverge. Decision: from install day, log only in the app; the old tabs are read-only history.
- Cigarette price varies (₹24–25 from packs vs singles): a Settings default plus an editable amount in Quick log.
- Supplement list and protein target (50 g) live in Settings and are editable.

## Sources
- Apps Script web apps (event object fields, reserved `c`/`sid`): https://developers.google.com/apps-script/guides/web
- Apps Script quotas: https://developers.google.com/apps-script/guides/services/quotas
- POST always 302: https://groups.google.com/g/google-apps-script-community/c/WALz_3rw7u4
- dart:io redirect rules: https://api.dart.dev/stable/2.8.0/dart-io/HttpClientRequest/followRedirects.html
- Redeploy keeps the URL via New version: https://tanaikech.github.io/2021/03/29/redeploying-web-apps-without-changing-url-of-web-apps-for-new-ide
- Sheets API scopes: https://developers.google.com/sheets/api/scopes
- Testing-mode 7-day tokens: https://support.google.com/cloud/answer/15549945
