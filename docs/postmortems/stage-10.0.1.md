# Postmortem — Stage 10.0.1 Add and remove accounts from the sidebar; soak-safe verify
Date: 2026-11-18 · Branch: s10.0.1-sidebar-accounts · PR: #44 · Planned size: S · Commits: 6

## Outcome
The Dashboard sidebar now has `+` and `−` at its foot (08 § Dashboard window, Q-060):
- **`+`** opens Add account, the same steps as onboarding. A provider that already has an account reads `Added`. `+` is off once every provider the build offers has an account.
- **`−`** is on only while an account row is selected. It opens `Remove account…`'s confirm, which deletes the Keychain item and the account's rows. The selection then moves to Overview. The confirm and its action now exist once (`RemoveAccountConfirm` in `AccountsTab.swift`) and serve both Settings → Accounts and the sidebar.

So after the first account, more providers can be added and removed (01 S1).

`TB_SOAK=1` makes `verify-stage.sh` safe while the H5 soak runs on this Mac:
- UI tests are off.
- Every app launch check in 0.4, 2.1, 4.1 and 9.5 prints `skip`, and so does every check that reads what such a launch left behind.
- The three real-domain guards skip too (Q-061).

D1–D13 are met. **H5 opens with this merge:** the owner rebuilds the soak copy, adds the providers from `+`, and says "soak started". H2 and H3 stay open (owner).

## What went as planned
- **The advisor's review flagged five traps before any code:**
  - the checks that read a launch's log must skip too, or the error/fault checks pass on an empty log and prove nothing;
  - the exact greps in 3.5.sh and 4.1.sh that pin `AccountsTab`'s remove path;
  - an explicit `dashboardSelection = .overview` after a removal (the detail's nil fallback leaves `−` on);
  - keeping shared files (`AppModel`, `UITestSupport`) untouched, which keeps the UI selection small;
  - the real-domain guards failing during the soak.

  Each one is handled in this PR.
- **The xAI fixture probe** already had `FixtureTransport` routes (6.2), so the UI test onboards xAI without a new fixture.
- **`SidebarAccountsUITests` passed on its first run (58 s)**, once it compiled.
- **The dry run of 10.0.1.sh** (PM-1.3-5), sourced against `verify-stage.sh`'s helpers, passed every static check before the first verify.
- **No carry-forward targeted this stage.** Earlier actions that target 10.1 stay open: PM-8.1-2 and PM-3.5-4.

## What went wrong
1. **Compile error: `ctx: ["view": view]`.**
   - **Root cause:** the shared modifier takes its `view` as a `String` variable. `LogValue` is string-literal-expressible, but a variable is not converted.
   - **Fix:** `.string(view)`.
   - **Cost:** one rebuild.
2. **UI test compile error, plus Swift 6 isolation warnings.**
   - **Root cause:** `XCUIElement` has no `application` property. The new private helpers (`control`, `dashboard`, `isSelected`, `waitFor`) touched main-actor XCUI API from nonisolated functions, which warns.
   - **Fix:** `isSelected` takes the app and an identifier. The helpers are `@MainActor`. The suite compiles with zero warnings.
   - **Cost:** one extra UI run, about 1 min.

## Verify and CI failures
- **First cumulative guard sweep (`TB_SOAK=1`): `FAIL 0.1 swiftlint --strict`.**
  - **Cause:** the shared confirm took `AccountsTab.swift` to 411 lines, over SwiftLint's 400-line limit (`file_length`). Only the `build-app` and UI runs had been done, and they don't lint.
  - **Fix:** `IntervalOverrides`, which 4.1 added and nothing in this stage touches, moved unchanged to `SettingsUI/AccountIntervalOverrides.swift` (AccountsTab is now 340 lines). `RefreshPauseUITests` declares the new path (`// ui-covers:`). No stage grep reads that struct's body.
- **Second sweep: `TB_SOAK=1 scripts/verify-stage.sh 10.0.1` printed `STAGE 10.0.1 OK`.**
  - 122 checks printed `soak running` skips, 36 of them the launch checks of 0.4, 2.1, 4.1 and 9.5.
  - The rest were UI checks and the real-domain guards.
  - No app launched, and nothing else failed.
- **Full verify with UI tests on (`scripts/verify-stage.sh 10.0.1`): `STAGE 10.0.1 OK` on its first run.**
  - **UI suites (8 selected by Q-047):** LaunchSmoke, PopoverEmptyState, AppsBinding, DashboardShell, Drilldown, Onboarding, RefreshPause and SidebarAccounts. 10 tests, 0 failures, 422 s.
  - **The rest:** `swift test` 583 tests in 87 suites; `swiftlint --strict` 0 violations; every launch check of 0.4, 2.1, 4.1 and 9.5 ran and passed.

## Deviations from the docs
- **14 § Stage 10.0.1 Inventory:** adds two files, both corrected in 14 in this PR.
  - `Dashboard/DashboardView.swift`: the sidebar now takes the model, for its records and `showOnboarding`, instead of the account list.
  - `SettingsUI/AccountIntervalOverrides.swift`: moved out of `AccountsTab.swift` (`file_length`).
- **14 § Stage 10.0.1 step 2:** under the soak, the three real-domain guards (`real_untouched`, `real_tb_unchanged`, `real_support_unchanged`) print `skip` as well (Q-061). Added to 14 in this PR.
- **The step-2 helper:** 4.1's two cadence checks need both the soak gate and their suite selection, so they go through a second helper, `launch_check_for <Suite>`.
- **08 § Dashboard window:** the sidebar line gains the `+` / `−` foot (Q-060; 01 S1 outranks 08's omission, 12 § R1). 14 § 13.4 maps it to 10.0.1.
- **The confirm's button id** stays `settings.accounts.confirmRemove` in both places, because the confirm is shared, not copied.

## Judgment calls
- Q-061 · Real-domain guards skip while the soak runs (A: one branch in `check`, rather than a list of ignored keys and files that would drift).

## Carry-forward actions
- PM-10.0.1-1 · agent · 11.5 · After the soak ends, run `TB_UI_TESTS=1 scripts/verify-stage.sh <id>` without `TB_SOAK`: every UI suite, every launch check and the real-domain guards (Q-047, Q-060, Q-061).
- PM-10.0.1-2 · Nikola · H5 · Rebuild the soak copy, launch it without a test root, add OpenAI, DeepSeek and xAI from the sidebar's `+`, and say "soak started <date>" (14 § Stage 10.0.1, Human gate).
- Earlier actions that target this stage: none.
