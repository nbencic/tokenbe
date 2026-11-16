# Postmortem — Stage 7.3 Drilldown polish
Date: 2026-11-16 · Branch: s7.3-drilldown · PR: #33 · Planned size: S · Commits: 7

## Outcome
Every path from the Overview to an app's spend now works without a console.
- **Drilldown:** an Overview `Apps this period` row is a button. It opens the account page filtered to the app.
  - Core picks the account where the app spent most in that currency (`Attribution.drilldownAccount`).
  - The By-app title carries `App: <name>` with ✕. Only the app's rows show, under `App total`.
  - ✕ clears the filter, and so does leaving the account. The filter is never persisted.
- **Drift chip:** beside the band pill, `Harness drift · Nov 14 · −$4.02` (` · N days`).
  - Core computes the drifting closed days of the range (`AccountSummary.harnessDrift`) with `tb.alerts.driftThresholdPct`, under the same rule as the daily `ledger.harness_drift`.
  - Changing the threshold rebuilds the summaries.
- **Unassigned:** keyless provider usage and a harness day without lines are both the sentinel's `Unassigned` row, with element id `unassigned`, and both can be filtered.

D1–D12 are met. Gates H2 and H3 are still open (owner) and do not block.

## What went as planned
- **The advisor's review came before any view code.** It moved the threshold into `SpendContext` (drift is not a band), put the chip in the header (above the fold, so PM-7.2-6's lazy grid does not hide it), and defined the empty filtered state and the `App total` relabel up front.
- **Core first:** every figure the UI shows is computed and tested in Core: the drift days, the drilldown account, the filter and its total, the `unassigned` id, the UTC day label and the signed amount (`AttributionDrilldownTests`, `FormattersTests`).
- **The guard sweep ran before the first verify** (PM-7.2-4), but only in part; see What went wrong 2. 7.1's "Apps this period rows are not buttons yet" check would have failed. It now checks that the rows come from `Attribution.totals`.
- **A draft PR went up as soon as Core and the views compiled** (PM-7.2-5).

## What went wrong
1. **The screen locked again** (`IOConsoleLocked = true`, 03:36). It happened between runs, while no `caffeinate` held the display. The first `DrilldownUITests` run timed out at onboarding's first query, so no 7.3 UI code ran. **Fix:** keep `caffeinate -dims` running for the whole session, not only during each wait. See Verify and CI failures for the UI runs.
2. **The guard sweep missed 4.2's and 5.2's checks.** The first `TB_UI_TESTS=0` verify failed at stage 4.2: its grep matched the whole `AccountDetailView(model: model, summary: account)` call, and DashboardView now passes `filter: $appFilter`. The rerun then failed at 5.2, whose grep matched `.uiDashboardRange])`, the last line of `freshnessKeys` before 7.3 added the drift threshold. The sweep had grepped the stage scripts for the edited file *names*, but these checks name the file by a `$app/Dashboard/…` path built from a variable, and the scripted sweep hung before it printed anything. **Fix:** 4.2 matches the call by its prefix; 5.2 looks for the key inside `freshnessKeys`. A cumulative `TB_UI_TESTS=0 scripts/verify-stage.sh <id>` *is* the sweep. Run it first instead of a hand-made grep (PM-7.3-2).

## Verify and CI failures
- **UI run 1** (`DrilldownUITests`): timed out at onboarding's first query because the screen was locked (What went wrong 1). No 7.3 code ran.
- **`TB_UI_TESTS=0` runs 1–3:** FAIL 4.2, then FAIL 5.2 (What went wrong 2), then FAIL 7.3 "Core filters the By-app rows". 7.3's own negative grep `byApp\.(reduce|filter)` matched the accessibility id `dashboard.account.byApp.filter`. **Fix:** it now greps for `summary\.byApp\.(reduce|filter)`.
- **UI run 2** (`DrilldownUITests` alone): passed, 49 s.
- **Full verify 1:** FAIL 0.4 because `DashboardShellUITests.testOptionClickOpensDashboard` failed ("⌥-click opens the Dashboard"); 21 of 22 tests passed in 19 min. This is PM-4.1-4's flake: the runner logged `(inf, inf, 0.0, 0.0)` for the status item. Run alone, the suite passed both cases in 63 s, and that run logged the same `inf` rect, so the rect alone does not cause the failure. No 7.3 file touches the ⌥-click path. Disk: 98 GiB free, and the runner was not killed (Q-039).
- **Full verify 2:** `STAGE 7.3 OK`. 519 Core tests in 78 suites passed, and all 22 UI tests passed with 0 failures in 19 min.
- **CI:** green on every pushed head checked (5b220e8, 39729a4).

## Deviations from the docs
- **08:** the Overview row click names its account; the header's drift chip; the filtered By-app table (chip, `App total`, the empty line).
- **14 § 7.3:** the full inventory (the Overview, Dashboard and Core files, `AppModel` for the threshold) and the Core tests.
- **Earlier stage scripts:** 7.1's "rows are not buttons yet" check now checks that the rows come from Core.

## Judgment calls
- Q-050: which account a row opens; what the filter matches and resets; the filtered `Total`; the drift chip's day, placement and copy; the two `Unassigned` paths.

## Carry-forward actions
- PM-7.3-1 · agent · every stage · Keep `caffeinate -dims` running in the background for the whole session (not only inside a wait), and check `IOConsoleLocked` before every UI run.
- PM-7.3-2 · agent · every stage · The guard sweep is a cumulative `TB_UI_TESTS=0 scripts/verify-stage.sh <id>` run before the first full verify, not a grep for file names.
- PM-7.3-3 · agent · 8.4 · PM-4.1-4 recurred (full verify 1). In 8.4, which reworks the UI tests' layout and accessibility, log `app.statusItems.firstMatch.frame` and `app.debugDescription` around the ⌥-click. If the frame is `inf`, wait for a finite frame before the click.
- PM-7.2-6 · agent · 8.4 · moved from 7.3: no 7.3 element sits in the lazy `SourcesStrip`. VoiceOver needs every chip, so 8.4 swaps the grid for a non-lazy wrapping layout.
- Earlier actions closed here:
  - PM-7.1-2 (rows become buttons; the two `Unassigned` rows match): closed (30e0bba, `AttributionTests.unassigned`, `DrilldownUITests`).
  - PM-7.2-2 (the drift chip reads the harness drift; `Unassigned` matches): closed (`AttributionTests.harnessDrifts`, `builderDrift`).
- Process actions applied: PM-7.1-3, PM-7.1-6, PM-7.1-7, PM-7.2-4, PM-7.2-5, PM-1.1-1.
