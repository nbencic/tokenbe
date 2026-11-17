# Postmortem — Stage 8.2 Spend-by-day chart & cache savings
Date: 2026-11-17 · Branch: s8.2-chart-cache-savings · PR: #36 · Planned size: M · Commits: 6

## Outcome
The Overview now has 08's items 3 and 5, in 08's order: headline, runway board, **Spend by day**, Apps this period, **Cache savings**.
- **Spend by day (08 § Overview 3):** Swift Charts stacked bars, one stack per UTC day of the range, one segment per USD account in O-3's palette by sidebar order, with a legend. Hovering a day shows a tooltip listing its accounts and `Total`. The chart is built only while the card is on screen. Each account's segments are its `Spend.daily` figures, so they sum to its `Spend in range` (`ChartDataTests`, every range). A CN¥ account is not stacked on dollars; the caption counts it (Q-052).
- **Cache savings (08 § Overview 5, 05):** `Saved $X via cache (net of writes)`, then one line per account. Anthropic counts its provider buckets; DeepSeek and xAI their harness buckets. OpenAI and OpenRouter read `—` with the reason in the help, as does an account with no rows of its source. The figure comes from `CostEstimator`'s own unrounded total (cached tokens as plain input minus their cost), so the tile uses the estimate's exact rates and fallbacks, rounded once.
- **PM-8.1-4 closed:** `ByModelUITests` pins `tb.alerts.driftThresholdPct` to 10 (first commit).

D1–D12 are met. Gates H2 and H3 are still open (owner) and do not block.

## What went as planned
- **The advisor's review came before any code** and kept three things out of trouble:
  - `Observation.swift` stayed untouched. 8.1's `modelUsageDays` already carries token classes per model, day and source, so Q-047 selected 7 UI suites instead of all 23.
  - The savings reuse `CostEstimator`'s fallbacks instead of re-deriving them.
  - The chart is USD-only, like the Overview subline.
