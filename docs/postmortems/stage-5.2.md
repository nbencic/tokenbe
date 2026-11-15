# Postmortem — Stage 5.2 Cost estimation & unpriced surfacing
Date: 2026-11-15 · Branch: s5.2-cost-estimation · PR: #24 · Planned size: M · Commits: 4

## Outcome
Every usage row now gets `est_cost_cents` and `unpriced` before it is written. The `Poller` prices each page through `PriceBook.price`. A poller without a price book writes the rows as unpriced, so 14's Verify query (`est_cost_cents IS NULL AND unpriced = 0`) returns 0, and `RepriceTests` asserts it after a fixture poll.
- **Formula:** 05's formula runs in `Int128` over one common denominator, saturates instead of trapping, and rounds half-up once.
- **Reprice:** a new feed snapshot or any override change reprices the last 90 days, one transaction per account (`price.repriced`).
- **Throttled logs:** `price.unpriced` and `price.fallback_multiplier` log once per model per UTC day.
- **UI:** the account page has a numbers strip with `Spend today`, `Spend in range` and `Unpriced in range` (only with unpriced usage, in `HealthWatch`). The Overview shows `Total spend <range>` for USD accounts plus `+ N non-USD`. The Price book line shows `N unpriced`.

D1–D13 are met, with one deferral. D10's launch checks ran: 0.4 and 2.1, clean launch and relaunch with zero `error`/`fault`. The check with a polled account is a UI check (4.1) and is deferred to 5.5. UI tests did not run in this stage: the owner asked on 2026-11-15 for phase 5's UI tests to run once at its end (Q-041). The UI-test target compiles (`run.sh build-uitest`). Gate H2 is still open (PM-3.6-1) and does not block this stage. Paper Desktop was not running, so the strip follows 08's copy (Q-040).

## What went as planned
- Pure Core:
  - `CostEstimator` (05's formula);
  - `Pricer`, a value copy of the book, so `repriceUsage` can price inside the database transaction without awaiting the actor;
  - `Spend` (05's spend definitions).
- `pricing.csv` has 16 hand-computed cases. They cover every fallback, the 1h → 5m write chain, half-up at exactly 0.5 cent, date-stripped and prefixed lookups, and three V5/unpriced cases. The OpenAI fixture rows now carry their hand-computed cents (1, 0, 0, 0).
- The summary builder takes a `SpendContext` (range, now, pricer). The observation adds three per-day aggregates over the last 91 days, so the UI never reads raw buckets.
- The advisor's pre-checks held:
  - pricing happens outside the write closure;
  - rounding happens once, over a common denominator;
  - a fallback is logged only for a class with tokens;
  - repricing is computed in Core;
  - the Overview total is USD-only.

## What went wrong
1. **A test trapped the whole test process (signal 5).** The overflow test multiplied `Int64.max / 2` by itself in `Int128`, which also overflows. **Root cause:** the formula had no overflow guard. A garbled feed rate (up to 9e18 picodollars passes the decoder) could have crashed the app the same way. **Fix:** `CostEstimator.product` and `sum` saturate, and the result clamps to `Int64` (R5: degrade, never crash). Cost: one test run.
2. **`PriceFeedTests` failed: `status == Status()` after an empty load.** **Root cause:** the new `Pricer` revision was bumped on every assignment, including assigning an empty override map. **Fix:** the revision bumps only when the table or overrides actually change. Cost: one test run.
3. **The `PriceEntry?` false positive (PM-5.1-2) appeared twice:** in swiftlint's `tokenbe_no_silent_catch` and in stage 0.2's grep check. **Fix:** both now need a non-identifier character before `try?`. The swiftlint regex is `\btry\?`; the stage-0.2 grep is `[^[:alnum:]_]try[?]|^try[?]`, because BSD `grep -E` does not match `(^|…)` alternation. `5.2.sh` adds a lint self-test (`PriceEntry?` passes, `try?` fails). This closes PM-5.1-2 early. Cost: one verify run.

## Verify and CI failures
- Verify run 1 (`TB_UI_TESTS=0`): failed at `0.2 no silent catch / try?` on `entry: PriceEntry?` in `CostEstimator.swift` (item 3).
- Verify run 2: failed at `5.2 no _above_200k rate is applied`. The check grepped the doc comment that says the variants are not applied. **Fix:** the check skips `///` lines.
- Verify run 3: failed at `5.2 no Double in the cost formula (R7)` on the range-day arithmetic (`-Double($0) * 86_400`, time, not money). **Fix:** `TimeInterval(-86_400 * $0)`. From then on, the stage's own checks ran alone first (a local copy of `verify-stage.sh` started at 5.2), so each fix cost seconds, not a 10-minute regression run.
- Verify run 4 (`TB_UI_TESTS=0`): `STAGE 5.2 OK`, 965 `ok`, 22 `skip` (UI, Q-041).

## Deviations from the docs
- **14 § Stage 5.2:**
  - step 2 names `writeUsagePage` (the code's function) and the override triggers;
  - the inventory lists every touched file;
  - Tests adds `SpendTests` (Q-040).
- **07:** `price.fallback_multiplier` is logged only for a class with tokens. It also carries `tier_priced_as_standard` for priority/batch buckets (Q-040).
- **11:** `CostFormulaTests` and `SpendTests` are added to the stage-introduced test list.
- **Paper:** not consulted (Paper Desktop not running). The numbers strip and the Overview subline follow 08's copy; 11.3 reconciles.

## Judgment calls
- Q-040: where rows are priced, the integer arithmetic, fallback and tier logging, the reprice scope and triggers, the meaning of `N unpriced`, spend as truth-then-estimate per UTC day, range days, `≈` without `±` on spend, the median rule and its `—`, and `No data yet` before the first poll.
- Q-041: phase 5 runs its UI tests once, at its end (the owner's instruction). Each stage runs `build-uitest`.

## Carry-forward actions
- PM-5.2-1 · agent · 5.3 · **closed (Stage 5.3)** · Burn and `spend_since_anchor` should reuse `Spend.spend`'s per-day truth-then-estimate rule (Q-040), so the strip and the runway never disagree.
- PM-5.2-3 · agent · 5.3 · Reprice race (non-blocking): a poll that priced its rows before an override change can write them after `repriceAll` finished. The next reprice, or the next poll of that hour, corrects them. Noted in Q-040; no fix planned.
- PM-5.2-2 · agent · 5.5 · **closed (Stage 5.5)** · Run the full UI suite (Q-041). It covers every phase-5 UI test, including those that 5.2–5.4 compiled but did not run.
- Earlier actions that targeted this stage:
  - PM-5.1-1: closed (`N unpriced` in the snapshot line; reprice on a snapshot or override change).
  - PM-3.4-3: closed (`price.repriced`, `RepriceTests`).
  - PM-5.1-2 (targeted 11.2): closed early (the regex word boundary and the lint self-test).
  - PM-5.1-5 followed: there was no `0.4` failure, since UI was off.
  - PM-4.3-2 followed: the new suites pass a `logPipeline`.
  - PM-4.1-2 does not apply, since there is no timing suite.
  - PM-5.1-4 does not apply, since nothing needed a download.
