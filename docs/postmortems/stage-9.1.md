# Postmortem — Stage 9.1 Retention roll-ups
Date: 2026-11-18 · Branch: s9.1-retention-rollups · PR: #39 · Planned size: M · Commits: 5

## Outcome
03 § Retention tiers runs in the daily activity as the `roll-ups` step, between the model drift and the price refresh (04):
- **Hourly → daily.** `1h` usage older than `tb.retention.hourlyDays` is summed per day, model, key and tier, then deleted. Provider rows become `source = 'rollup'`. Harness rows stay `harness`. Days that hold an `anchor` stay hourly.
- **Daily → monthly.** Whole months older than 400 days get `1mo` rows. They are recomputed from the daily rows, which stay, and a row is written only when a sum changes. Every summary read of `usage_bucket` skips `1mo`.
- **Harness purge.** `harness_event` rows older than `tb.retention.rawHarnessDays` are deleted, only after the roll-ups succeeded.
- **Balance thinning.** `balance_snapshot` keeps every row for 7 days, then the first and last of each UTC day and currency.
- **Logging and transactions.** Each tier logs `db.rollup {tier, rows_in, rows_out, before}` and is one transaction per account (R7). `incremental_vacuum` remains the activity's last step.
- **Settings.** Advanced → `Hourly detail kept for N days` and `Raw harness events kept for N days` steppers, bounded by 09's ranges.

Totals stay exact in every reader: Spend, burn, `spend_since_anchor`, By app, By model, the chart and the cache tile. Anthropic's cache savings count the roll-up rows (PM-8.2-4). A day whose raw harness lines were purged is still a day with reports, and a single-app account keeps it (PM-7.2-1). D1–D13 are met. No H-gate belongs to this stage; H2 and H3 stay open (owner).

## What went as planned
- **The design was settled before any code.** The orientation read every `usage_bucket` reader, `Spend.counts`, `CacheSavings`, the harness attribution and `BalanceDay`. It found three places where 03's literal text would break a total:
  - harness hours merged into a `rollup` row;
  - an anchor day rolled to midnight;
  - only the first balance snapshot kept.

  The advisor review then added four items:
  - the monthly tier must recompute, not add;
  - a purged day must not turn `inferred`;
  - the Advanced controls;
  - the PM-4.3-3 order check.

  Each became code, a test or a Q-055 line before the first build.
- **Core tests passed on their first run.** `RetentionTests` (11 cases), the new `CacheSavingsTests` and `AttributionTests` cases, and the existing Observation and Drift suites: 66 tests in 6 suites.
- **The stepper UI test passed on its first run** (AdvancedMaintenanceUITests, with SettingsGeneralUITests alongside, 3 tests in 2 min 53 s).
- **The guard sweep passed on its first run** (PM-8.3-2 held): 1,411 checks and 564 Core tests in 84 suites passed. Only D13 failed, because this file did not exist yet. Before it ran, the stage scripts were grepped for every expression this stage rewrote. That found 8.2.sh's `success("provider")` check, which was updated in the same commit.
- **CI was green on the first pushed code** (27eaa42), which also checks Swift 6.1 / Xcode 16.4.

## What went wrong
1. **The single-app fallback first took the first app of several.**
   - **Symptom:** `harnessRows` reused the existing `single`, which is `harnessApps(…).first`. It is set whenever the account has any harness app, not only when it has exactly one. With two apps, a purged day would have gone wholly to the alphabetically first app.
   - **Root cause:** the variable's name promised more than its value. In the old code, the inferred branch was correct only because `inferredDays` itself requires exactly one app.
   - **Fix:** `onlyApp` requires `count == 1`. `AttributionTests.purgedLines` asserts the two-app case is Unassigned.
   - **Cost:** found by reading the code before the test run; no extra commit.
2. **Eight lint violations on the first lint run:**
   - Observation's `fetch` reached 51 lines after the SQL was wrapped;
   - three `x = x + y` in `Rollup.run`;
   - two `try?` in the new UI test (`tokenbe_no_silent_catch`);
   - a nested error type and a 253-line suite body in RetentionTests.

   **Fix:** the SQL went back on single lines, `RollupCount` got `+=`, the UI test reads the log through `do/catch` with `XCTFail`, and the failing stub moved to file scope. One lint rerun, before the first commit.
