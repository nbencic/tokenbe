# Postmortem — Stage 10.0.4 Moonshot (Kimi)
Date: 2026-11-18 · Branch: s10.0.4-moonshot · PR: #48 · Planned size: S · Commits: 2

## Outcome
A Moonshot (Kimi) account can be added with its API key (Q-062), and it shows its balance directly.
- **Region:** the probe asks `api.moonshot.ai` (USD) first. A 401 there tries `api.moonshot.cn` (CNY), logged as the debug record `poll.region_fallback`, never as a failure. The region that answers becomes the account's currency.
- **Polling:** the balance poll (`tb.poll.balanceIntervalS`) derives its host from that currency, through a new `PollContext.currency` with no new column. It writes available balance as the amount, vouchers as granted and cash as topped up (negative while the account owes money).
- **Harness:** Moonshot lines use the OpenAI chat-completions normalizer, the `moonshot/` price prefix, and cache savings from harness buckets.
- **Onboarding:** a sixth tile, letter `K`, captioned `Balance only · apps via harness`.

Moonshot stays out of `Verified` until H6 records it, so Release hides it; the Debug soak copy offers it. D1–D13 are met; the soak runs, so the verify ran with `TB_UI_TESTS=0 TB_SOAK=1`.

## What went as planned
- **Only two Core switches needed the new case** (harness normalizer, price prefix), plus cache savings and the app's glyph, caption and lag help. The compiler listed each one.
- **The research notes held the documented example and field meanings,** so the synthetic fixtures copy Moonshot's own example (`49.58894`, …) and its CNY/USD rule.
- **`MoonshotTests` (12 tests)** cover both regions, the refused-on-both case, other failures, not-ok and unreadable bodies, the exact snapshots (USD, CNY, owing), unknown keys, the missing polls, fixture mode and the host rule. The full suite passed: 607 tests.
- **PM-10.0.2-4 held:** coverage is 97.06 % locally, and every new line is covered.

## What went wrong
1. **Two test mistakes, caught on the first run.**
   - **Debug record not seen:** the test pipeline's minimum level is info, so the debug `poll.region_fallback` record was dropped. The test now sets `minimumLevel = .debug`, as `IngestTailerTests` does.
   - **Wrong error field:** a provider rule's name is not in `LogError.desc`, so the test now checks `err.type`.
2. **Lint: `humanMessage` reached cyclomatic complexity 11.** The per-provider key-rejected copy moved into `PollError.keyRefused(_:status:)`, an exhaustive switch over providers, so no grep or test changed.
3. **Dry run: `FAIL 3.3 without a key it refuses and writes nothing`.** That check needs a clean `Tests/Fixtures/providers` in git, and the new Moonshot fixtures were still uncommitted. The fix is to commit before the sweep (PM-10.0.4-1).

## Verify and CI failures
- **Dry run of 3.3, 6.1, 6.2, 7.2, 8.2 and 10.0.4:** only the 3.3 failure above. 8.2.sh's exact-text grep was updated beforehand for the new cache-savings line (PM-7.3-2).
- **Cumulative sweep `TB_UI_TESTS=0 TB_SOAK=1 scripts/verify-stage.sh 10.0.4`: `STAGE 10.0.4 OK` on its first run.** 1566 checks ok and 129 skipped (UI and soak); the coverage gate passed; `✔ Test run with 607 tests in 90 suites passed after 4.328 seconds.`.

## Deviations from the docs
- **14 § 10.0.4 step 2** planned the host from the currency with "no new column". `PollContext` gained a `currency` field, defaulting to `USD` and filled by the poller from `account.currency`; it is not a database column.
- **The plan named no new event.** `poll.region_fallback` (debug) was added to 07 and `Evt`, because no existing event fits an expected wrong-region 401 at debug.
- **The recorder entry for Moonshot** stays in 10.0.6, as planned.
- **3.3.sh's ProviderID check** now reads "later providers append", since the case list grew.

## Judgment calls
- Q-062 · the owner's choice, nothing new. The new event follows 12 § R5 ("new event → add to 07").

## Carry-forward actions
- PM-10.0.4-1 · agent · every stage · Commit new fixtures before any verify run: 3.3's "writes nothing" check needs a clean `Tests/Fixtures/providers` in git.
- PM-10.0.4-2 · agent · 11.5 (after the soak) · Run `OnboardingUITests` and `SidebarAccountsUITests` with UI on. Onboarding now has six tiles, then seven in 10.0.5.
- PM-10.0.4-3 · Nikola · H6 · Record Moonshot (10.0.6 adds the recorder). Then 02's `[expected]` marks are checked, and Moonshot can join `Verified`.
- Earlier actions that target this stage: PM-10.0.2-4 (coverage) is met.
