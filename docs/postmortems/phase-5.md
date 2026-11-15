# Postmortem — Phase 5 Money
Date: 2026-11-15 · Stages: 5.1 (#22), 5.2 (#24), 5.3 (#25), 5.4 (#26), 5.5 (#27); process PR #23 (UI disk preflight, Q-039)

## Outcome vs. phase map
14 § 0.5: "The product's core promise: remaining, runway, bands, alerts."
- **Remaining:** met (5.3). Direct accounts show their latest balance. Anchored accounts show anchor + top-ups − spend since the anchor as `≈ $N ± M`, with 05's estimate band. Spend comes from the priced usage of 5.1 (price book) and 5.2 (cost formula, repricing), and from provider cost for closed days.
- **Runway:** met (5.3). `burn_7d` and `burn_today` give two paces, Day-1 reads `Collecting…`, and auto-reload reads `reloads at $X`.
- **Bands:** met (5.3, 5.5). They follow 05's order on Alerts' thresholds, are stored in `band_state` with their inputs (V6), and are logged `ui.band_change` with a trigger. They appear on the cards, the banner, the Overview board, the account pill, and the notched glyph from launch (step 8).
- **Alerts:** met (5.4). macOS notifications for low/critical transitions, a missing anchor and stale data, with quiet hours, snooze, `Open`, and the Alerts tab.
- **Verification:**
  - E2E-2: `AnchorRunwayUITests`.
  - E2E-4: a Core test with `RecordingNotifier`.
  - E2E-8's pricing half: `RepriceTests`. Its by-model row is 8.1's.
  - E2E-9: `check-traceability.sh`, plus the same join inside `AnchorRunwayUITests` on its own log.

  All ran in the phase-closing UI run (Q-041).

## Patterns across stages
1. **Earlier stages' guards break when a later stage legitimately arrives.** In 5.1, `2.1.sh`/`4.1.sh` pinned the full startup list. In 5.3, `1.3.sh`/`4.2.sh` "not yet" guards (D6) and `3.5.sh`/`4.2.sh` literal greps on refactored lines failed 3 of 4 full verifies. **Root cause:** checks that own a full list or a literal line instead of the property they protect. **Fix adopted:**
   - each failing check now asserts its property;
   - before a stage's first full verify, sweep earlier scripts for guards on the touched files;
   - run the stage range from the oldest affected stage with a local copy of `verify-stage.sh` (PM-5.1-5, PM-5.3-4).
2. **XCUITest sees a different tree than the code suggests.** Three cases:
   - a `Table` in a grouped `Form` killed the runner (5.1, PM-5.1-3);
   - the menu-bar metric is not exposed (5.5);
   - the pill's word sits in the value, not the label (5.5).

   **Lesson:** read an element's label, title and value once in a failure message before writing the assertion (PM-4.2-4 holds).
3. **Environment, not code, fails UI runs.** Low disk killed the runner (5.1, Q-039), and the owner's locale and shared-suite settings changed formatted text (5.5). **Fix:** the disk preflight in `run.sh`; assertions that do not depend on the locale or on settings another suite owns (PM-4.2-5).
4. **Parallel work paid off:**
   - stacked branches (5.3 on 5.2, 5.4 on 5.3, 5.5 on 5.4), rebased onto `main` after each squash merge;
   - full verifies in a separate git worktree.

   Together they kept CI and verify time from blocking the next stage. Each rebased tree was checked identical to the verified one before its PR.

## Plan and doc changes
- **14:**
  - § 0.3: the `Notifier` seam lives in Core (Q-043);
  - inventories for 5.1–5.5 name every touched file;
  - 5.2 step 2 names `writeUsagePage`;
  - 5.3 Verify states the E2E-9 join.
- **07:**
  - `price.fallback_multiplier` adds `tier_priced_as_standard`;
  - `ui.band_change` adds `trigger`, floor and `estimate_band`;
  - `ui.notification_sent` adds the `stale`/`test` kinds;
  - the 5.1 ctx additions (Q-038).
- **11:** the stage-introduced tests `CostFormulaTests`, `SpendTests`, `LedgerTests`, `BandTransitionTests` and `AccountPresentationTests`.
- **Process:** phase 5's UI tests ran once, at its end (Q-041, the owner's instruction). `run.sh build-uitest` compiles them in every stage.
- **Judgment calls:** Q-038 (5.1), Q-040 (5.2), Q-041 (process), Q-042 (5.3), Q-043 (5.4), Q-044 (5.5).
- **Proposed for later phases:**
  - Paper was not available for 5.2–5.5. Every new view follows 08's text, and its look is 11.3's to reconcile (PM-5.5-1).
  - 8.1's drift and by-model table can reuse `Spend.daily` and the price book's `Pricer`.

## Gates and risks
- **H2 (OpenAI recording):** still open (PM-3.6-1, owner). The money math runs on synthetic usage and cost shapes; a recorded fixture may move field names (02 `[expected]`). Phase 6's direct providers bring H3.
- **Risks for phase 6:**
  - direct balances feed `Remaining` through `balance_snapshot`, which only tests have written so far (`BalanceSnapshotRecord` in `BandTransitionTests`);
  - CN¥ accounts are counted as `+ N non-USD` in every total, never converted;
  - the full UI suite now takes about 45 minutes (15 tests).

## Open carry-forward actions
- **Phase 5:**
  - PM-5.2-3 · agent · accepted · the reprice race (Q-040).
  - PM-5.4-2 · agent · 9.5 · the in-memory 24 h notification dedupe is lost at relaunch.
  - PM-5.5-1 · agent · 11.3 · the metric's look against Paper `7P-0`.
  - Process: PM-5.1-3, PM-5.1-4, PM-5.1-5, PM-5.1-6 (owner, disk), PM-5.3-4, PM-5.5-2 (coverage margin).
- **Earlier phases:**
  - PM-4.1-1 · agent · 11.3 · the popover footer as Paper's vertical list.
  - PM-4.3-3 · agent · 9.1 / 9.4 · the daily steps at their 04 positions.
  - PM-3.6-1 · Nikola · H2 · re-record OpenAI with an active org.
  - PM-3.6-2 · agent · the PR that consumes H2.
  - Process: PM-4.1-2, PM-4.1-4, PM-4.2-4, PM-4.2-5, PM-4.3-1, PM-4.3-2.
