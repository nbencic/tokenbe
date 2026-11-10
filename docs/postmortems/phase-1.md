# Postmortem — Phase 1 App shell
Date: 2026-11-10 · Stages: 1.1 (#6), 1.2 (#7), 1.3 (#8)

## Outcome vs. phase map
14 § 0.5: "Full window/menu chrome with real empty states; preferences work."
- **Menu chrome:** met.
  - The code-drawn glyph has three shapes; state wiring lands in 4.2/5.5.
  - The popover has the real Empty state and a footer with `Open dashboard` (⌘D), `Settings…` (⌘,) and `Quit`.
  - ⌥-click opens the Dashboard.
- **Window chrome:** met.
  - Dashboard: `NavigationSplitView`, the Overview empty state, a range picker, and frame and range memory.
  - Settings: General, Privacy and Advanced.
- **Preferences work:** met for every key whose tab exists. One deliberate exception: the menu bar metric is stored now and drawn in 5.5.
- **One spec item cannot be met as written:** the global shortcut toggles the Dashboard, not the popover (Q-023).

## Patterns across stages
1. **`MenuBarExtra` is the phase's hard constraint.** It has no right-click (D-context-menu), unreliable modifiers (O-15, which happened to work), and on macOS 26+ no way to open it from code (Q-023). Each limit was absorbed by downgrading a feature inside the 04/08 rule, never by an AppKit workaround. The remaining risk: any later feature that needs to open the popover programmatically, such as a notification's `Open` action (5.4), must target the Dashboard too. Noted for 5.4.
2. **UI tests on the owner's real Mac are the slowest and riskiest part of a stage.** Their cost came from four sources:
   - the menu-bar overflow (1.1);
   - a sandboxed runner (1.1);
   - the screen locking during verify (1.1 and 1.2);
   - AppKit writing the real defaults domain (1.2).

   Each became a structural fix:
   - overflow-aware helpers;
   - launch-argument settings;
   - a lock check and `caffeinate` scoped to verify;
   - a guard on the real domain's `tb.*` keys.
3. **Shared state between tests and cumulative checks.** UI tests share one settings suite, and later stages' checks run before or after them in every verify. Three times a value one test left behind would have broken another stage's check: the `30d` reset (1.2), the subshell helper (1.2) and the log level (1.3). The rule now: think through every value a test leaves (PM-1.2-2, PM-1.3-2).
4. **Flaky async tests were a real cost once (1.2), then prevented.** About 900 test runs found a real production bug in the 0.2 drop report and three test-harness defects. The ≥ 50-run loop is now routine (PM-1.2-3).
5. **My own D6 greps were wrong in both directions.** A comment tripped one (1.1, 1.2), and a case-insensitive grep would have matched everything (1.3). Running each check's grep by hand before verify catches both (PM-1.2-1).

## Plan and doc changes
- Applied during the phase:
  - `09`: the `tb.ui.shortcut` effect (Q-023);
  - `14`: the Stage 1.2 "Adds" line with no context menu (Q-021); 1.2's Verify reads the UI-test suite (Q-020); 1.3's test line (Q-023).
- Q-017 to Q-023 logged.
- `verify-stage.sh` gained `suite_passed` (xunit, Q-022) and the shared real-settings guard.
- Proposed for later phases:
  - 5.4: the notification's `Open` action cannot open the popover (Q-023). It should open the Dashboard, scrolled to the account (the account page arrives in 4.2). To decide at 5.4 per R3.
  - 8.4 (accessibility & input): keyboard access to the popover. It is reachable by clicking only (Q-023); VoiceOver users reach it through the menu bar as usual.

## Gates and risks
- **No human gate in Phase 1.**
- **The owner's optional actions** remain PM-1.1-2 (`automationmodetool`) and PM-0.4-3 (`chmod 600 .env`).
- **H2** is next, at 3.6.
- **Risks for Phase 2 (Storage):**
  - GRDB migrations under Swift 6.1 strict concurrency on CI;
  - keeping the database out of the owner's real Application Support folder in every test (`TOKENBE_TEST_ROOT` already covers the app; Core tests must use temporary directories);
  - 2.2's maintenance buttons are the first destructive controls, so their confirm dialogs must be UI-tested under a test root only.

## Open carry-forward actions
- PM-1.3-1 · agent · process · Spike OS-control features first; check 04/08/13 before choosing a fallback.
- PM-1.3-2 · agent · process · Check what each value a UI test leaves does to earlier launch checks.
- PM-1.3-3 · agent · 5.5 · Draw `tb.menubar.metric`.
- PM-1.3-4 · agent · 8.4 / 11.4 · Shortcut documentation and recorder accessibility.
- PM-1.2-1, PM-1.2-2, PM-1.2-3, PM-1.2-5 · agent · process · D6 greps by hand; UI-test state; ≥ 50-run loop; shared helpers in `verify-stage.sh` and `caffeinate` during verify.
- PM-1.2-4 · agent · 9.5 · Whether `Reset all settings…` also resets AppKit's window state.
- PM-1.1-1 · agent · process · Check the screen lock before UI tests.
- PM-1.1-2 · owner · optional · `sudo automationmodetool enable-automationmode-without-authentication`.
- PM-1.1-3 · agent · 3.5 · Crowded-menu-bar guidance in onboarding.
- Phase 0's open actions: PM-0.1-3 (H4 Apple ID, 11.5); PM-0.2-3 (`--from-tests`, 9.5); PM-0.3-2, PM-0.4-2 and PM-0.5-1 (process); PM-0.4-3 (owner, `.env` permissions); PM-0.5-2 (owner, coverage, 11.2).
