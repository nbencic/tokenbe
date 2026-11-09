# Postmortem — Stage 1.1 Composition root, AppModel, popover empty state, glyph states
Date: 2026-11-09 · Branch: s1.1-popover-shell · PR: #6 · Planned size: M · Commits: 7

## Outcome
Clicking the menu-bar glyph opens the popover of `08` in its **Empty** state:
- the header shows the title;
- the body reads `No accounts yet` / `Add a provider key to start tracking.`;
- the footer has `Quit` (⌘Q).

The plumbing behind it:
- `AppEnvironment` (settings, clock, log sinks) is injected with `.environment(\.appEnvironment)`.
- `AppModel` lives in the app delegate and receives the environment after startup step 1.
- `MenuBarGlyph` draws the three shapes (`solid`, `notched`, `dashed`); `AppModel.glyphState` is always `.solid` until 4.2/5.5.
- Opening and closing the popover logs `ui.popover_open` / `ui.popover_close {dur_ms}` through a Core `PopoverTracker`.

Core gained `AccountSummary` (the full value type of 14, mostly optionals), `Band`, `Money`/`Currency` and `Formatters`. `Formatters` covers money, estimates, runway, tokens, freshness and dates, pinned to `en_US_POSIX` and `de_DE`.

Verification:
- 77 Core tests pass; TokenBeCore line coverage is 94.42 % (1625/1721) (gate 85 %).
- `PopoverEmptyStateUITests` opens the popover, checks the identifiers and copy, closes it with Escape, reopens it and quits. It then checks both log events and the removed sentinel, all under `TOKENBE_TEST_ROOT`.
- The popover views carry 12 accessibility identifiers (≥ 6 required).

DoD D1–D3, D6 and D8–D11 are met. D12 is met by PR #6's green CI. D13 is met by this file.

## What went as planned
- The composition root slotted into 0.4's startup without reordering anything. `Settings` is still created only after logging is configured (04).
- The D6 rule ("a control appears in the stage that implements its action") was easy to enforce mechanically. `1.1.sh` fails if `Add account`, `Open dashboard`, `Settings…`, `Pause polling` or a refresh icon appears in the popover early.
- CI on Xcode 16.4 / Swift 6.1 passed on the first run. PM-0.5-1 (write for 6.1) was followed from the start: no trailing commas in argument lists, no 6.2-only isolation.

## What went wrong
1. **`Formatters` trapped on `Int64` overflow** in the first test run:
   - `abs(Int64.min)` in money;
   - `count * 100` in tokens for counts near `Int64.max`;
   - `(value + divisor / 2) / divisor` rounding near the top of the range.

   Found by the extreme-value cases I added to the tests: the first `swift test` run crashed the test process. Fix: an `absolute` helper that maps `.min` to `.max`, `roundedQuotient` (quotient plus a remainder comparison, no addition), and `multipliedReportingOverflow` with a fall-back to zero decimals. Cost: one test run.
2. **`Settings` was ambiguous in the app target.** SwiftUI has its own `Settings` scene type, so `AppEnvironment.settings: Settings` didn't compile. Fix: spell it `TokenBeCore.Settings` (Q-018). Cost: one build.
3. **SwiftLint `--strict` rejected two `large_tuple` test tables** in `FormattersTests` (the money and token cases). Fix: a small `Case` struct for money; the token cases became `(count, texts)` pairs. Cost: one lint run. A `try? await Task.sleep` in `PopoverTrackerTests`, which would have hit the silent-catch rule, was caught before running and became `try` in a throwing test.
4. **The UI tests could not run while the Mac was locked.** `xcodebuild test` failed with `Timed out while enabling automation mode`, because the console session was locked (`IOConsoleLocked = true`) and macOS asks for authentication to enable Automation Mode. The owner was away from the Mac; the stage waited until the screen was unlocked.
   - Everything else (build, unit tests, lint, the app build, CI) was green before that, so the wait cost wall-clock time only.
   - Running `sudo automationmodetool enable-automationmode-without-authentication` once removes the authentication prompt, but not the lock. UI tests need an unlocked, logged-in console session.
5. **The first real UI-test run failed: the click never opened the popover.** The test was written while the Mac was locked, so it had never run. The app's element tree at the failure had a status item but no window. The test's screen recording showed no TokenBe ring in the menu bar, only macOS's overflow chevron `«` at the item's accessibility frame.
   - With about 20 status items and the notch, macOS keeps TokenBe's item in the overflow. The system's layout file (`com.apple.MenuBar`) stores TokenBe at 675 pt from the trailing edge. The first click only reveals the item.
   - Fix: the test clicks up to twice until the popover's element appears (Q-019). The app is unchanged; on a crowded menu bar the owner will see the same overflow.
   - The next run found that the popover's `StaticText` elements have empty labels on macOS; the string is the accessibility value. Fix: the test reads `value`, falling back to `label`.
   - Run 4 then found no `ui.popover_open` in the log: the app had logged at `info`. **The UI-test runner is sandboxed**, so the test's `UserDefaults(suiteName:)` writes (debug level, and the suite reset) went into the runner's own container, never reaching the app. Fix: the setting goes to the app as a launch argument (`-tb.log.level debug`), which every `UserDefaults` instance in the app reads. The no-op suite reset was removed, and each test root is now deleted in `tearDown`.
   - Cost: four UI-test runs. Lesson: a UI test written without running it is a draft, not a test.
