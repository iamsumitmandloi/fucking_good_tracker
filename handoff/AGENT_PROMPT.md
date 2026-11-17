# Paste this into Claude Code (or any coding agent) from the repo root

You are building **Starting Again**, a personal Flutter app (Android + iOS) that reads from and writes to my Google Sheet through an Apps Script web app. Everything you need is in this repo:

- `PRD.md`: requirements, verified constraints, data model, API contract, milestones. **Source of truth.**
- `design/DESIGN.md`: tokens and components. `design/screens/*.dc.html`: the 6 screen designs (390×844). They are design-tool HTML: read them for layout, spacing, copy and colours; don't try to run them. If `design/screens/png/` exists, the PNGs are the visual truth.
- `backend/Code.gs`: the Apps Script backend. Already written; don't change its contract without asking me.

## Rules
1. Read `PRD.md` and `design/DESIGN.md` fully before writing code. Then reply with: (a) your understanding in ≤ 10 lines, (b) anything in the PRD you think is wrong or ambiguous, (c) the M1 file list. **Wait for my OK.**
2. Build in milestone order **M1 → M2 → M3 → M4 → M5** (PRD §9). Stop after each milestone and show: what's done, how to run it, test results, what's next. Wait for my OK.
3. **Never run git commit, push, branch or any other git write without asking me first.** Work in this folder only; no extra clones or worktrees.
4. Add packages with `flutter pub add <name>`; never invent versions. After any change: `dart format .`, `flutter analyze` (zero warnings), `flutter test`.
5. The sheet URL and token come from Settings (flutter_secure_storage), optionally seeded via `--dart-define=SHEET_URL` / `SHEET_TOKEN`. Never hard-code or commit them. Never log the token.
6. **The POST 302 is mandatory knowledge**: Apps Script answers every POST with 302; dart:io won't follow it for POST. Read `location`, then GET it (PRD §5.1). Write a unit test for this path first, with a fake client.
7. Offline-first: every UI read comes from drift; the network only refreshes the cache and flushes the outbox. Logging must work in airplane mode.
8. Missing data is never 0. Show "—" or a gap.
9. Match the design closely: tokens via a `ThemeExtension` (`AppColors`, `AppText`), Space Grotesk + Inter via google_fonts, dark only, 44px+ touch targets, no emoji icons.
10. If something in the PRD is impossible or a package behaves differently than stated, stop and tell me with evidence (doc link or error). Don't silently work around it.

## Start
Do step 1 of the rules now.
