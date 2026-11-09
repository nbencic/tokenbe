# Postmortem — Stage 1.2 Dashboard window shell
Date: 2026-11-09 · Branch: s1.2-dashboard-shell · PR: #7 · Planned size: S · Commits: 7

## Outcome
TokenBe now has its Dashboard window:
- The popover footer has `Open dashboard` (⌘D); ⌥-click on the menu-bar glyph opens the Dashboard directly.
- The window is a `NavigationSplitView`, minimum 920×600. The sidebar has `Overview`. The Overview shows the real empty state (`No accounts yet`) and a `Spend by day` card reading `No spend in this range`; there is no placeholder headline.
- The toolbar's range picker `Today | 7 d | 30 d | 90 d` is bound to `tb.ui.dashboardRange` (default `7 d`).
- The window frame is saved to `tb.ui.dashboardFrame` on move or resize (debounced 500 ms) and on close. It's restored on the next open, but only if it still fits on a connected screen.

Core gained `DashboardRange`, `WindowFrame` (format, minimum size, off-screen rule), `Debouncer` (clock injected) and `SettingsSuite.resetUITests`. The reset refuses every suite but the UI-test one.

Verification:
- 84 Core tests pass, including 4 new suites: DashboardRange, WindowFrame, Debouncer and SettingsSuiteReset. After the flake fixes (item 6), about 350 full-suite runs had no failing test.
- `DashboardShellUITests` covers two scenarios:
  - ⌘D opens the Dashboard with the empty Overview. Picking `30 d`, closing, quitting and relaunching gives the same range and the same frame.
  - ⌥-click opens the Dashboard.
- 14's Verify reads `tb.ui.dashboardRange = 30d` from the UI-test suite. The owner's real settings plist, logs and support folder were confirmed untouched.

DoD D1–D4, D6 and D8–D11 are met; D12 is met by PR #7's green CI; D13 is met by this file.

## What went as planned
- The 1.1 investment paid off. The shared UI-test helpers (overflow-aware `openPopover`, `text`, launch-argument settings, `quitThroughPopover`) made the Dashboard tests straightforward, and the popover test now uses them too.
- ⌥-click via `NSEvent.modifierFlags` worked on the first try on macOS 27, so O-15's fallback (dropping it) wasn't needed.
- Turning off SwiftUI's own window restoration made the frame test meaningful. The restored frame can only come from `tb.ui.dashboardFrame`, and it matched exactly after a relaunch.
- `main` CI after the 1.1 merge was green.

## What went wrong
1. **The Dashboard UI tests looked for the window by title.** `.navigationTitle("Overview")` renames the window, so `windows["Dashboard"]` matched nothing, although both ⌘D and ⌥-click had opened it. The element tree in the result bundle showed it at once. Fix: find the window by its scene id `dashboard`. Cost: one UI-test run.
2. **One UI test undid the other's state.** The ⌥-click test reset the UI-test settings, and it runs after the ⌘D test, which would have erased the `30d` that 14's Verify reads. Caught by reading the suite before running verify. Fix: only the test that needs a clean start resets. Cost: none.
3. **`CGRect.width` is never negative.** `{{1, 2}, {-5, 600}}` decoded as a valid frame, because CGRect standardizes its size. Fix: check the raw numbers. Cost: one test run.
4. **The first debouncer test raced the clock.** It advanced time before the second task had started sleeping, so the deadline moved. Fix: let tasks settle and assert exactly one sleeper before advancing. Cost: one test run.
5. **Smaller slips, one build or lint run each:**
   - a non-isolated `deinit` touching main-actor state (`isolated deinit` is Swift 6.2-only, PM-0.5-1); observers are removed when the view leaves its window instead;
   - a closure-parameter-position lint error;
   - a `DashboardView` comment that named the future buttons, which would have tripped my own D6 check. That is the same mistake as in 1.1; this time it was caught before verify by grepping for what the check greps.
6. **The first verify run failed on an old 0.2 test, and that uncovered three flakes and a real bug.** `LogSinkTests`' "overflow … reports `app.log_dropped` on the 60 s tick" failed once. Looping the full suite found 4 failures in 60 runs, in two tests, plus runs whose output was cut short.
   - **Production bug (0.2, `Log.swift`):** the 60 s timer's `.reportDropped` was yielded into the bounded stream without a retry. When the stream was full, the drop report was itself dropped and went out a tick later; 07 says it goes out on the tick. Fix: the timer calls `reportDroppedNow()`, which retries until the consumer makes room.
   - **`TestClock.waitForSleepers` gave up silently after 10,000 yields.** Under a loaded parallel run that isn't enough, and the test advanced time before the timer slept. Fix: a shared `eventually` helper bounded by 5 s of real time, which records an issue on timeout. It also replaced two other yield-count loops (`LogFacadeTests`, `LogSinkTests`).
   - **`TestClock` registered sleepers for already-cancelled tasks.** The cancellation handler had already run, so the sleeper lingered, unlike a real clock, which throws. This made the debouncer run a cancelled action. Fix: `TestClock.sleep` throws `CancellationError` for a cancelled task. `Debouncer` also re-checks cancellation after sleeping, so a clock that returns normally can't run a stale action.
   - **My `resets()` unit test wrote the real UI-test suite.** The process-wide registration domain made it flaky, and since verify re-runs the unit tests at 0.5 after the UI tests, it would also have wiped the `30d` that 1.2's check reads. Removed. The positive path is proven by the UI test, which resets and then sees `7 d` although the previous run left `30 d`. That proof holds from the second run on, once the suite holds a non-default value; a first-ever run proves only that the default shows.
   - **Truncated console output, not a code problem.** About once in 100–150 runs, SwiftPM's relay lost the tail of Swift Testing's output while the run exited 0. On such a run the xunit result still listed all 84 tests as passed. The stage checks grepped that console text, so they could fail spuriously. Fix: `run.sh test` writes `--xunit-output`, and every stage's suite checks now read it through `suite_passed` (Q-022).
   - Cost: about 45 minutes and some 900 test runs. Lesson: a check that passes 20 times in isolation still needs a loop of the full parallel suite.

