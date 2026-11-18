# Postmortem — Stage 10.0.2 xAI on its Management API
Date: 2026-11-18 · Branch: s10.0.2-xai-mgmt-api · PR: #45 · Planned size: M · Commits: 3

## Outcome
An xAI account now uses a management key (Q-062, the owner's choice).
- **Probe:** `GET /auth/management-keys/validation` names the key's team (`scopeId` for `SCOPE_TEAM`, else the deprecated `teamId`). One `POST /v1/billing/teams/{team_id}/usage` over the last day then proves billing read access.
- **Mode:** the account is anchored, in USD, with a cost job. That job runs every `tb.poll.keysIntervalS` (xAI only, 04) and in the daily activity. It writes, per UTC day, one `description` row per model and one `total` row, in cents.
- **Guard:** TokenBe names exactly the validation and usage paths, on `management-api.x.ai` only. 10.0.2.sh fails on any other management billing path: top-up, limits, billing info, payment method, invoices, prepaid.
- **Why it was needed:** the soak recorded that the old `GET /v1/api-key` has no balance (02 § xai, 13 § D-xai-balance).
- **Not yet:** `prepaid/balance` waits for H6, which must show what its `total` means.

D1–D13 are met; the soak runs, so the verify ran with `TB_UI_TESTS=0 TB_SOAK=1`. The H5 soak and the H2, H3 and H6 gates stay open.

**Owner step after merge:** remove the soak's xAI account with `−` first. It holds an inference key and anchored capabilities with no jobs. Then rebuild the soak copy, and add xAI again from `+` with a management key and an anchor.

## What went as planned
- **Before any code, the plan and the owner's two decisions were recorded:** the provider list and the xAI management key, as Q-062. 01 S1, S2 and S4 were updated, and stages 10.0.2–10.0.6 and H6 added to 14.
- **The official billing page settled two points the research notes left open:** the usage body is wrapped in `analyticsRequest`, and timestamps are ISO-8601 UTC with JSON-number values.
- **`XAITests` was rewritten:** 15 tests, covering every probe branch, the exact cost rows, the request body, `limitReached` and unknown keys. It passed after one fix (below).
- **The dry run of 6.2, 10.0.1 and 10.0.2 (PM-1.3-5) caught two over-broad greps** before any verify.

## What went wrong
1. **The probe accepted a usage body that the cost job could not read.**
   - **Symptom:** `XAITests` "a usage body TokenBe cannot read" failed. The drift fixture's `"timestamp": "yesterday"` decodes as a string, and only `costRows` parses it.
   - **Fix:** the probe builds the cost rows too, so the problem shows at onboarding.
   - **Cost:** one test run.
2. **xAI's cost job would never have run.**
   - **Root cause:** found while wiring, before any test. The coordinator schedules `Job.minuteCadence` (usage, balance, keys), and cost had no interval for any provider; the plan wrongly said the cost job ran "like OpenAI's".
   - **Fix:** `Job.scheduled` = minute cadences + cost. Cost now has an interval for xAI only (`tb.poll.keysIntervalS`). `minuteCadence` is unchanged, so the Accounts tab shows no new override row.
   - **Doc:** 04 § Daily activity names it, and 14 § 10.0.2 step 2 is corrected.
3. **Lint:** `function_parameter_count` on the new POST helper (6 and 7 parameters), and `optional_data_string_conversion` in a test.
   - **Fix:** a `BearerRequest.Target`, and `String(bytes:encoding:)`.
   - **Cost:** one lint run.

## Verify and CI failures
- **Dry run of the stage checks, two greps too broad:**
  - `api.x.ai/v1` matched source URLs in `prices.bundled.json`. Now `--include='*.swift'`.
  - The forbidden-path grep matched the ledger's top-ups. Now only path-shaped literals, plus a check that only `XAIClient.swift` names the management host.
- **First cumulative sweep (`TB_UI_TESTS=0 TB_SOAK=1`): `FAIL 0.5 check-no-secrets.sh`.**
  - **Cause:** the first branch name (`s10.0.2-xai-` followed by `management`, written apart here), in this postmortem’s header, matches the xAI key pattern (`xai-` + 8 letters).
  - **Fix:** the branch was renamed on GitHub (the PR follows) and locally to `s10.0.2-xai-mgmt-api`.
  - **Lesson:** a branch slug must not start a key-shaped run (`xai-`, `sk-`) of 8 or more letters.
- **Second sweep: `STAGE 10.0.2 OK`.**
  - 1510 ok and 125 skip, the skips from UI and the soak.
  - `swift test` 589 tests in 87 suites; `swiftlint --strict` 0 violations.
- **Local coverage gate (PM-9.3-2, run before CI): `FAIL 9974/10284 = 96.99 % < 97 %`.**
  - **Causes:** two lines were never run.
    - The new POST helper's bad-URL `throw`: splitting the `guard` across lines left that `throw` on a line of its own, and nothing tested it.
    - `XAIUsageRequest.json()`'s unreachable encode `catch`.
  - **Fix:** a `BearerRequestTests` case for a relative path, and the unreachable `catch` kept on one line.
  - **Result:** 9976/10281 = 97.03 %, and a third sweep after the fix.
  - **Margin:** under 0.1 %. Each new adapter must test every failure branch (PM-10.0.2-4).

## Deviations from the docs
- **14 § Stage 10.0.2 step 2** said the cost job ran "like OpenAI's cost". OpenAI's cost is daily-only. xAI's cost now runs on the keys period through `Job.scheduled`, and 04 is updated.
- **6.2.sh's checks of the `/v1/api-key` probe are retired.** They are superseded by 10.0.2.sh (Q-062). 6.2.sh keeps its wiring, R7 and suite checks.
- **3.3.sh** names `XAI_MANAGEMENT_KEY` instead of `XAI_API_KEY`, matching the recorder.
- **`helpLag(.xai)`** says spend is read hourly. 08 has no lag copy per provider, so this is authored like the others.

## Judgment calls
- Q-062 · the owner's decisions: providers to add, xAI on a management key with a path guard, stage order.

## Carry-forward actions
- PM-10.0.2-1 · agent · 11.5 (after the soak) · Run `SidebarAccountsUITests`, `OnboardingUITests` and `DirectBalanceUITests` with UI on. SidebarAccounts onboards xAI in fixture mode, which now shows step 3's anchor field. Caption and Lag-help copy changed.
- PM-10.0.2-2 · Nikola · H6 · Record xAI with `XAI_MANAGEMENT_KEY` (`scripts/record-fixtures.sh xai`): validation, usage and prepaid balance. Then 02's `[expected]` marks are checked, and whether xAI turns direct is decided from `total`.
- PM-10.0.2-3 · Nikola · after merge · Remove the soak's xAI account with `−`, rebuild the soak copy, then add xAI from `+` with a management key and an anchor.
- PM-10.0.2-4 · agent · 10.0.3–10.0.5 · Core coverage is at 97.03 %. Every new adapter and migration branch gets a test, and the local coverage gate runs before the first sweep.
- Earlier actions that target this stage: none.