- **Core first.** `CacheSavingsTests` (8 tests) and `ChartDataTests` (5) were written before the views. Each failure on the first run was a test expectation, not code (What went wrong 1).
- **A screenshot before the full verify** (8.1's lesson) caught three layout bugs a passing test would not have (What went wrong 2).
- **A draft PR went up once the stage compiled and Drilldown passed** (PM-7.2-5).

## What went wrong
1. **Two Core expectations were wrong on the first run.**
   - `CacheSavingsTests.builderAndTotal` expected 520 ¢ for two 259.5 ¢ rows. Rounding once gives 519 ¢, so the expectation, not the code, was wrong. The test now says so.
   - `AccountSummaryBuilderTests.identity` asserts that a summary is empty before the first poll. The builder had set `rangeDays` and `cacheSavings` before the "has data" guard. **Fix:** both moved after the guard, like every other figure.
   - **Cost:** one Core run (5 s).
2. **The first chart had three layout bugs, and the hover test missed.** The Drilldown run's screenshot showed:
   - all 30 x labels drawn over each other: a category axis marks every value whatever `AxisMarks(values:)` is given;
   - y ticks reading `$0, $0, $1, $1`: hidden cents rounded the quarter-dollar ticks;
   - the hover on day 25 of 30, because the shared test settings domain held `30 d` from an earlier suite.

   **Fix:**
   - only the chosen days get a label;
   - a tick between whole dollars keeps its cents;
   - Drilldown pins `-tb.ui.dashboardRange 7d`.

   The next screenshot showed the tooltip drawn correctly, but Swift Charts exposes no annotation text to accessibility. So the hovered day's rule now carries `Total, Nov 17, ≈ $0.64` as its label; a chart mark's `accessibilityValue` is not exposed either. The per-account cache value moved its identifier from a combined row (empty label) to the value text.
   - **Cost:** five Drilldown runs (about 1 min each).
3. **The first temporary screenshot captured the whole screen**, including the owner's other windows, not only TokenBe's. It was exported to the session scratchpad only, never committed, and deleted at once. The next one used `app.windows.firstMatch.screenshot()`. **Lesson:** a diagnostic screenshot in a UI test is always a window screenshot (PM-8.2-3).

4. **A head with a known lint failure was pushed.** One shell line ran lint, then commit, push and `gh pr create` joined with `;`. Lint exited 2 and the rest ran anyway, so CI failed on 71ffad9.
   - **Fix:** the next commit fixed the violation.
   - **Lesson:** gate a push on lint with `&&`, or check the exit code before pushing (PM-8.2-5).
   - **Cost:** one red CI run, no time lost.

## Verify and CI failures
- **Core and lint:** 542 Core tests in 81 suites; 2 failures on the first run (What went wrong 1), then all passed. Lint found three violations: `Strings` over the type-body limit (new strings in an extension); `tokenbe_no_double_money` on the segment's `amount: Double` (the chart plots whole cents now); `chart(_:)` over 50 lines (hover area extracted).
- **DrilldownUITests alone:** failed runs 1–4 (What went wrong 2), passed on run 5.
- **Guard sweep** (`TB_UI_TESTS=0 verify 8.2`): every check passed except D13 (this postmortem, not yet written). No earlier stage script needed a change.
- **Full verify** (Q-047 selected 7 suites: LaunchSmoke, PopoverEmptyState, AnchorRunway, ByModel, DashboardShell, Drilldown, PriceBook): `STAGE 8.2 OK` on the first run: 1 344 checks passed. The selected UI suites ran 8 tests with 0 failures in 4 min 34 s. The 16 suites Q-047 did not select print `skip`. Disk had 107 GiB free and the screen was unlocked.
- **CI:** failed on 71ffad9, the first pushed head, with the SwiftLint error `chart(_:)` over 50 lines. Local lint had failed on that commit too, but the commit, push and draft PR ran in a `;`-chained command, so they went ahead anyway (What went wrong 4). cc5ff27 fixed it. CI was green on ec2b247 (run 44068340063) and on the head that carries this correction.

## Deviations from the docs
- **05 § Cache savings:** the estimate's rates and fallbacks, one rounding, unpriced models left out, `—` without rows of the account's source.
- **08 § Overview 3:** the tooltip's `Total`; USD accounts only, with the caption.
- **08 § Overview 5:** the headline sums the accounts with a figure; one line per account; the text when nothing is computed.
- **14 § 8.2:** the inventory, the tests (including DrilldownUITests) and the test-matrix entry.

## Judgment calls
- Q-052: the chart's data, currency, palette, axes, tooltip and VoiceOver; the savings formula, sources, dollars, tile layout and negative savings; the Overview order.

## Carry-forward actions
- PM-8.2-1 · agent · 8.4 · The runway board's Account column wraps `DeepSeek` to `DeepS` / `eek` at the Dashboard's default width (seen in this stage's screenshot; the column predates 8.2). Give the name column room or `fixedSize` in 8.4's layout pass.
- PM-8.2-2 · agent · 8.4 · The chart's per-day totals reach VoiceOver only while the pointer hovers (the rule's label). 8.4 (`08 § Accessibility`) should give the chart a keyboard- and VoiceOver-reachable summary per day, such as an `accessibilityChartDescriptor` or a per-day element, and test it in `AccessibilityUITests`.
- PM-8.2-3 · agent · every stage · A diagnostic screenshot in a UI test is `app.windows.firstMatch.screenshot()`, never `app.screenshot()`, which captures the owner's whole screen. Delete exported attachments after use. (Process; applied from this stage on.)
- PM-8.2-4 · agent · 9.1 · Anthropic's cache savings count `source = 'provider'` rows only (05). When 9.1 rolls hourly rows into `source = 'rollup'`, decide whether roll-up rows keep their cache classes and count toward the savings, so savings for older days in a 90 d range don't vanish. Add a `CacheSavingsTests` case.
- PM-8.2-5 · agent · every stage · Never chain `push` or `gh pr create` after `lint` / `test` with `;`; use `&&`, so a failing local check stops the push. (Process; applied from this stage on.)
- Earlier actions closed here: PM-8.1-4 (the drift threshold pinned in `ByModelUITests`).
- Earlier actions that targeted 8.2: PM-8.1-4 only.
- Still open from earlier stages: PM-8.1-1 (H2 PR), PM-8.1-2 (10.1), PM-8.1-3 (9.5), PM-7.3-3 (8.4).
- Process actions applied: PM-7.1-3, PM-7.1-6, PM-7.1-7, PM-7.2-4, PM-7.2-5, PM-7.3-1 (`caffeinate` held, `IOConsoleLocked` checked before UI runs), PM-7.3-2 (the `TB_UI_TESTS=0` sweep ran first).