7. **A UI test wrote the owner's real defaults domain.** `NavigationSplitView` autosaved its sidebar split widths into `dev.bathyon.tokenbe`, the app's standard domain, at 22:27. `TOKENBE_TEST_ROOT` redirects TokenBe's own settings suite but not AppKit's standard domain. I found the plist while checking that the real folders were absent after verify run 2. It holds one AppKit key and no TokenBe setting. My first guard (the plist's mtime) was wrong in kind, because AppKit legitimately writes there. Fix: 0.4 snapshots the real domain's `tb.*` keys at the start of verify and both 0.4 and 1.2 require them unchanged; recorded in Q-020. The key itself was left in place, per the rule never to modify the owner's real domain.
8. **The Mac locked again before verify's UI tests** (`Timed out while enabling automation mode`, `IOConsoleLocked = true`). PM-1.1-1 says to check the lock before UI tests, and I checked only before my standalone runs, not before verify. Everything else was finished and pushed, and the UI tests waited for the owner.

## Verify and CI failures
- `swift test` run 1: items 3 and 4. Run 2: green.
- `verify-stage.sh 1.2` run 1: `FAIL 0.2 swift test` (item 6). Full-suite loops then failed 4 of 60, then 1 of 100 (my `resets()` test), then truncated output 4 of 100 with all tests passed.
- `build-app` run 1: item 5 (`deinit`). Run 2: green.
- `uitest` run 1: item 1 (both Dashboard tests). Run 2: all 4 UI tests green.
- `verify-stage.sh 1.2` run 2: `FAIL 0.4 UI tests` (item 8, the locked screen); every earlier check passed (148).
- Run 3, after the unlock: all tests and UI tests green; `FAIL 1.2 owner's real TokenBe settings … real_tb_unchanged: command not found` (item 9).
- Run 4: `STAGE 1.2 OK`, 248 checks.
- CI on PR #7: run 42708352467 green on the first try (build-test 5 min 10 s); the postmortem commit re-ran it.

## Deviations from the docs
- `14 § Stage 1.2` "Adds" listed a right-click context menu; its own step 4, 08 and D-context-menu say there is none. 13 wins. The line was corrected in 14 (Q-021).
- 14's Verify reads the UI-test suite `dev.bathyon.tokenbe.uitests`, not the real domain (Q-014). 14 was updated (Q-020).
- Files beyond the inventory:
  - `Components/WindowFrameKeeper.swift`;
  - Core `Model/DashboardRange.swift`, `Presentation/WindowFrame.swift` and `Presentation/Debouncer.swift`;
  - `Tests/TokenBeUITests/UITestSupport.swift`.
- Debug-only `TOKENBE_TEST_RESET_SETTINGS` and `SettingsSuite.resetUITests` (Q-020).
- A behaviour fix to 0.2 production code: the drop report retries when the stream is full (item 6).
- `run.sh test` writes an xunit result, and the 0.2, 0.3, 0.4, 1.1 and 1.2 suite checks read it through `suite_passed` (Q-022).
- Test support: the `eventually` helper; `TestClock` throws for cancelled tasks and has `deadlines` and `waitUntil`.
- The `1.1.sh` D6 list no longer forbids `Open dashboard`, which arrived with its action in this stage.

## Judgment calls
- Q-020: Dashboard window details. Covers the frame source of truth, the restore rule, saving on close, the window title, the opening paths, the UI-test reset and the Verify suite.
- Q-021: the context-menu contradiction in 14.
- Q-022: stage checks read the test result file, not console text.

## Carry-forward actions
- PM-1.2-1 · agent · every stage with UI copy · Before verify, grep the source for every string the stage's D6 checks forbid; comments count. Name future controls generically in comments ("the refresh button"). Status: open (process).
- PM-1.2-2 · agent · every stage with UI tests · Each UI test that needs clean settings resets them itself; a test whose state a stage check reads must run last or be the only one that writes that key. Status: open (process).
- PM-1.2-4 · agent · 9.5 (reset, environment audits) · `Reset all settings…` should decide whether AppKit's window state in the standard domain (split widths) is reset too; Q-020 records that it lives there. Status: open.
- PM-1.2-5 · agent · every stage that adds a stage check · Helpers or snapshots used by more than one stage script live in `verify-stage.sh`; stage scripts run in subshells. Keep the Mac awake during verify with `caffeinate -dims` bound to the verify process. Status: open (process).
- PM-1.2-3 · agent · every stage that adds async tests · Before verify, loop the full parallel suite (≥ 50 runs, `swift test --skip-build`) and fix any flake. A new async test must wait on conditions with `eventually` or `TestClock.waitUntil`, never a fixed yield count. Status: open (process).
- Earlier open actions, unchanged by this stage:
  - PM-1.1-1 (check the screen lock before UI tests; process);
  - PM-1.1-2 (owner, optional `automationmodetool`);
  - PM-1.1-3 (crowded-menu-bar guidance, 3.5);
  - PM-0.4-3 (`chmod 600 .env`, owner);
  - PM-0.5-2 (coverage beyond 85 %, default 11.2);
  - PM-0.2-3 (`--from-tests` at 9.5);
  - PM-0.1-3 (Apple ID for H4 at 11.5);
  - process items PM-0.3-2, PM-0.4-2 and PM-0.5-1.