3. **An expected count in the test was wrong:** 6 daily rows from 9 hours, where the hours form 5 groups. Corrected while reviewing the test before it ran.

## Verify and CI failures
- **Core and lint:** 66 tests in the six touched suites passed on the first run. Lint was clean after the fixes in What went wrong 2.
- **Stage-script dry run** (9.1 static checks, plus the edited checks in 4.3 and 8.2): every check passed.
- **UI, targeted:** AdvancedMaintenanceUITests (incl. `testRetentionSteppers`) and SettingsGeneralUITests passed, 3 tests in 2 min 53 s.
- **Guard sweep** (`TB_UI_TESTS=0 verify 9.1`): 1,411 checks passed. Core: 564 tests in 84 suites. The run failed only D13 (this postmortem).
- **Full verify** (`Observation.swift` is a shared file, so Q-047 selected every suite): `STAGE 9.1 OK` on the first run, with 1 448 checks passed and 1 printing `skip` (3.6's H2 check). 25 UI tests passed with 0 failures in 19 min 46 s; the ⌥-click test did not flake. DailyRunNowUITests saw the app's own daily run log the four `db.rollup` tiers. 564 Core tests in 84 suites passed. Disk had 87 GiB free, the screen was unlocked, and no runner was killed.
- **CI:** green on 27eaa42. The head that carries this file is checked by SHA before the merge.

## Deviations from the docs
- **03 § Retention tiers** (Q-055), with 03 updated in this PR:
  - harness hours roll into `1d` rows that keep `source='harness'` (03 said `rollup` for all hourly rows);
  - an anchor's day stays hourly;
  - balance thinning keeps the first and the last snapshot of each day (03 said the first);
  - monthly rows cover whole months and are skipped by every summary read.
- **14 § Stage 9.1:** the Inventory now lists the files, and the Tests line the cases.
- **Phase 8 slips** (folded in as the first commit, 9c5446c, per the 8.4 handoff):
  - `phase-8.md` pattern 4 said no phase-8 stage changed a shared file. In fact 8.1 changed `Observation.swift` and ran all 23 UI tests. Corrected.
  - AccessibilityUITests tolerates contrast on any element without an identifier, which is wider than Q-054's "sidebar rows and window title". The code was left as it is: narrowing it blind could fail the audit on an element no run has named. Instead, Q-054 has an appended correction, the test's comment says so, and PM-8.4-2 (11.3) now includes narrowing the predicate.

## Judgment calls
- Q-055: the retention rules the docs leave open:
  - the harness roll-up source;
  - anchor days;
  - mixed pricing within one day;
  - late hours;
  - recomputing the monthly rows and skipping them in reads;
  - first and last balance snapshots;
  - purged harness lines (PM-7.2-1);
  - UTC-day cut-offs and the shape of the `db.rollup` record;
  - the two steppers.

## Carry-forward actions
- PM-9.1-1 · agent · 11.1 · LOAD-1 (5 years of data, < 250 MB, Overview < 300 ms) is the first real test of `rollupMonthly` at scale. It reads all daily rows older than 400 days on every run, and writes only the months that changed. If it shows up in the daily step's duration (`roll_ups_ms` in `sched.daily_end`), bound the read to the months not yet rolled up.
- PM-9.1-2 · agent · 9.2 · Export and import cover `usage_bucket` with all three widths. An import must keep the `1mo` rows as they are, without re-deriving them. Round-trip row counts per width are part of `ExportImportTests`.
- Earlier actions that targeted 9.1:
  - PM-8.2-4: closed (5280fee, `CacheSavingsTests.rollupRows`).
  - PM-7.2-1: closed (5280fee, `AttributionTests.purgedLines`). With several apps the split of a purged day is lost; Q-055 accepts this.
  - PM-6.1-4: closed (5280fee, `RetentionTests.balanceThinning`).
  - PM-4.3-3: closed for 9.1 (`roll-ups` is in 4.3.sh's order check); still open for 9.4 (update check).
  - Statuses edited in stage-8.2, 7.2, 6.1, 4.3 and phase-8.
- Still open from earlier stages:
  - PM-8.1-1 (the H2 PR);
  - PM-8.1-2 (10.1);
  - PM-8.1-3 (9.5);
  - PM-8.3-1 (9.2, 9.4, 9.5);
  - PM-8.4-1 (owner, 11.3);
  - PM-8.4-2 (11.3, widened here).
