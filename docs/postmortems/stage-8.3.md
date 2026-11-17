# Postmortem — Stage 8.3 CSV export of the current view
Date: 2026-11-17 · Branch: s8.3-csv-export · PR: #37 · Planned size: S · Commits: 4

## Outcome
The Dashboard toolbar has `Export…` (O-4, 08 § Dashboard window). It opens an `NSSavePanel` sheet that suggests `TokenBe-<page>-<label>-<range>-<UTC date>.csv` and writes an RFC 4180 CSV of the current page's table (Q-053):
- the Overview's runway board, in the screen's sort order;
- an account page's By-app table under its app filter, with the `Total` / `App total` footer;
- the Apps page's list (App, Harness tag, Key).

Each cell is the string the page prints. It comes from the same function the view draws from (`RunwayBoard.cells`, `ByAppTable.cells` / `totalCells`, `AppsPage.keys`), so the file cannot disagree with the screen. Core's `ViewCSVExporter` writes UTF-8 without a BOM, with CRLF after every record, and quotes only the fields that need it. The write is atomic and logs `db.export {kind: csv_view, path, rows}`. A failed write logs `ui.error` and shows an alert.

D1–D12 are met. Gates H2 and H3 are still open (owner) and do not block.

## What went as planned
- **Core first.** `CSVExporterTests` covers quoting, the header, CRLF, no BOM, the write and its log, and the file name. All 547 Core tests in 82 suites passed on the first run of the new suite.
- **One cell function per table.** The view and the CSV read the same builder, so 7.3's filtered footer and `Hide cents` carry over without a second formatting path.
- **No new entitlement.** The app is not sandboxed, so the save panel needed nothing.
- **The UI test never presses Save.** DrilldownUITests opens `Export…` on the filtered account page, checks the suggested name and presses Cancel. 8.3.sh fails if any UI test clicks a `Save` button, so a test can never write into the owner's folders.
- **Lint gated the push** (`&&`, PM-8.2-5): the first commit and the draft PR went up only after a clean lint.

## What went wrong
1. **The cumulative guard sweep failed three times in a row, one earlier check per run.** `verify-stage.sh` stops at its first failure, so each run exposed only one stale check:
   - `1.2 Dashboard has no 'Export' yet` and `4.2 Dashboard has no 'Export' yet (8.3)`: both D6 guards were waiting for this stage. They are retired, and their comments now point at 8.3.sh, as 4.2 did for `Refresh`.
   - `7.3 a filtered table's footer reads App total (Q-050)` grepped the exact text `filter == nil ? Strings.total : Strings.appTotal`. The footer moved into the shared `totalCells(…, filtered:)`. The check now reads the new expression and the call that passes the filter.
   - **Root cause:** PM-7.3-2's warning applied again. Before the first sweep, only file names were grepped. A grep of `scripts/stages/` for the control's name (`Export`) and for the rewritten expressions would have found all three at once.
   - **Fix:** 66df253.
   - **Cost:** three sweep runs instead of one, plus an extra run after the session break.
2. **DrilldownUITests failed on its first run.** It expected the suggested name to end in `.csv`, but the save panel hides the extension in its name field. **Fix:** the test checks the name's prefix (page, label, range). The `.csv` type is still enforced by `allowedContentTypes` (8.3.sh). **Cost:** one Drilldown rerun (about 1 min).
3. **Lint flagged a test's cleanup.** `CSVExporterTests` removed its temp folder in a `do { } catch { }` (`tokenbe_no_silent_catch`). **Fix:** it uses the shared `TempDirectory` support type, like the other file tests. Caught before the commit; it cost one lint run.

## Verify and CI failures
- **Core and lint:** 547 Core tests in 82 suites passed. The one lint violation (What went wrong 3) was fixed before the first commit.
- **DrilldownUITests alone:** failed run 1 (What went wrong 2), then passed.
- **Guard sweep** (`TB_UI_TESTS=0 verify 8.3`), run four times:
  - FAIL 1.2, then FAIL 4.2, then FAIL 7.3 (What went wrong 1);
  - after 66df253, every check passed (1 350) except D13 (this postmortem, not yet written).
- **Full verify** (Q-047 selected 6 suites: LaunchSmoke, PopoverEmptyState, AppsBinding, DashboardShell, Drilldown, HarnessIngest): `STAGE 8.3 OK` on the first run, with 1 360 checks passed. The UI suites ran 7 tests with 0 failures in 4 min 18 s. The checks of the suites Q-047 did not select print `skip` (26). Disk had 89 GiB free, and the screen was unlocked.
- **CI:** green on the PR head that carries this postmortem (see PR #37); no CI failure on the way.

## Deviations from the docs
- **08 § Dashboard window:** `Export…` now says what each page exports and that each cell is written as shown (Q-053).
- **14 § 8.3:** the inventory now names the App files that share the cell functions, and the `ui.error` event. The tests now list the CRLF, write and file-name cases and DrilldownUITests.
- **14 § 13.6:** the test matrix listed `CacheSavings/ChartData 8.2 · CSVExporter 8.3` twice (one duplicate from 8.2, one from this branch); it now lists each once. Drilldown is listed as 7.3/8.2/8.3.

## Judgment calls
- Q-053: which table each page exports; the filter, footer and sort; cell text as the screen prints it (the `Attribution` header for the By-app badge column); the RFC 4180 details; the file name and its sanitizing; the `db.export` fields; the panel; a UI test that cancels.

## Carry-forward actions
- PM-8.3-1 · agent · 9.2, 9.4, 9.5 · 1.3.sh still guards `Settings tabs have no '<x>' yet` for `Export` and `Import` (9.2), `Check for updates` (9.4) and `Reset all` (9.5). Each of those stages retires its own entry in the same commit as the control, as 8.3 did for 1.2 and 4.2.
- PM-8.3-2 · agent · every stage · Before the first guard sweep, grep `scripts/stages/*.sh` for every control name the stage adds and for every expression it rewrites, not only for file names. `verify-stage.sh` stops at the first failure, so each stale check otherwise costs a full sweep. (Process; extends PM-7.3-2.)
- Earlier actions that targeted 8.3: none.
- Still open from earlier stages: PM-7.3-3, PM-8.2-1, PM-8.2-2 (8.4); PM-8.1-1 (H2 PR); PM-8.1-2 (10.1); PM-8.1-3 (9.5); PM-8.2-4 (9.1).
- Process actions applied: PM-7.1-3, PM-7.1-6, PM-7.1-7, PM-7.2-5 (the draft PR was opened once the stage compiled), PM-7.3-1 (`caffeinate` was running and `IOConsoleLocked` was false before the UI runs), PM-7.3-2 (the `TB_UI_TESTS=0` sweep ran first), PM-8.2-3 (no screenshot this stage), PM-8.2-5 (lint gated the push).