6. **I read a stale coverage figure.** Running `coverage-gate.sh` by hand after the verify run reported 94.31 %, exactly 0.5's figure. Verify had stopped at the UI-test failure before 0.5's `swift test --enable-code-coverage`, so the gate read 0.5's JSON. CI is unaffected, because it always runs the tests with coverage first.
   - Fix: the gate now refuses coverage data older than any Core source or test file. The fresh figure is 94.42 %.

## Verify and CI failures
- `swift test` run 1: the test process crashed on the overflow traps (item 1). Run 2: 77 tests green.
- `build-app` run 1: the `Settings` ambiguity (item 2). Run 2: green.
- `lint` run 1: item 3. Run 2: clean.
- `uitest` runs 1–2: `Timed out while enabling automation mode` (item 4).
- After the unlock, `verify-stage.sh 1.1` run 1: `FAIL 0.4 UI tests` (item 5: the popover never opened).
- `uitest` run 3: `"" is not equal to "No accounts yet"` (item 5: the static-text label). Run 4: `0 is less than 2` popover opens in the log (the sandboxed runner, item 5). Run 5: both UI tests green.
- `verify-stage.sh 1.1` run 2 (with this file): `FAIL 1.1 popover has no 'Add account' yet`. My own D6 check matched a code comment in `EmptyStateView.swift` that named the future button; the check had never run before, because earlier runs stopped at the UI tests. The comment was reworded.
- Run 3: `STAGE 1.1 OK`.
- CI run 42659916592 on PR #6: green in 5 min 10 s on the first try.

## Deviations from the docs
- `08`'s runway example now reads `~12 d · ~9 d today`, matching `05`'s formatting rules (`05` wins under 12 R1).
- Files beyond the inventory: `Presentation/PopoverTracker.swift` (Core, so the open/close events are unit-tested), `Components/MenuBarGlyph.swift` (listed in the steps but not in the inventory) and `PopoverTrackerTests` (in `FormattersTests.swift`).
- The provider glyph on account cards is left out until artwork exists. Cards aren't rendered before Phase 3, and `08` names no asset (Q-018).
- `coverage-gate.sh` now fails (exit 2) when the coverage JSON is older than any Core source or test file (item 6). Not asked for by 10; it guards against reading stale data.
- `tb.ui.hideCents` is read by the formatter callers, not by `Formatters` itself. `Formatters` takes `hideCents` as a parameter so it stays pure; the card view reads the setting.

## Judgment calls
- Q-017: formatting details that 08 and 05 leave open. Integer-only, overflow-safe arithmetic; English month names computed by hand rather than with Foundation date styles, whose output differs between macOS 15 and 27.
- Q-018: popover shell details. `PopoverTracker` in Core, `AppModel` owned by the app delegate, no provider glyph yet, and the `TokenBeCore.Settings` spelling.
- Q-019: UI tests on a crowded menu bar. The test clicks through the overflow; it doesn't touch the owner's menu-bar layout or add a test-only hook that opens the popover.

## Carry-forward actions
- PM-1.1-1 · agent · every stage with UI tests · Before running `uitest`, check `ioreg -n Root -d1 -a | plutil -extract IOConsoleLocked raw -`. If it prints `true`, finish everything else in the stage first and ask the owner to unlock, instead of burning test runs on automation-mode time-outs. Status: open (process).
- PM-1.1-3 · agent · 3.5 (onboarding) · On a crowded menu bar TokenBe's glyph sits behind macOS's overflow `«`, which defeats an at-a-glance monitor. 08 doesn't cover it. In onboarding, consider first-run guidance (⌘-drag the glyph to the right) or a notification when the item is hidden. Status: open.
- PM-1.1-2 · Nikola · optional · Run `sudo automationmodetool enable-automationmode-without-authentication` once, so UI tests don't ask for a password after each reboot. Status: open.
- Earlier open actions, unchanged by this stage:
  - PM-0.4-3 (`chmod 600 .env`, owner);
  - PM-0.5-2 (coverage beyond 85 %, default 11.2);
  - PM-0.2-3 (`--from-tests` at 9.5);
  - PM-0.1-3 (Apple ID for H4 at 11.5);
  - process items PM-0.3-2, PM-0.4-2 and PM-0.5-1.
