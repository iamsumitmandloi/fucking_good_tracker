# Starting Again: agent rules

Resume by reading this file, then `PROGRESS.md` (current phase, next step, blockers), then `PLAN.md` and `DECISIONS.md`.

**Phase 7 (current direction):** the app is a read-only viewer of the Events tab. Brief `handoff_v2/AGENT_PROMPT_v2.md` (it overrides the PRD where they differ), plan `PLAN_v2.md`, design `handoff_v2/design/`. Every write path sits behind `FeatureFlags.logging` (off). No writes to the sheet at all, not even `dev-` rows, unless the owner turns logging back on.

## Where things are
- Requirements: `handoff/PRD.md` (source of truth). Design: `handoff/design/DESIGN.md` + `handoff/design/screens/*.dc.html` (read, don't run).
- Backend: `handoff/backend/Code.gs`. **Do not modify or redeploy.** If it must change, stop and explain why.
- Flutter app: `app/`. Ignore `fucking_good_tracker/` (unused default project).
- Secrets: `secrets.json` at the root (`SHEET_URL`, `SHEET_TOKEN`). Run with `--dart-define-from-file=../secrets.json` from `app/`.

## Hard rules
1. **Token:** never print, log, commit or paste it. Mask as `••••`. Never `cat secrets.json` into output; read it inside scripts only.
2. **Git:** no commit/push/branch/reset/stash or any git write without asking. `git init`, `status`, `diff` are fine.
3. **Live sheet:** GET any time, only the tabs needed (`&tabs=`). POST only for a phase gate's named live check, ids prefixed `dev-`, type `note` unless the gate says otherwise. List every dev row in `PROGRESS.md`. Never write to legacy tabs.
4. **POST → 302 → GET Location.** dart:io won't follow it for POST.
5. Every cell value from the API is a string (`"87.91"`, `"TRUE"`, `""`); rows carry `_row`. Parse defensively. Legacy parser never throws.
6. **Packages:** `flutter pub add` only; never invent versions. Ask before adding anything heavy not named in the PRD.
7. **Quality bar on every change:** `dart format .` → `flutter analyze` (zero issues) → `flutter test` (green). Don't move on with red.
8. **Offline-first:** UI reads only from drift; network refreshes cache and flushes the outbox.
9. **Missing data is never 0:** show "—" or a gap. Stats ignore `dev-` ids and voided events.
10. **Design:** tokens in ThemeExtensions from DESIGN.md; Space Grotesk + Inter; dark only; touch targets ≥ 44; no emoji icons.
11. **Verify, don't assume:** if a package or the backend differs from the PRD, check, adapt, record in `DECISIONS.md`.
12. Update `PROGRESS.md` after every phase and major step.

## Stop only for
Secrets needed, a git operation, an unresolvable PRD contradiction, or the end of Phase 6.
