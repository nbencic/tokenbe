# Postmortem — Stage 8.1 By-model table & drift
Date: 2026-11-16 · Branch: s8.1-by-model-drift · PR: #35 · Planned size: M · Commits: 5

## Outcome
The account page now has 08's **By model** table: Model | Requests | Input | Cache write | Cache read | Output | Reasoning | Est. cost | Provider cost | Drift, over the Dashboard range.
- **Drift (05 § Drift):** OpenAI's `line_item` cost rows map to usage models by exact model name (Q-051). Drift compares the estimate and the provider's cost over the closed days that have a mapped row. Beyond `tb.alerts.driftThresholdPct` the cell is flagged in `HealthWatch` with an icon, and its VoiceOver label says so in words. Without a cost row it reads `—`.
- **Unpriced models (A6):** a model missing from the price book reads `unpriced` in Est. cost, never `$0`, and has no drift. Priced and unpriced buckets are summed apart in SQL.
- **`ledger.drift`:** a daily-activity step `model drift`, after `harness drift`, logs yesterday's flagged models at `warn`, once per account, model and day.
- **E2E-8:** `ByModelUITests` runs the real pricing path on an `unpriced` fixture case, then checks the flagged row, the `Unpriced in range` cell and a flagged drift cell.

D1–D12 are met. Gates H2 and H3 are still open (owner) and do not block. The line-item format is synthetic until H2 (PM-8.1-1).

## What went as planned
- **The advisor's review came before any code**, and changed four things:
  - Unpriced buckets are summed apart from priced ones. Copying `usageDays`' `COALESCE(est, 0)` would have shown `≈ $0` and a flagged −100 % drift for a model with a cost row.
  - Est and provider cost cover the same days.
  - The line-item mapping is a bounded longest match, not "text before the comma", which only our own synthetic fixture shows.
  - E2E-8 moves its rows to today, because the fixtures carry fixed November dates that the 7 d range has already passed.
- **Core first.** Every figure is computed and tested in Core (`DriftTests`: 9 cases, `FormattersTests.signedPercent`, `ObservationTests.modelTables`) before the view existed. All 529 Core tests passed on the first run.
- **E2E-8 passed on its first run (48 s).**
- **A screenshot before the full verify.** A temporary `XCTAttachment`, exported with `xcresulttool`, showed the table at the Dashboard's width. It caught the layout issue in What went wrong 1 before any full run.
- **A draft PR went up as soon as the stage compiled** (PM-7.2-5).

## What went wrong
1. **The first layout truncated model names and wrapped the flagged drift cell.**
   - **Symptom:** the screenshot at about 965 pt showed `made-u…odel-1` and `gpt-4o…08-06`, and `+100,0` / `%` on two lines.
   - **Cause:** ten columns whose titles (`Provider cost`, `Cache write`) are wider than their values. The Grid compressed the one flexible column, the model name.
   - **Fix:** two-word titles take two lines (same words; VoiceOver reads one label), and every value cell is `fixedSize`. The second screenshot showed full names and a one-line drift cell.
   - **Cost:** one extra 45 s UI run.

2. **The By-model table pushed the lazy Sources strip's chips out of the accessibility tree.**
   - **Symptom:** full verify 1 failed two suites that read the strip. `StaleOfflineUITests` found no `dashboard.account.source.usage`, and `DailyRunNowUITests` timed out on `dashboard.account.source.cost` ("the account page opens").
   - **Cause:** the strip was a `LazyVGrid`, which creates only the cells near the visible area. 08 orders the By-model table (item 5) above the Sources strip (item 6), so the table moved the strip below the fold, and SwiftUI never built the chips. PM-7.2-6 had named this risk and scheduled the fix for 8.4.
   - **Fix:** PM-7.2-6 pulled forward. `AdaptiveColumns`, a small non-lazy `Layout`, reproduces the grid's adaptive columns (200 pt minimum, 28 pt spacing), so every chip exists for VoiceOver and the tests wherever the strip sits. 8.1's script checks that the strip is not lazy. The four suites that read the strip passed on the rerun.
   - **Cost:** one full verify (about 20 min) and one 7 min rerun of four suites.
   - **Lesson:** a stage that adds a section above an existing one should check that section's UI suites first. Q-047 selected every suite here, so the full verify caught it, but only after a 20 min run.

