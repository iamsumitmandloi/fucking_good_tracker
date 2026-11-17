# DECISIONS

Format: date · what · why · evidence.

## 2026-11-17

1. **Repo layout: docs stay in `handoff/`, app goes to `app/`.** The brief expects `PRD.md`, `design/`, `backend/` at the root; they live in `handoff/`. Moving them gains nothing. The pre-existing `fucking_good_tracker/` (default counter app) is left untouched and unused. Evidence: `ls` of the repo root.
2. **`fucking_good_tracker/shit` holds the live `/exec` URL and what looks like the token in plain text.** Added to `.gitignore`; should be deleted once `secrets.json` exists. Value never copied anywhere.
3. **Bus mode summary copy changed.** Design says "Written to Study Sessions as one row"; PRD §4 says each card is its own `study` event and the summary writes nothing extra. PRD wins. New copy: "Each card is saved as its own entry. Blank and Shaky come back tomorrow; Nailed in 4 days." Evidence: `BusMode.dc.html:79` vs `PRD.md:69`.
4. **Bus mode run size.** The design shows a 4-segment progress bar; the due queue can be 198 cards on day 1. A run takes the first N due cards (Settings, default 10); segments = N. Exit keeps rated cards.
5. **Week cigarette bar colour.** Design colours Mon/Tue lime (4 each) and other days grey; budget is 5. Rule: lime when ≤ budget, grey otherwise. Evidence: `Trends.dc.html:105`.
6. **Sleep row label = wake date.** Design's "Tu" row is 22:30 → 06:00 ending Tue morning, matching Today's "Slept ~22:30 → ~06:00". Evidence: `Trends.dc.html:106`, `Today.dc.html:125`.
7. **"Day N" in the Today header** = days since the first date with any data (11 Nov = Day 1, 17 Nov = Day 7). Evidence: `Today.dc.html:24`.
8. **Study "Browse the bank" chips** (Source tab counts) are in the design but not in PRD scope. Build the chips with live counts plus a simple read-only list per source; no editing.
9. **Flutter toolchain = fvm default (Flutter 3.47.9, Dart 3.13.7).** `flutter` on PATH resolves to `~/fvm/default/bin/flutter`.

## Live API headers (pending)

Blocked: `secrets.json` not present yet. Will record actual headers of `Start Here`, `Study Bank`, `Events` (and the legacy tabs) after the first live GET.
