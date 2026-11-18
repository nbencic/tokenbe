# Postmortem — Stage 9.5 Reset, cleanups, environment audits
Date: 2026-11-18 · Branch: s9.5-reset-audits · PR: #43 · Planned size: S · Commits: 6

## Outcome
Every remaining 09 behaviour and 04's startup sequence are verified end to end:
- **Reset all settings…** is Advanced's last row. After a destructive confirm it runs `Settings.resetAll`, which removes every `tb.*` key except `tb.ui.onboardingDone`, re-registers the defaults, reaches every live consumer and logs `app.settings_reset`. Keys, the database and logs are untouched.
- **A time-zone change while running (O-14)** resets Foundation's zone and logs `sched.clock_jump {tz: true, reason: timezone}`. The schedule is rebased with no extra polls, and the log file turns over at local midnight in the new zone.
- **Sleep and wake** stay wired from 4.1.
- **9.5.sh audits 04.** It launches the Debug app twice on a throwaway root and asserts each launch's 8 startup steps in 04's order, step 1's fields, and zero error or fault records.
- **PM-0.2-3:** `check-log-events.sh --from-tests` now requires every event to be produced in a test.
- **E2E-6** (SettingsRoundTripUITests) changes one control per tab, relaunches, and resets.

D1–D13 are met. This stage closes phase 9 (`phase-9.md`), and the H5 soak starts here (owner; see `phase-9.md` § Gates and risks).

## What went as planned
- **The advisor's review settled the design before code:**
  - check that Reset reaches the live consumers (every one subscribes to `settings.changes`, and `resetAll` publishes every key);
  - lower the test pipeline to debug for `ingest.duplicate`;
  - look for zone caches beyond the sink (none: quiet hours and dates read `.current` at call time);
  - avoid the keys `makeApp` pins in E2E-6;
  - audit step 1's fields, not only the order;
  - work out how the soak and the verifies share this Mac.
- **Each test passed on its first run:** the time-zone and `ingest.duplicate` tests (16 tests in 2 suites), the launch audit run on its own, and `SettingsRoundTripUITests` (1 min 15 s).
- **PM-9.3-2's routine held** before the first verify:
  - the coverage gate (97.12 %);
  - a grep of the stage scripts for globs over the folders this stage writes into (only 7.1.sh's per-suite `ui-covers` loop, which the new suites satisfy);
  - a full dry run of 9.5.sh.
- **Carry-forwards closed:** PM-8.3-1 (the last guard), PM-1.2-4, PM-0.2-3, PM-8.1-3 and PM-7.3-5. PM-5.4-2 is re-targeted to 11.5, after the soak (Q-059).

## What went wrong
1. **`Startup`'s class body went past 250 lines.**
   - **Symptom:** the time-zone watcher pushed the body to 256 lines (`type_body_length`).
   - **Fix:** the three system watchers moved to `Startup.systemWatchers(_:)` in an extension. 4.1.sh's literal checks still find them in the file.
   - **Cost:** one lint run.
2. **A dry-run script broke on its own filtering.**
   - **Symptom:** dropping the `suite_passed` lines left a stray `done`.
   - **Fix:** a stub instead of a filter.
   - **Cost:** one rerun; 9.5.sh itself was fine (`bash -n`).

3. **`LogFacadeTests` lost its debug records once (a race from before this stage).**
   - **Symptom:** full verify 1 failed 0.1's `swift test`: two issues in `LogFacadeTests`, whose `debug` records never arrived.
   - **Root cause:** `Settings.init` binds `tb.log.level` to the process-wide `Log` when it has no pipeline of its own. Three tests built a `Settings` that way (CoordinatorTests, AccountLifecycleTests, SettingsAccessorTests). Run in parallel with the serialized `LogFacadeTests`, one of them reset the global level to `info` between that test's `debug` setting and its records. Every earlier run had passed by timing.
   - **Fix:** those three get a private, silent pipeline, like every other test (only LogFacadeTests may use the global `Log`). A full Core run then passed.
   - **Cost:** one full verify (it fails at the first stage, within minutes).

4. **E2E-6's Reset wiped values that 1.3's checks read.**
   - **Symptom:** full verify 2 ran all 29 UI tests green, then failed 1.3's `UI-test suite: tb.menubar.metric = todaySpend`.
   - **Root cause:** Reset removed every `tb.*` key from the shared UI-test settings suite, after SettingsGeneralUITests had written the values that 1.3.sh reads from it (PM-1.2-2). The advisor had named this risk; I took DashboardShell's reset at its start as precedent, but a reset that runs after another suite's writes is different.
   - **Fix:** a DEBUG opt-in, `TOKENBE_TEST_SETTINGS_SUITE`, gives one test a suite of its own under the UI-test prefix (`….uitests.roundtrip`, cleared at its first launch). `resetUITests` accepts only that prefix, `uiTestsName(isolated:)` strips anything but letters, digits and `-`, and `DashboardShellTests` asserts both. SettingsGeneral and RoundTrip then passed in that order, and the shared suite kept `todaySpend`.
   - **Cost:** one full verify (35 min).

## Verify and CI failures
- **Core and lint:** 583 Core tests in 87 suites passed; coverage 97.12 %; lint clean after What went wrong 1.
- **Launch audit run alone:** both launches, the order, step 1's fields and no error or fault records, all passing.
- **UI, targeted:** SettingsRoundTripUITests passed on its first run.
- **Guard sweep** (`TB_UI_TESTS=0 verify 9.5`): `STAGE 9.5 OK` on the first run, with 1 516 checks passed.
- **Full verify 1:** FAIL 0.1, `swift test` (What went wrong 3).
- **Full verify 2:** all 29 UI tests passed, then FAIL 1.3 `UI-test suite: tb.menubar.metric = todaySpend` (What went wrong 4).
- **Full verify 3:** see the PR body. `Startup.swift` is a shared file, so Q-047 selects every suite.
- **CI:** the head that carries this file is checked by SHA before the merge.

## Deviations from the docs
- **07 `sched.clock_jump`:** the `reason` gains `timezone` (O-14); 07 is updated in this PR.
- **O-14 "recompute today boundaries":** "today" for spend is the UTC day (Q-040) and does not move. Only the local-time days move: log rotation and quiet hours (Q-059).
- **The audit's step list:** 9 lines per launch. 04's 8 steps, plus `login item` between ingest and the scheduler (Q-023).
- **14 § Stage 9.5:** the Inventory now lists the files, and the Tests line the cases.

## Judgment calls
- Q-059 covers the rules the docs leave open:
  - the Reset dialog's text;
  - AppKit's window state, which is kept (PM-1.2-4);
  - the time-zone handling;
  - the audit;
  - `--from-tests` and its four exemptions;
  - the per-process once-a-day logs (PM-8.1-3);
  - the test-root key note (PM-7.3-5);
  - E2E-6's scope.

## Carry-forward actions
- PM-9.5-1 · Nikola · 11.5 · H5: the 14-day soak, set up as described in `phase-9.md` § Gates and risks; its findings go into the phase-11 postmortem (14 § 0.6 rule 5).
- Earlier actions that targeted 9.5:
  - closed:
    - PM-8.3-1 (stage-8.3, phase-8);
    - PM-1.2-4 (stage-1.2);
    - PM-0.2-3 (stage-0.2);
    - PM-8.1-3 (stage-8.1);
    - PM-7.3-5 (stage-7.3);
  - re-targeted: PM-5.4-2 → 11.5 (stage-5.4: judged on the soak's data).
- Still open: see `phase-9.md` § Open carry-forward actions.
