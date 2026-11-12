# Postmortem — Stage 4.1 Scheduler, coordinator, pollers; Sources tab; Refresh/Pause
Date: 2026-11-12 · Branch: s4.1-scheduler · PR: #18 · Planned size: L · Commits: 4

## Outcome
Polls now run on their own, per 04:
- usage every 5 min and key lists every hour for OpenAI;
- a new account is polled at once;
- skipped jobs log `sched.skip` (paused, circuit open, offline), and Low Power Mode stretches intervals ×4;
- sleep/wake and wall-clock jumps log `sched.clock_jump` without a catch-up burst;
- a job running past 2 × its interval is cancelled with `sched.overrun {phase}`.

The user can:
- set intervals in the new Settings → Sources tab, or per account under Accounts → `Refresh intervals`;
- see `Refreshed …` with a spinning refresh button in the popover header;
- pause everything with `Pause polling for 1 h` (`Paused · resumes HH:mm` with `Resume`);
- pause one account with its `Paused` toggle.

`verify-stage.sh 4.1` passes every stage check (782 `ok`). Its one `skip` is 3.6's H2 gate (Q-033). D1–D12 are met, plus 04's DoD overlap and clock-jump items (`CoordinatorTests.pollerOverlap`, `SchedulerTests.clockJump` / `wakeNoCatchUp`). 14's Verify run was a 190 s fixture-mode launch with usage every 60 s; it logged `poll.ok usage` gaps of 60.07 / 60.18 / 60.04 s and no error or fault records. H2 is still open; it does not block this stage (14 § 0.4).

## What went as planned
- **Core first.** `SchedulerLoop` is a pure table: due, coalescing, backoff, rebase. `AccountPoller` is a thin I1 guard over the existing `Poller`, and `PollCoordinator` holds the side effects. 3.4's `Poller` literals and tests are unchanged, apart from the new `phase` parameter.
- **One input stream.** The coordinator follows the store's own observation (`observeSummaryInputs`). Accounts, `account.paused`, overrides and circuits all reach it the way they reach the UI. This closed PM-3.6-3 and PM-3.5-3 with no extra plumbing.
- **The advisor's points held.** I1 is claimed before the first suspension. Overruns are folded into the loop's single wake, so no watchdog sleepers sit on `TestClock`. `Remove account…` awaits `coordinator.stop` first (the removal race). The cadence run passes settings through the argument domain, so the UI-test suite keeps nothing.
- **Earlier scripts checked up front.** `scripts/stages/*.sh` were grepped for every changed symbol before the first verify (PM-3.5-5): `scheduler` was appended after `login item`, so 2.1.sh's first-four-steps check is unchanged. A dry run of 1.x–4.1 found the stale "not yet" checks in 1.1.sh and 1.3.sh and two wrong 4.1 greps before any verify run.

