# Postmortem — Stage 5.3 Ledger, runway, bands; Alerts tab; cards and Overview complete
Date: 2026-11-15 · Branch: s5.3-ledger-runway-bands · PR: #25 · Planned size: L · Commits: 7

## Outcome
TokenBe now computes the product's core numbers per 05:
- remaining (direct balance, or anchor + top-ups − spend since the anchor);
- the estimate band `M`;
- `burn_7d` and `burn_today`;
- two runway paces;
- the band, from Settings → Alerts' thresholds, with auto-reload's `reloads at $X` override.

**Popover**
- Cards show the pinned metric in row 2 (`≈ $100 ± 0`) and the others in row 3. Day-1 shows `Collecting… runway after 2 days of data`, and a spend-only card shows `today $X · 30 d $Y`.
- An alert banner names the worst account. ↑/↓/⏎ move between cards.

**Dashboard**
- The Overview has the shortest-runway headline, `Total remaining ≈ … across N USD accounts + M non-USD`, and the runway board.
- The account page has `Set anchor…`, `Add top-up…`, Remaining/Runway/Burn 7 d, the anchor nudges, and the ledger list. User rows can be deleted.

**Settings**
- Settings has the Alerts tab.
- Accounts has the auto-reload toggle and amounts.

**Band changes**
- A band change writes `band_state` with its inputs in one statement (V6) and logs `ui.band_change` with a `trigger`.
- `scripts/check-traceability.sh` implements E2E-9.

D1–D13 are met, with the UI part deferred. Per the owner's instruction (Q-041), `AnchorRunwayUITests` (E2E-2, the critical banner, and E2E-9 on its own log) is compiled here and runs in 5.5. D10's launch checks ran (0.4, 2.1). Gate H2 is still open (PM-3.6-1) and does not block. Paper Desktop was not running (Q-042).

## What went as planned
- The six `Ledger/*.swift` files are pure functions over `SummaryInputs`, tested table-driven: `ledger.csv` has 16 hand-computed cases covering every band, every nil combination, V1, `M ≥ remaining` and auto-reload. Plus `LedgerTests`, `BurnTests`, `BandTransitionTests` and `AccountPresentationTests`.
- The advisor's pre-checks shaped the design:
  - write only on a band change, from a Core actor seeded from the persisted rows (no observe → write loop);
  - decide E2E-9's edge cases up front;
  - enforce `source = 'user'` in SQL;
  - reuse the daily spend rule (PM-5.2-1);
  - fix existing UI-test assertions in this stage.
- Stage 5.2 merged while 5.3 started on a stacked branch, rebased onto `main` after the squash merge, so CI time was not idle time.

## What went wrong
1. **`AccountOrderTests.byRunway` broke under the new "unknown sorts last" rule.** **Root cause:** `AccountSummary`'s default band is `unknown`, so the test's accounts all became "unknown". **Fix:** the helper gives accounts a `healthy` band, and a new case covers an unknown account with a runway. Cost: none beyond the edit (found by reading the test before running).
2. **`AccountSummaryBuilderTests.identity` failed:** the builder now always sets `dollarFloorCents`. **Fix:** the test asserts the floor, then clears it. Cost: one test run.
3. **`AccountRecord` could not become `Identifiable`:** `2.1.sh` pins each record's exact declaration. **Fix:** a small `AnchorTarget` wrapper in the app. Cost: one build.
4. **E2E-9 as written in 11 fails for three real cases:**
   - a band that changed while the app was closed is logged at launch with no poll before it;
   - a poll commits its rows before it logs `poll.ok`, so the band change can be logged first;
   - settings and clock flips have no poll record at all.

   **Fix (Q-042):** `ui.band_change` carries `trigger` (`data`, `settings`, `clock`, `launch`), and only `data` changes are joined. A `poll.ok` up to 2 s after the change counts. 07 and 14 are updated.
5. **Lint:**
   - `Strings` grew past 250 lines; the 5.3 copy moved into an extension in the same file.
   - Parameter count and names (`at:` became `asOf:`).
   - A 4-tuple in the UI test became a struct.
   - A first attempt to move the strings with a marker script failed on a wrong marker, and the move was redone by line range.

   Cost: two lint runs.

