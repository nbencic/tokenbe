# Postmortem — Stage 4.3 Daily activity
Date: 2026-11-13 · Branch: s4.3-daily-activity · PR: #21 · Planned size: S · Commits: 4

## Outcome
Once a day, at a time macOS picks (`NSBackgroundActivityScheduler` `dev.bathyon.tokenbe.daily`, 86400/3600, `.utility`, repeating; startup step 7), TokenBe runs 04's daily steps in order:
- cost polls for accounts with `capabilities.cost`;
- a database backup;
- the full `integrity_check` on every 7th run;
- `incremental_vacuum`.

A step that fails is logged (`sched.daily_step_failed`) and retried at the next activity, and the remaining steps still run. Each run logs `sched.daily_start` / `sched.daily_end {dur_ms, steps_ok, steps_failed, <step>_ms}` and writes `tb.daily.lastRunAt` and `tb.daily.runCount`. The backup and integrity steps write `tb.db.last*`. Settings → Sources → `Run daily tasks now` runs the same function out of band, Advanced shows `Last daily run`, and the account page's cost source reads `Cost · ok · HH:mm`.

`verify-stage.sh 4.3`: VERIFY-SUMMARY. D1–D12 are met. Coverage is 97.38 % (gate 97 %). H2 is still open (Q-033); it does not block the stage.

## What went as planned
- **The runner is a small Core actor.** `DailyActivity` holds an ordered registry, a gate per step and a retry set; `CostPolls` reuses the scheduler's `Poller` and skip rules. Both were tested before any UI: 8 tests, all green on the first run, at 99 % line coverage for the file.
- **The app side is one file.** `DailyActivityRegistration` builds the steps in 04's order and owns the system scheduler and 09's bookkeeping. Later stages (roll-ups 9.1, price refresh 5.1, update check 9.4) slot in at their 04 positions.
- **Earlier scripts were dry-run first** (PM-3.5-5). Every stage script's static checks passed before any verify. The one guard 4.3 retires, `1.3.sh`'s "no Last daily run yet", was found by grep and updated in the same commit.
- **PM-4.2-2 closed here.** `DailyRunNowUITests` onboards, runs the activity, and reads `Cost · ok · HH:mm` on the account page.

## What went wrong
1. **The Mac stopped opening the popover for UI tests** (2026-11-12, about 22:30 to the next session).
   - **Symptom:** the first run of `DailyRunNowUITests` could not open the popover after onboarding. Then `RefreshPauseUITests` failed, and so did `PopoverEmptyStateUITests`, which no stage had changed since 1.1, on unchanged `main` (7dd6b99) too.
   - **Bisection:** turning off the new `NSBackgroundActivityScheduler` registration did not help, nor did stashing all 4.3 changes. No stray TokenBe process was running, the screen was not locked and the display was awake. The status item was still found and clicked, but no popover opened (no `ui.popover_open`).
   - **Root cause:** the Mac's state, outside the code. It cleared by the next session, where `PopoverEmptyStateUITests` passed at once. The agent cannot capture the screen, so the exact cause is unknown.
   - **Fix:** the owner chose to stop. The next session started with the cheapest UI check before anything else.
   - **Cost:** about 6 single-suite runs (~5 min) and one stop.
2. **A test polluted the global log.** The first coverage run failed `LogFacadeTests`: `DailyActivityTests.weeklyGate` built a `DailyActivity` without a test pipeline, so its records went through the global `Log` while `LogFacadeTests` was capturing it. Every activity in the suite now gets its own pipeline. **Cost:** one test run.
3. **Small compile and lint fixes.**
   - A `duration(to:)` call on an existential `any InstantProtocol` does not compile, so the runner measures on `ContinuousClock`; durations are only logged.
   - The results of `backup()` and `incrementalVacuum()` had to be discarded explicitly.
   - `Date` in `Strings.swift` needed `import Foundation`.
   - The `try?` JSON parse in the UI test became a `do`/`catch`.
   - **Cost:** four builds.

## Verify and CI failures
VERIFY-FAILURES

## Deviations from the docs
- **07 § Mandatory events:**
  - new `sched.daily_step_failed {step, err}` (error);
  - `sched.daily_end` adds `run` and `<step>_ms`, and is `warn` when a step failed (Q-037).
- **14 § Stage 4.3 Inventory:** adds `CostPolls` in `DailyActivity.swift` and the edits to `Startup`, `AppEnvironment` and `Strings`. § 13.3 lists `daily_step_failed`.
- **1.3.sh:** its "no Last daily run yet" guard is retired; 4.3.sh checks the row.

## Judgment calls
- Q-037 — Stage 4.3's daily-activity rules:
  - the failure event;
  - in-memory retry of gated steps;
  - run numbering and bookkeeping;
  - overlap skip;
  - cost-poll skips;
  - integrity failure;
  - the button's running state;
  - the `Last daily run` format;
  - no `next …` for cost;
  - the first run's timing.

## Carry-forward actions
- PM-4.3-1 · agent · process · Before a full verify, and after any idle gap, run `TB_UI_ONLY=PopoverEmptyStateUITests scripts/run.sh uitest` (~20 s). If it fails on unchanged code, the Mac's state is at fault. Stop and ask the owner instead of bisecting code.
- PM-4.3-2 · agent · process · Every test that builds a type taking `logPipeline:` passes one. A nil pipeline logs through the global `Log`, which `LogFacadeTests` owns.
- PM-4.3-3 · agent · 5.1 / 9.1 / 9.4 · Price refresh, roll-ups and the update check register as `DailyStep`s at their 04 positions: after cost polls, roll-ups, then price refresh, then update check, before the backup. Extend `4.3.sh`'s order check when each one arrives.
- **Earlier actions that targeted this stage:**
  - PM-4.2-2: closed (451fb19). `Cost · ok · HH:mm` is asserted; no next time (Q-037).
  - Process actions followed: PM-4.2-4 (no identifiers on bare containers), PM-4.2-5 (`DailyRunNowUITests` asserts its own results and reads no shared suite value), PM-4.1-2 (no new timing suite; the runner has no clock waits), PM-3.5-5 (dry-run first).
