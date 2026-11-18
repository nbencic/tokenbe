# Postmortem — Stage 10.0.5 Novita
Date: 2026-11-18 · Branch: s10.0.5-novita · PR: #49 · Planned size: S · Commits: 3

## Outcome
A Novita account can be added with its API key (Q-062), and it shows its balance directly.
- **Polling:** the probe and the balance poll read `GET https://api.novita.ai/openapi/v1/billing/balance/detail`.
- **Snapshot:** available balance (credit limit included) is the amount, and the cash balance is topped up. Both arrive as strings in 1/10000 USD and are divided by 100, rounded half away from zero, once (05 § Currency).
- **Harness:** lines use the OpenAI chat-completions normalizer, the `novita/` price prefix, and cache savings from harness buckets.
- **Onboarding:** the tile grid now scrolls, so seven tiles fit the 520×440 window and `Cancel` and `Continue` stay in place. Novita's tile has the letter `N` and the caption `Balance only · apps via harness`.

Novita stays out of `Verified` until H6 records it. D1–D13 are met; the soak runs, so the verify ran with `TB_UI_TESTS=0 TB_SOAK=1`.

## What went as planned
- **The pattern held.** Adding the case was the same short list as Moonshot's: the compiler named the exhaustive switches.
- **Exact-text greps were updated ahead of the sweep (PM-7.3-2):** 8.2.sh and three 10.0.4.sh checks now match a case list with a regex that tolerates later providers.
- **`NovitaTests` (9 tests) passed on its first run.** The full suite passed: 616 tests in 91 suites. Local coverage was 97.07 %.
- **PM-10.0.4-1 held:** the code and fixtures were committed before any verify.

## What went wrong
1. **Dry run: `FAIL 10.0.4 docs: … 06 provider list …`.**
   - **Cause:** that check grepped `` `xai`, `moonshot` (lowercase; Q-062) ``, and 06's list now continues with `` `novita` ``.
   - **Fix:** it now greps `` `xai`, `moonshot` `` only.
   - **Cost:** one dry run.
   - **Lesson:** in a stage that adds to a list, its own checks should not pin the end of that list (PM-10.0.5-1).

## Verify and CI failures
- **Dry run of 3.3, 7.2, 8.2, 10.0.4 and 10.0.5:** one failure, above.
- **Cumulative sweep `TB_UI_TESTS=0 TB_SOAK=1 scripts/verify-stage.sh 10.0.5`:** result below.

## Deviations from the docs
- **The tile grid scrolls.** The plan didn't mention it, but 08's fixed 520×440 window could not hold a third row of tiles, so 08 now says so.
- **Novita's per-key bill list is not used in V1.** Novita is direct, as planned, and 02 says so.

## Judgment calls
- None new; the provider choice is Q-062.

## Carry-forward actions
- PM-10.0.5-1 · agent · 10.0.6+ · A stage that appends to a list (providers, hosts, tiles) checks the item it adds, not the list's end.
- PM-10.0.5-2 · agent · 11.5 (after the soak) · Run `OnboardingUITests`, `DirectBalanceUITests` and `SidebarAccountsUITests` with UI on: seven tiles in a scrolling grid. Re-check 08's step-1 screenshot in 11.3 (Paper).
- PM-10.0.5-3 · Nikola · H6 · Record Novita (10.0.6 adds the recorder). Then 02's `[expected]` marks are checked, and Novita can join `Verified`.
- Earlier actions that target this stage: PM-10.0.2-4 (coverage) met at 97.07 %. PM-10.0.4-1 (commit fixtures first) followed.
