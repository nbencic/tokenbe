# Postmortem — Phase 4 Scheduling
Date: 2026-11-13 · Stages: 4.1 (#18), 4.2 (#20), 4.3 (#21); process PR #19 (coverage gate 97 %, Q-035)

## Outcome vs. phase map
14 § 0.5: "Polls run on their own; Sources tab; stale/offline/paused states."
- **Polls run on their own:** met (4.1). `PollCoordinator` runs usage and keys on 09's intervals, with backoff, overlap guard, overrun cancel, Low Power ×4, and clock-jump and wake handling. A new account is polled at once. The daily activity (4.3) adds cost polls, backup, the weekly integrity check and vacuum, once a day and on `Run daily tasks now`.
- **Sources tab:** met (4.1). It has the intervals and the Low Power multiplier; 4.3 adds `Run daily tasks now`. Per-account overrides are under Accounts → `Refresh intervals`.
- **Stale, offline, paused states:**
  - paused (4.1): `Pause polling for 1 h` / `Resume` and the per-account `Paused` toggle;
  - stale and offline (4.2): the overlay, the `Offline — showing last known values` banner and the dashed glyph;
  - the account page's sources strip shows each job's state, last success, next run and human error message.
- **Verification:** E2E-5 (11) passes as `StaleOfflineUITests`. 04's DoD overlap and clock-jump items are covered by `CoordinatorTests` and `SchedulerTests`.

## Patterns across stages
1. **UI suites leak through shared state.** Three times in this phase a stage check or test depended on state another suite changes:
   - PM-3.4-8: `tb.ui.dashboardRange`;
   - 4.2 verify run 1: `tb.general.launchAtLogin`, which every fresh-root launch rewrites;
   - 4.3: `DailyActivityTests` logging through the global `Log` that `LogFacadeTests` captures.

   **Root cause:** global singletons (the UI-test settings suite, `Log`) shared by suites whose order is alphabetical. **Fix adopted:** each test asserts its own persistence after a relaunch, and stage scripts check that the test case passed, not a shared value (PM-4.2-5). Core tests always pass a pipeline (PM-4.3-2).
2. **Accessibility shape decides testability.** The cards' identifier and value were hidden by SwiftUI's container handling (4.2). The glyph's identifier was proven by a 4-second spike before the test was written, which saved a cycle. **Lesson:** spike the accessibility tree first, and put state in text (PM-4.2-4).
3. **Timing tests need observable effects.** `CoordinatorTests` raced their own setup until the tests waited for the request and the retry sleeper (4.1). The 50-loop before the first verify (PM-4.1-2) then held in 4.2: 50/50.
4. **Environment failures look like code failures.** ⌥-click (PM-4.1-4, did not recur) and the 4.3 popover outage both failed tests that no change had touched. The cheap check is a ~20 s run of `PopoverEmptyStateUITests` on unchanged code (PM-4.3-1).

## Plan and doc changes
- **07:**
  - `sched.clock_jump.reason` (4.1);
  - `poll.failed.detail` (4.2);
  - `sched.daily_step_failed` and the `sched.daily_end` ctx (4.3).
- **03:** `poll_state.last_error_message` holds the human message (4.2, prose only; the DDL is unchanged).
- **09:** override clamping for `account.interval_override_json` (4.1).
- **14:**
  - inventories for 4.1–4.3;
  - § 0.3: `FixedNetworkMonitor` (DEBUG);
  - § 13.3: `daily_step_failed`;
  - the coverage gate at 97 % (Q-035).
- **Stage scripts:** `1.2.sh` and `1.3.sh` now read the tests' own relaunch assertions; `4.1.sh` follows `networkMonitor()`. `run.sh uitest` takes `TB_UI_ONLY`.
- **Judgment calls:** Q-034 (4.1), Q-036 (4.2), Q-037 (4.3).
- **Proposed for later phases** (no doc change yet):
  - Paper's popover footer is a vertical menu list (PM-4.1-1 → 11.3).
  - 5.1, 9.1 and 9.4 register their daily steps at their 04 positions (PM-4.3-3).

## Gates and risks
- **H2 (OpenAI recording):** still open (PM-3.6-1, owner). It blocks only the Verified flip; Phase 5 proceeds on synthetic fixtures (14 § 0.4).
- **Risks for Phase 5:**
  - Money math lands on synthetic usage and cost shapes until H2; a recorded fixture may move field names (02 `[expected]`).
  - The band pill and dot show `unknown` until 5.3 (PM-4.2-1).
  - The glyph's `notched` state must be ordered against `dashed` (PM-4.2-3).
  - The UI suite now takes about 10 minutes, and every phase end runs it; a Mac-state outage costs a session (PM-4.3-1).

## Open carry-forward actions
- **Phase 4:**
  - PM-4.1-1 · agent · 11.3 · Rework the popover footer to Paper's vertical menu list; Paper's `YP-0` holds only the 5.1/7.2 groups.
  - PM-4.2-1 · agent · 5.3 · Assert the band pill's word once bands exist; the stale overlay keeps the last band.
  - PM-4.2-3 · agent · 5.5 · Order `notched` against `dashed`, with `GlyphStateTests`.
  - PM-4.3-3 · agent · 5.1 / 9.1 / 9.4 · Register the daily steps at their 04 positions; extend `4.3.sh`'s order check.
  - Process: PM-4.1-2, PM-4.1-4, PM-4.2-4, PM-4.2-5, PM-4.3-1, PM-4.3-2.
- **Phase 3:**
  - PM-3.6-1 · Nikola · H2 · Re-record OpenAI with an active org.
  - PM-3.6-2 · agent · the PR that consumes H2.
  - PM-2.2-3 · agent · 5.3 · Balance and the ledger in `SummaryInputs`.
  - PM-3.4-3 · agent · 5.x pricing · Reprice provider rows (`price.repriced`).
  - PM-3.4-4 · agent · 6.1 · `Repository+Balance` and the poller's balance write.
  - PM-3.5-4 · agent · 10.1 · Anthropic's wrong-prefix copy.
  - PM-3.2-3 · agent · 11.2 · Re-assess Q-027 once Developer ID signing exists.
  - PM-1.1-3 · agent · 11.2.
  - Process: PM-3.1-5, PM-3.2-4, PM-3.3-3, PM-3.3-4, PM-3.4-5, PM-3.4-7, PM-3.4-9, PM-3.5-1, PM-3.5-2, PM-3.5-5.
  - Closed in Phase 4: PM-3.6-3, PM-3.1-4 and PM-3.5-3 (4.1); PM-3.4-8 (4.2).
- **Phase 2:** PM-2.2-1, PM-2.2-2, PM-2.2-4, PM-2.1-1/2 (process); PM-2.1-4 (9.x).
- **Phase 1:**
  - process: PM-1.3-1, PM-1.3-2, PM-1.2-1/2/3/5, PM-1.1-1;
  - PM-1.3-3 (5.5);
  - PM-1.3-4 (8.4 / 11.4);
  - PM-1.2-4 (9.5).
- **Phase 0:**
  - PM-0.1-3 (11.5);
  - PM-0.2-3 (9.5);
  - process: PM-0.3-2, PM-0.4-2, PM-0.5-1.
  - Closed in PR #19: PM-0.5-2 (coverage gate 97 %, Q-035) and PM-0.4-3.
