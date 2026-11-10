# Postmortem — Stage 2.2 Observation plumbing & maintenance buttons
Date: 2026-11-10 · Branch: s2.2-observation · PR: #10 · Planned size: S · Commits: 7

## Outcome
The UI now reads the database through `ValueObservation` (04 I2).
- **Data path.** `observeSummaryInputs()` yields the current `SummaryInputs` at once, then again after every committed change, with duplicates dropped. Core's `AccountSummaryBuilder` maps the inputs to `[AccountSummary]` (04 I3). `AppModel` subscribes once startup step 2 has given `AppEnvironment` a repository, so the popover's account list is live. In 2.2 the inputs are `account` rows only, and the builder fills only the identity fields (Q-025).
- **Maintenance buttons.** Settings → Advanced has 08's `Run integrity check now` and `Back up now`, in 08's order.
  - The integrity check logs `db.integrity_check` and sets `tb.db.lastIntegrityCheckAt`. Its sheet shows `ok` or the first error line, and on failure the path of the copy.
  - The backup logs `db.backup`, writes `tokenbe.sqlite.bak` and sets `tb.db.lastBackupAt`. Its sheet shows the size, the time and the path.
  - If either call throws, `ui.error` is logged and the sheet shows the error.
- **Verification.** 136 Core tests pass, 7 of them new in `ObservationTests` and `AccountSummaryBuilderTests`. They run on the real database and on `MemoryRepository` alike. `AdvancedMaintenanceUITests` clicks both buttons under its own `TOKENBE_TEST_ROOT`. It asserts the sheets, the `.bak` file, `db.integrity_check ok`, `db.backup`, both `tb.db.*` writes, and zero error or fault records.

D1–D6 and D8–D11 are met; D12 by the PR's CI; D13 by this file and `phase-2.md`.

## What went as planned
- PM-2.1-3 was followed as written. `ObservationRepository` joins the `Repository` composition, and `MemoryRepository` implements it with the same semantics: the current value first, then one value per change.
- The ≥ 50-run loop (PM-1.2-3): `ObservationTests` and `AccountSummaryBuilderTests` passed 50 of 50 runs, and the full Core suite passed 50 of 50.
- The screen lock was checked before every UI run (PM-1.1-1). Static checks (lint, event table, secret guard, app build) ran standalone before the first full verify (PM-1.3-5). All passed first time.
- No new event, setting, dependency or Xcode project change. The UI-test folder is a synchronized group, so the new test file joined the target on its own.

## What went wrong
1. **`extension GRDBRepository: ObservationRepository` failed to compile** as a redundant conformance, because `GRDBRepository: Repository` already includes it through the typealias. Fixed by dropping the conformance from the extension. Cost: one build.
2. **A test closure read two actor properties under one `await`.** The compiler rejected the second read in the autoclosure. It was split into two awaited reads. Cost: one test build.
3. **The new UI test leaked the selected Settings tab.** The Settings window reopens on the tab last used in the UI-test suite. `AdvancedMaintenanceUITests` runs first alphabetically and left Advanced selected. `SettingsGeneralUITests` assumed General and could not find its first control. This is the shared-state pattern of PM-1.3-2, this time from AppKit window state rather than a 09 key. Fixed on both sides: the new test reselects General before quitting, and the 1.3 test selects General itself. Cost: one verify run, about 7 minutes.
4. **The `tb.db.*` check in `2.2.sh` read the UI-test settings suite after the whole UI run.** `DashboardShellUITests` resets that suite later in the same run (Q-020), so the keys were gone. The writes are now asserted inside the UI test from the app's own `app.settings_changed` records, which live in its test root. Cost: one verify run.
5. **The backup sheet first formatted its date with a system style.** 08 § Formatting rules fixes dates as `MMM d` through `Formatters`, which R2 requires. A pre-merge review caught it. The date now uses `Formatters.date`, plus the short time of day, for which 08 has no rule (Q-025). Cost: one commit and one verify run.

## Verify and CI failures
- Verify run 1: every check up to 0.4's UI run passed (148). `SettingsGeneralUITests` failed: `settings.general.launchAtLogin` not found (item 3 above). `AdvancedMaintenanceUITests` itself passed.
- Verify run 2: stages 0.1–2.1 all green, every 2.2 check green, including `AdvancedMaintenanceUITests passed`. Then `UI-test suite: tb.db.lastBackupAt set by the last UI-test run` failed with an empty value (item 4).
- Verify run 3: `STAGE 2.2 OK`, with 406 checks across stages 0.1–2.2 and D13, the UI suites included.
- Verify run 4, after the backup sheet's date was routed through `Formatters.date` (item 5): `STAGE 2.2 OK`, 406 checks.
- CI: PR #10 `build-test` passed on the first run (7 m 9 s): build, tests, coverage gate, lint, event-table check, app build and the secret guard. Main's push run for Stage 2.1 (#9) also passed (6 m 37 s), closing 2.1's D12.

## Deviations from the docs
- 14 § Stage 2.2 Verify tested `~/Library/Application Support/TokenBe/tokenbe.sqlite.bak`, the owner's real folder. That contradicts D10 and Q-014. The check now runs under the UI test's own root, and 14 is reworded (Q-025).
- 14 step 1 lists six input sources. 2.2 observes `account` only, because only identity fields exist yet (Q-025). 14 already says "the set grows per stage".
- Changed outside the inventory, all required by the stage:
  - `Repository.swift`: the typealias gains `ObservationRepository`.
  - `AppModel.swift`, `AppDelegate.swift`, `SettingsView.swift` and `Strings.swift`: step 1's subscription, step 2's wiring, and D8's copy.
  - `scripts/stages/1.3.sh`: "integrity" and "Back up" are no longer forbidden in `SettingsUI`; they arrive here. `scripts/stages/2.1.sh`: the typealias line it matches.
  - `Tests/TokenBeUITests/SettingsGeneralUITests.swift`: selects General explicitly.
  - `MemoryRepository`: implements the new aggregate.

## Judgment calls
- Q-025: observe `account` only, and identity fields only; skip a row the model cannot read, logged as `ui.error`; observation failure as `ui.error {view: "summary"}`, since 07 has no event for it and 14 says to reuse existing events; the sheet copy; no confirm dialog on these two buttons; the Verify location; the remembered Settings tab.

## Carry-forward actions
- PM-2.2-1 · agent · process · AppKit and SwiftUI state persists across UI-test launches too: window frames, the selected tab. A UI test either leaves the state it found or the next test sets it explicitly. Extends PM-1.3-2.
- PM-2.2-2 · agent · process · Never read the UI-test settings suite after the whole UI run for a key that a suite resetting it (Q-020) could clear. Assert such writes inside the test, from the app's log in its test root.
- PM-2.2-4 · agent · process · Before writing any user-visible number, date or size, grep 08 § Formatting rules and route it through `Formatters` if a rule exists.
- PM-2.2-3 · agent · 4.1–5.3 · `SummaryInputs` grows with each stage that fills an `AccountSummary` field: `paused` in 4.1, `poll_state` freshness in 4.2, balance and ledger in 5.3. Each addition needs an `ObservationTests` case that changes only that table.
- Earlier actions targeting 2.2: PM-2.1-3, closed (12b1b59). Phase 1's risk note, "2.2's maintenance buttons are the first destructive controls", closed: neither control destroys data. 08 gives no confirm dialog for them, and both were UI-tested only under a test root (Q-025).
