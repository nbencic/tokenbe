# Postmortem — Stage 7.1 Apps bound to provider keys
Date: 2026-11-15 · Branch: s7.1-apps-by-key · PR: #30 · Planned size: L · Commits: 6

## Outcome
An OpenAI account's page shows a **By app** table (08 `20N-0`). Each row is one provider key, with:
- the key's hint and the `key` badge;
- its requests, tokens (a stacked mini-bar by class), spend and share.

Its `Total` equals the numbers strip's `Spend in range` (01 A2). An unbound key shows the provider's key name, and offers `Name…`, which creates an app and binds the key. Settings → Accounts → Keys & apps has a `Bound app` picker with `New app…`. The Overview lists `Apps this period`. The sidebar's `Apps` page edits display names; the name is the immutable harness tag (O-13). Each popover card can expand row 4, today's top apps, and remembers that in `tb.popover.expanded.<provider>`.

The stage opened with Q-047, the owner's change-based UI-test selection (the first task the phase-6 handoff named). This branch changes `AppModel`, so its verify selected every suite. D1–D13 are met. Gates H2 and H3 are still open (PM-3.6-1, PM-6.1-1, PM-6.2-1) and do not block.

## What went as planned
- **Q-047 first, then the stage.**
  - Each suite declares its paths on `// ui-covers:` lines. `scripts/ui-select.sh --explain` says why each suite runs.
  - Every `ui_check` finds the suite its command names and prints `skip` when that suite did not run. 1.3's settings checks and 4.1's cadence run name their suite with `ui_check_for`.
  - The selection logic was tested dry with a stubbed `check` before any UI run (the advisor's point). It skipped and ran the right checks.
- **One day rule.** `Attribution` uses `Spend.daily`, so the table's total and the strip's `Spend in range` agree by construction. `AttributionTests` asserts the equality on hand-built inputs (507 ¢ across a per-key cost day, a total-only day and the open day) and on observed fixture polls.
- **Repository method names** follow 14 § 2.1 step 5: `upsertApp, fetchApps, bind, unbind, fetchBindings`. A new app and its binding are one transaction (R7).
- **The data reaches the UI only through `ValueObservation`.** `SummaryInputs` gains apps, bindings, provider keys and the per-key aggregates. `ObservationTests.appTables` changes each table alone (PM-2.2-3). So a binding made in Settings renames the By-app row at once, as `AppsBindingUITests` shows.
- **The guard sweep (PM-5.3-4)** found nothing to change: no earlier absence check names a 7.1 control. 7.1's static checks passed when run on their own (PM-1.3-5).
- **Fixtures agreed.** The OpenAI usage, cost and key-list fixtures share `key_fixture_a1b2` and `key_fixture_c3d4` with redacted values, so the UI test could bind keys and read hints.
- **Verify run 1 with UI off** (`TB_UI_TESTS=0`): every stage check passed. Only D13 failed, for this file.

## What went wrong
1. **The Dashboard's account page was wider than its window, so the sidebar could not be clicked.**
   - **Symptom:** `AppsBindingUITests` failed with `Unable to find hit point` on the sidebar's `Apps` row. The tree showed a 920 pt window holding a 1 360 pt split view. The sidebar was drawn at x = 55, outside the window at x = 275.
   - **Root cause:** a 4.2/5.1 bug, not 7.1 code. The Sources strip was an `HStack` of non-wrapping lines: four OpenAI sources plus the price chip, about 1 100 pt. That minimum width forced the detail column wider than the Dashboard's 920 pt minimum. No earlier UI test clicked the sidebar while an account page was open.
   - **Fix:** the strip's columns wrap in an adaptive grid (200 pt minimum).
   - **Cost:** 3 single-suite UI runs (one was a `debugDescription` dump).
2. **Closing Settings with ⌘W left another app's window in front.** **Fix:** the test calls `app.activate()` before it clicks the sidebar. Cost: 1 UI run.
3. **Row 4's text is inside its button, so it is the button's label.** Its own identifier is not exposed. **Fix:** the test reads the button's label; the inner identifier was removed. Cost: 1 UI run.
4. **A failed run left `tb.popover.expanded.openai = true` in the shared UI-test suite.** The next run's "collapsed" assertion then failed. **Root cause:** PM-1.2-2's pattern. **Fix:** the test collapses the row first if it finds it expanded, and ends collapsed. Cost: 1 UI run.
5. **The numbers strip's cell exposes its text as the element's value, not its label.** **Fix:** the test reads `label + value`. Cost: 1 UI run.
6. **Small compile and lint issues:**
   - an exclusivity violation in `Attribution.totals` (`totals[id]?.spend = …totals[id]…`);
   - `Strings.appName` already existed (the new one is `appNameField`);
   - `SummaryInputs.fetch` and the UI test exceeded `function_body_length`;
   - `AccountsTab.swift` passed 400 lines, so the picker moved to `BoundAppPicker.swift`.

   Each cost one build or lint run.
7. **2.2's "empty initial value" test** compared the first `SummaryInputs` with an empty one. The migration's `unassigned` app is now part of it. **Fix:** the test drops the sentinel before comparing. Cost: one `swift test` run.

## Verify and CI failures
- `swift test`: 1 failure on the first run (item 7); then 471 tests in 76 suites passed.
- `swiftlint --strict`: 3 violations on the first run (item 6); clean after.
- `AppsBindingUITests` alone (`TB_UI_ONLY`): 5 failing runs (items 1–5), then it passed in 72 s.
- Verify run 1 (`TB_UI_TESTS=0`): all stage checks `ok`; `FAIL D13 postmortem stage 7.1` (this file did not exist yet).
- Verify run 2 (UI on, every suite selected because `AppModel.swift` changed): see the PR description for the summary lines.

## Deviations from the docs
- **08:**
  - an unbound key shows the provider's key name, per 01 A2 ("human key names"); `(unnamed key …a9f2)` only without a name. 01 wins over 08 (R1).
  - row 4's `other` rule and when it shows;
  - the Apps page's content and empty state.
- **11:** `AttributionTests` lists the key-path cases.
- **14:**
  - § 0: the UI-test paragraph describes Q-047.
  - § 7.1: the inventory names every touched file, including `BoundAppPicker.swift`, `SourcesStrip.swift` and Q-047's scripts. The tests add `ObservationTests.appTables`.
  - § 11.5: the full UI suite runs once (`TB_UI_TESTS=1`).

## Judgment calls
- Q-047 · UI tests run only for the suites that cover changed code (the owner's request; supersedes Q-031 and Q-041).
- Q-048 · app-attribution rules the docs leave open. These include:
  - the day rule and the remainder;
  - keyless usage → `Unassigned`;
  - unbound key names;
  - one row per key;
  - row 4's `other`;
  - the slug edges;
  - the sentinel;
  - the Apps page's copy;
  - the Sources strip fix;
  - `Strings.swift`'s `file_length`.

## Carry-forward actions
- PM-7.1-1 · agent · 7.2 · The By-app table gains the `≈ split`, `harness` and `inferred` paths in `Attribution.swift`, and the empty-table link `Report apps from your harness →`. Accounts without per-key usage (DeepSeek, xAI) show no table until then.
- PM-7.1-2 · agent · 7.3 · `Apps this period` rows become buttons (filter the account page by app). The `Unassigned` row that 7.1 shows for keyless provider usage should match 7.3's harness `Unassigned` surfacing.
- PM-7.1-3 · agent · every stage with UI tests · A UI test that clicks a Dashboard element after closing Settings or a sheet calls `app.activate()` first. A test that toggles a shared setting puts it in a known state before asserting.
- PM-7.1-4 · agent · 11.3 · Check the Dashboard's other pages at the 920 pt minimum width against Paper (the Sources strip was one overflow). The By-app table's look follows 08's text; Paper Desktop was not used.
- PM-7.1-5 · agent · 11.5 · Run the full UI suite once (`TB_UI_TESTS=1 scripts/verify-stage.sh 11.5`, Q-047).
- Earlier actions that targeted 7.1: none. PM-6.1-3 and PM-6.2-2 target 7.2. Process actions applied here: PM-5.3-4 (the guard sweep), PM-1.3-5 (dry run of the static checks), PM-1.1-1 (screen unlocked), Q-039 (99 GiB free).