## What went wrong
1. **Coordinator tests raced their own setup (33 of 50 loop runs failed).**
   - **Symptom:** the first full test run was green. The 50-run loop (PM-1.2-3) then failed in `states`, `addRemove` and `refreshOverlap`: idle never came, or `calls(usage) == 0`.
   - **Root cause:** the tests waited for "usage dispatched" (`runningKeys`, `inFlightCount == 1`) and then advanced the clock or removed the account. The job's first request and its retry sleeper could still be pending, so the advance was lost or the request never went out.
   - **Fix:** `SchedulerHarness.usageRetrying()` waits for the request and the retry sleeper themselves. The rerun loop passed 50/50 (one run's console summary was truncated, Q-022; it exited 0).
   - **Cost:** one loop run (~10 min).
2. **Lint caught structure, and one false positive.**
   - `PollCoordinator` exceeded `file_length` and `type_body_length` (strict: 250 lines), and used a 3-tuple. Inputs moved to `PollCoordinator+Inputs.swift` (14's inventory updated), and the tuple became `TickMark`.
   - `tokenbe_no_silent_catch` (`try\?`) matched `Entry?`. The type became `Slot`.
   - **Cost:** two lint/build passes.
3. **Compile errors in tests.** `#expect(await a && b)` makes `b` an autoclosure that cannot `await`. The expectations were split. **Cost:** one build.
4. **Paper Desktop was not running.** `YP-0`'s control style and the popover footer could not be checked. The Advanced tab's Stepper pattern is used. The footer wraps to two rows, because 08's four actions need about 430 pt of a 360 pt popover (Q-034). This is re-targeted to 11.3 (PM-4.1-1).

## Verify and CI failures
- **Verify run 1:** `FAIL 0.4 UI tests (LaunchSmokeTests)` because the run's `DashboardShellUITests.testOptionClickOpensDashboard` failed ("⌥-click opens the Dashboard"). The runner logged `Could not find any displays containing rect (inf, inf, 0.0, 0.0)` while clicking the status item. Rerun alone, the suite passed both cases. Nothing in this stage touches the ⌥-click path, so this is treated as an environmental flake (PM-4.1-4). The suite passed again in run 2.
- **Verify run 2:** every stage check `ok`; D13 failed only for this missing postmortem, as expected (14 § 0.6).
- CI: see the PR.

## Deviations from the docs
- **07 § Mandatory events:** `sched.clock_jump` gains `reason` (`drift`, `wake`) in ctx (Q-034).
- **09 § Accounts:** `account.interval_override_json` values are clamped to the overridden key's range and logged as `app.settings_changed clamped=true source=system`. `cost` overrides are not read (Q-034).
- **14 § Stage 4.1 Inventory:** adds `PollCoordinator+Inputs.swift`, the same actor split for lint.
- **3.5 behaviour:** onboarding's `Done` no longer sends requests. The coordinator polls the account as soon as it exists (PM-3.6-3). 3.5.sh and `OnboardingUITests` were updated.
- **1.1.sh / 1.3.sh:** their "not yet" checks for `Pause polling`, `arrow.clockwise` and the Sources tab are retired; 4.1.sh checks them now.
- **Popover footer:** two rows instead of one (Q-034, PM-4.1-1).

## Judgment calls
- Q-034 — Stage 4.1's scheduling rules:
  - next run counted from completion;
  - coalescing within the tolerance;
  - skips wait one interval, and resume, unpause, reset circuit and reconnect run at once;
  - `refreshNow` obeys skip rules;
  - removal awaits `stop`;
  - missing keys keep polling with backoff;
  - override clamping;
  - Sources steppers;
  - the two-row footer;
  - header freshness = the oldest account success;
  - the cadence run's setup.

## Carry-forward actions
- PM-4.1-1 · agent · 11.3 · Check Settings → Sources (`YP-0`) and the two-row popover footer (`1-0`) against Paper; Paper Desktop was not running in 4.1. Status (4.2): looked at in Paper. `YP-0` holds only the Harness reports and Price book groups (7.2, 5.1). Paper's footer is a vertical menu list, label left and shortcut right, not two rows of buttons. Stays → 11.3 for the rework.
- PM-4.1-2 · agent · process · A test that needs a job "in flight" waits for its observable effect (the request sent, the retry sleeper registered), never for the dispatch alone. Run the 50-loop on every new timing suite before the first full verify.
- PM-4.1-3 · agent · 4.2 · `AppModel.isOffline` is now fed by `CoordinatorState`. 4.2's offline banner and dashed glyph read it; `Freshness` adds stale. Status: closed in 4.2 (3c2f844).
- PM-4.1-4 · agent · process · If `DashboardShellUITests.testOptionClickOpensDashboard` fails again inside the full suite, capture `app.debugDescription` around the ⌥-click (PM-3.5-1) and look at the status item's frame (`inf` rect).
- PM-4.1-5 · agent · 4.2 · An account with a missing key is still polled and logs `keychain.missing` (error) at most every 15 min (Q-034). 4.2, which owns `needsKey` on the sidebar, decides whether that is right for SOAK-1, or logs a Q. Status: closed in 4.2, kept as is (Q-036).
- **Earlier actions that targeted 4.1:**
  - PM-3.6-3: closed (7883667). Onboarding's `Done` defers to the coordinator; 3.5.sh's check follows.
  - PM-3.1-4: closed (dea2f74, 7883667). `ManualNetworkMonitor` (test seam), `NWPathMonitorAdapter` wired in startup, `sched.skip reason=offline`.
  - PM-3.5-3: closed (dea2f74). The scheduler skips paused accounts, and `AccountSummary.isPaused` comes from `account.paused`.
  - PM-2.2-3: progress (dea2f74). `SummaryInputs` already carried `account.paused`; `ObservationTests.pausedFlows` covers it. It stays open for 4.2–5.3.