## Verify and CI failures
- **Core and lint:** 529 Core tests in 79 suites passed on the first run. Lint found two violations (an `o1` identifier; `ObservationTests` over 250 lines), fixed by renaming the identifier and moving the new test into an extension.
- **ByModelUITests alone:** passed on runs 1–3 (48 s, 42 s, 43 s). Runs 2 and 3 carried the temporary screenshot (What went wrong 1).
- **Guard sweep** (`TB_UI_TESTS=0 verify 8.1`, PM-7.3-2): `STAGE 8.1 OK` on the first run (1 306 checks). No earlier stage script needed a change.
- **Full verify 1:** FAIL 0.4 "UI tests". 21 of 23 UI tests passed in 18 min; `StaleOfflineUITests` and `DailyRunNowUITests` failed (What went wrong 2). Disk: 101 GiB free, screen unlocked, runner not killed.
- **Rerun of the four strip suites** (StaleOffline, DailyRunNow, DirectBalance, HarnessIngest) after `AdaptiveColumns`: all passed.
- **Full verify 2:** all 23 UI tests and 529 Core tests passed with 0 failures (UI 19 min). It then failed only 8.1's own new check, "the Sources strip is not lazy": its `! grep -qF 'LazyVGrid'` matched the new type's doc comment. **Fix:** the check greps for `LazyVGrid(`.
- **Final verify** (`TB_UI_TESTS=0`, after that script-only fix): `STAGE 8.1 OK` (1 308 checks ok; 33 UI checks print `skip`). No app or test code changed after full verify 2, so its UI results stand. A 30 min UI rerun would have tested the same build.
- **CI:** green on every pushed head (63151b8, c8e7bb7, and the head that carries this postmortem).

## Deviations from the docs
- **04 § Daily activity:** a `model drift` step after `harness drift` (yesterday, `ledger.drift`).
- **05 § Drift:** an unpriced model has no drift; a provider cost of 0 is not divided by; the mapping and the columns' days follow Q-051.
- **08 § Account detail 5:** the drift format, the flag's icon and label, the `unpriced` cell, when the table shows, and the row order.
- **11 E2E-8:** names `ByModelUITests` and its fixture case.
- **14 § 8.1:** the full inventory and tests (D1), including `SourcesStrip.swift` (PM-7.2-6).

## Judgment calls
- Q-051: the line-item mapping; what each column covers; unpriced and zero-cost rows; the flag, format and order; when the table shows; the two-line titles; `ledger.drift` as a daily step with a once-per-day memory; E2E-8's data.

## Carry-forward actions
- PM-8.1-1 · agent · the H2 PR (PM-3.6-2) · Re-check `Drift.lineItemModel` against the recorded `line_item` strings. If a recorded line item names its model differently (a display name, a different case or a dated id), change the rule and `DriftTests.lineItemMapping`, and update Q-051.
- PM-8.1-2 · agent · 10.1 · The Anthropic adapter writes `description` cost rows. Decide how a row carries its model (`group_key` or a mapped field) so `Drift.mappedCosts` reads `description` rows too. Add a `DriftTests` case.
- PM-8.1-3 · agent · 9.5 · `price.unpriced` and `ledger.drift` dedupe per process (`DailyOnce` in memory), so a relaunch on the same day logs again (like PM-5.4-2). Decide in 9.5 whether that is acceptable for A6's "logged once per day", and log a Q.
- PM-8.1-4 · agent · 8.2 · `ByModelUITests` asserts `above the 10 % threshold` but does not pin `tb.alerts.driftThresholdPct`, which lives in the shared settings domain. Add `app.launchArguments += ["-tb.alerts.driftThresholdPct", "10"]` as the first commit of 8.2.
- Earlier actions closed here: PM-7.2-6 (a non-lazy Sources strip; target was 8.4, pulled forward because this stage pushed the strip below the fold): closed (`AdaptiveColumns`; status edited in stage-7.3.md and phase-7.md).
- Earlier actions that targeted 8.1: none.
- Process actions applied: PM-7.1-3, PM-7.1-6, PM-7.1-7, PM-7.2-4, PM-7.2-5, PM-7.3-1 (`caffeinate` held all session, `IOConsoleLocked` checked before each UI run), PM-7.3-2 (the cumulative `TB_UI_TESTS=0` sweep ran first).
