# Postmortem — Phase 7 Apps
Date: 2026-11-16 · Stages: 7.1 (#30, #31), 7.2 (#32), 7.3 (#33)

## Outcome vs. phase map
14 § 0.5: "Per-app attribution incl. harness drop folder."
- **Per-app attribution:** met, along every path in 06's precedence.
  - **key** (7.1): provider keys bound to apps, with Σ rows equal to the provider total.
  - **≈ split** (7.2): a key's day split among the harness apps that used it.
  - **harness** (7.2): accounts without a usage API (DeepSeek, xAI) take their spend from harness lines.
  - **inferred** (7.2): a single-app DeepSeek day takes its balance delta.
  - **Unassigned:** usage without an app is this row everywhere (7.3).
- **Harness drop folder:** met (7.2). Tailing from stored offsets, V7's offset and rows in one transaction, dedup, `ingested/` and `rejected/`, E2E-3 with a hard kill, A3 within 5 s, and the Settings → Sources group with both reporters.
- **Drilldown:** met (7.3). Overview row → filtered account page; the harness drift chip.
- **Verification:**
  - Core: `AttributionTests` (key, split, harness, inferred, drift, drilldown), `LineParserTests`, `IngestTailerTests`, `ObservationTests`.
  - App: `AppsBindingUITests`, `HarnessIngestUITests`, `HarnessRejectedUITests`, `DrilldownUITests`.
  - Coverage stayed at or above 97 %.

## Patterns across stages
1. **CI's older compiler (Swift 6.1) caught what the local toolchain allows, in every stage.**
   - 7.1: a crash on a method-reference setter.
   - 7.2: `#require` around a throwing call, and a synchronous read of an actor `let`.
   - 7.1 merged on a red CI because a pipe hid the exit code (PM-7.1-6).
   - **Fix that held:** push a draft PR as soon as new code compiles, and read `statusCheckRollup` before merging. 7.2 and 7.3 merged only on green.
2. **The Mac's locked screen cost UI runs in 7.2 and 7.3.** **Fix:** hold `caffeinate -dims` for the whole session and check `IOConsoleLocked` first (PM-7.3-1).
3. **Earlier stage scripts guard the future** ("not yet" checks; one-line greps of a list). Each stage of phase 7 had to update one: 7.1's `topApps`, 7.2's step lists, 7.3's "rows are not buttons yet". A grep-based guard sweep (PM-5.3-4, PM-7.2-4) still missed 4.2's and 5.2's exact-text checks in 7.3. From now on the sweep is a cumulative `TB_UI_TESTS=0` verify run first (PM-7.3-2).
4. **Q-047's change-based UI selection worked**, and gave clear signal per stage. Each phase-7 stage touched `AppModel` or `Startup`, so each ran every suite anyway (about 17 min).

## Plan and doc changes
- **14:** § 7.1–7.3 inventories completed (D1). E2E-3 asserts A3.
- **04:** the ingest step and the FSEvents flags; the `harness drift` daily step.
- **05:** the per-response harness rows; harness spend only for USD accounts.
- **06:** the DoD counts rows per distinct request id; where the folder sits.
- **08:** By-app rows, badges and links; the Sources group; the drilldown and the drift chip.
- **Judgment calls:** Q-047 (UI selection), Q-048 (apps), Q-049 (ingest), Q-050 (drilldown).

## Gates and risks
- **H2 (OpenAI) and H3 (DeepSeek, xAI) recordings:** open (owner). The split path and the harness substitute are tested on synthetic fixtures only.
- **Risks for phase 8:**
  - 8.1's `Drift`/`ledger.drift` is a different check from the harness drift. Q-050 keeps their names apart.
  - 8.2's chart reads `Spend.daily`, which now includes inferred days.
  - The account page is taller with each stage; its lazy Sources strip hides chips below the fold (PM-7.2-6, 8.4).

## Open carry-forward actions
- **Phase 7:**
  - PM-7.1-4 · agent · 11.3 · check the Dashboard pages at 920 pt against Paper; verify with `TB_UI_TESTS=1`.
  - PM-7.1-5 · agent · 11.5 · one full UI run (`TB_UI_TESTS=1`).
  - PM-7.1-6, PM-7.1-7, PM-7.2-4, PM-7.2-5, PM-7.3-1, PM-7.3-2 · agent · every stage · process.
  - PM-7.2-1 · agent · 9.1 · the split must read rolled-up weights once raw harness events are purged.
  - PM-7.2-3 · agent · 10.2 · OpenRouter harness buckets priced from the book, not `cost_cents`.
  - PM-7.2-6 · agent · 8.4 · a non-lazy Sources strip for VoiceOver.
- **Phase 6 and earlier (unchanged):**
  - PM-6.1-1 and PM-6.2-1 · the H3 PR.
  - PM-6.1-4 · 9.1 · thin `balance_snapshot`.
  - PM-5.2-3 · accepted · the reprice race.
  - PM-5.4-2 · 9.5 · the 24 h notification dedupe is lost at relaunch.
  - PM-5.5-1 · 11.3 · the metric's look.
