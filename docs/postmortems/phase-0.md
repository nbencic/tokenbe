# Postmortem — Phase 0 Toolchain & skeleton
Date: 2026-11-09 · Stages: 0.1 (#1), 0.2 (#2), 0.3 (#3), 0.4 (#4), 0.5 (#5)

## Outcome vs. phase map
14 § 0.5: "A signed-less app that launches, shows a menu-bar glyph, logs `app.launch`/`app.terminate` to NDJSON."
- **App launches, menu-bar glyph:** met. The ring is drawn in code; the UI smoke test finds the status item.
- **`app.launch` / `app.terminate` to NDJSON:** met. Startup step 1 and the clean-terminate path, verified by real launch/quit/kill cycles.
- **Signed-less:** ad-hoc "sign to run locally", hardened runtime in Release, no sandbox. Developer ID waits for H4.
- **Beyond the line:** CI, the coverage gate, the secret/URL guard, the logging, crash and settings cores, and a machine-checked definition of done with postmortems.

## Patterns across stages
1. **Spec defects surfaced only when something executable touched them.** Each was caught by a test or check, never by reading:
   - the 07 redaction patterns leaked bearer tokens (0.2);
   - 10's lint exclusion named the wrong file (0.3);
   - 14 D10 deleted the owner's real data, and H1 missed Xcode 26's template overrides (0.4);
   - 11's fixture placeholder would have failed the secret guard (0.5).

   Root cause: the docs were reviewed in two read-only passes, with no runnable checks.
2. **Toolchain drift.** Local Swift 6.2 vs CI's 6.1 (0.5), and the moved `.build` layout (0.5). Only CI catches the first; tools should ask SwiftPM for paths instead of hard-coding them.
3. **The owner's machine as a test bed.** Several near misses involved the owner's real environment, each closed with a structural fix:
   - XCUITest's hard kill left a sentinel;
   - D10's `rm -rf`;
   - `.env` not ignored.

   The fixes: `TOKENBE_TEST_ROOT`, a verify check that real folders stay untouched, and `.gitignore`.
4. **My own slips, caught by read-back or tests before shipping:**
   - malformed patches (0.2);
   - logic slips in `set`/`emit` (0.3);
   - a non-append file handle that would have overwritten crash lines (0.2);
   - a misread coverage column (0.3, found in 0.5);
   - lint style (trailing commas, 0.2 and 0.3).

   The repeated-run, fresh-clone and second-look habits paid off every stage.

## Plan and doc changes
- Applied during the phase:
  - `07`: redaction, record shape, `app.log_sink_failed`;
  - `09`/`10`: the lint exclusion;
  - `12`: R11 per-stage branches, R12/R13 postmortems and project-file rule;
  - `13`: D-postmortems, D-stage-branches, D-xcodeproj-agent, GRDB 7.12.0;
  - `14`: § 0.6 postmortems, D13, H1 retired, D10 isolation;
  - `00`/`CLAUDE.md`: pointers.
- Q-001 to Q-016 logged; Q-001 and Q-005 resolved.
- Proposed for later phases:
  - Every new provider field or doc rule should land with an executable check in the same PR (the pattern behind item 1). Already the practice in this phase; no doc change needed beyond R10.
  - Phase 3's `record-fixtures.sh` must write the 11 placeholder exactly, or the guard will flag it.

## Gates and risks
- **H1:** retired (D-xcodeproj-agent).
- **H2:** next human gate, at 3.6. The owner has an OpenAI Admin key in `.env` (git-ignored, never read by the agent) and runs `record-fixtures.sh` in their own terminal.
- **H3:** at 6.1/6.2. **H4:** needs a paid Apple Developer membership. **H5:** starts after 9.5.
- **Risks for Phase 1:**
  - `MenuBarExtra(.window)` limits: ⌥-click (O-15) and popover sizing;
  - XCUITest on macOS 27 needs Automation/Accessibility permission (it worked here without a prompt);
  - all SwiftUI views must fit `08` with copy only from `Strings.swift` (lint enforced).

## Open carry-forward actions
- PM-0.1-3 · Nikola · 11.5 · Apple ID / Team in Xcode for Developer ID signing (H4).
- PM-0.2-3 (rest) · agent · 9.5 · `check-log-events.sh --from-tests`.
- PM-0.3-2 · agent · every stage · no trailing commas.
- PM-0.4-2 · agent · every stage · launches and UI tests only under `TOKENBE_TEST_ROOT`.
- PM-0.4-3 · Nikola · now · `chmod 600 ~/tokenbe-app/.env`.
- PM-0.5-1 · agent · every stage · Swift 6.1 is the compile gate.
- PM-0.5-2 · Nikola · 11.2 default · decide on coverage beyond 85 %.