## Verify and CI failures
- Stage-only run 1 (`5.3.sh` alone, Q-041 practice from 5.2): failed at `5.3 unknown sorts last`. The check's single-quoted pattern kept the `\$` escapes. **Fix:** a plain `$0` in single quotes.
- Stage-only run 2: every 5.3 check ok; only D13 (this file) failed, as expected.
- Full verify run 1 (`TB_UI_TESTS=0`): failed at `1.3 SettingsView has no 'Alerts' tab yet`, a D6 guard for tabs that had not arrived. **Fix:** Alerts left the guard list; 5.3.sh checks the tab.
- Full verify run 2: failed at `3.5 the anchor is ledger_event(kind=anchor)`. The check grepped the literal `kind: "anchor"`, which the shared insert helper replaced. **Fix:** the check follows `UserEntry` (anchor, topup).
- Full verify run 3 (in a separate git worktree, so 5.4 work could go on): failed at `4.2 Dashboard has no 'Set anchor' yet`, the same kind of guard. A run from 4.2 onward then also failed `4.2 a card opens its account page`: cards now open through the shared `openAccount`. **Fix:** both 4.2 checks, found in one stage-range run before the next full run.
- Full verify run 4: `STAGE 5.3 OK`, 1032 `ok`, 23 `skip` (22 UI, Q-041; 1 H2).
- **Lesson:** earlier stages' "not yet" guards (D6) and literal greps break when a later stage legitimately adds the control or refactors the line. Before a stage's first full verify, run `grep -n "yet\|no '" scripts/stages/*.sh` and the stage range from the oldest touched stage (PM-5.3-4).

## Deviations from the docs
- **07 `ui.band_change`:** adds `trigger`, plus floor and estimate_band in `inputs`. It is not logged for an account's first evaluation (Q-042).
- **14 § Stage 5.3:**
  - the inventory names every touched file;
  - Tests names `AccountPresentationTests`;
  - Verify states the E2E-9 join and that the UI part runs in 5.5 (Q-041).
- **11:** the stage-introduced test list adds `LedgerTests`, `BandTransitionTests` and `AccountPresentationTests`.
- **05 vs 08 on negative remaining:** `M ≥ remaining → unknown` applies only to a positive remaining, so 08's `critical` for a negative remaining within V1 is reachable (Q-042).
- **`ledger.reconcile`** has no producer in V1 code (05 defines no reconcile formula). It stays in 07 (Q-042).
- **Paper:** not consulted (not running). 11.3 reconciles.

## Judgment calls
- Q-042: the per-day spend rule in burn and since-anchor, the anchor-day remainder, the reach-back window, rounding up `M`, negative remaining vs V1, auto-reload forcing `watch`, band recording and its triggers, the E2E-9 join, cards' row rules, the banner pick and 60-character fit, the Overview totals, sheet validation, the authored nudge copy, and Alerts steppers.

## Carry-forward actions
- PM-5.3-1 · agent · 5.4 · **closed (Stage 5.4)** · `AlertPolicy` should consume `ui.band_change`'s transitions through `BandRecorder` (the one place a change is known). It should not notify on `launch` changes that only restore a persisted band, and should define whether a `launch` change into `low` notifies.
- PM-5.3-2 · agent · 5.5 · Run `AnchorRunwayUITests` (with E2E-9 on its log) and the existing suites whose card text changed: `OnboardingUITests` now accepts `≈ $200` or `No data yet` in row 2.
- PM-5.3-4 · agent · process · Before a stage's first full verify, grep earlier stage scripts for D6 "not yet" guards and literal greps on the files the stage touched, and run the stage range from the oldest affected stage (a local copy of `verify-stage.sh` started at that index). Three of 5.3's four verify failures were such checks.
- PM-5.3-3 · agent · 5.5 · Startup step 8 renders the glyph from persisted `band_state`. `BandRecorder` already seeds from it; the glyph must not wait for the first evaluation.
- Earlier actions that targeted this stage:
  - PM-5.2-1: closed (`Spend.daily` feeds burn, since-anchor and the strip).
  - PM-5.2-3 (reprice race): accepted in Q-040; no change.
  - PM-4.2-1: closed. `AnchorRunwayUITests` asserts the band pill's word (`critical`); it runs in 5.5. The stale overlay never changes the band: `Freshness` sets only `isStale`.
  - PM-5.1-3 followed: there is no `Table` in a grouped `Form`; the ledger is a `List` on the account page and the Alerts tab uses steppers.
  - PM-4.3-2 followed: the new suites pass a `logPipeline`.
