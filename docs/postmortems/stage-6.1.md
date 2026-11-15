# Postmortem — Stage 6.1 DeepSeek adapter
Date: 2026-11-15 · Branch: s6.1-deepseek-adapter · PR: #28 · Planned size: M · Commits: 6

## Outcome
A user can add a DeepSeek account with a standard API key (Debug builds; Release only once `deepseek/RECORDED` exists).
- **Balance:** `GET /user/balance` is both the probe and the 60 s `balance` job. Each currency entry becomes one `balance_snapshot`, and the account's currency is the first entry's.
- **Display:** cards and the account page show the balance directly, without `≈` or `±`, as `CN¥56.79` or `$110`. The Overview counts CN¥ accounts as `+ N non-USD`.
- **Unavailable:** an account DeepSeek reports unavailable keeps its balance on screen. Its band is forced `critical` with no runway. Its page shows the chip `Provider reports account unavailable`, and the banner reads `DeepSeek: account unavailable`.
- **Not yet:** until harness ingest (7.2) gives DeepSeek spend, its runway reads `Collecting…` and its band is `unknown`.

D1–D13 are met. UI tests compile (`build-uitest`) but did not run: the owner chose Q-041's cadence for phase 6, so the UI suite runs once, at 6.2.

**Gate H3 is open.** The owner has both keys in `.env` and runs the recorder in their own Terminal. When they say "recorded", the PR that consumes the gate diffs the recording against 02, adds `Verified += .deepseek`, and appends `## Addendum — H3 closed` here.

## What went as planned
- **Most of the direct path already existed.** Phase 5 left these in place and they needed no change:
  - `Remaining`'s `direct` case;
  - `Currency.cny` with its `CN¥` symbol;
  - `OverviewTotals` and `Spend.totalUSD` (USD only, plus `+ N non-USD`);
  - mode-gated anchor UI (`needsAnchor` is anchored-only);
  - the balance job's interval and capability gating;
  - the recorder's `deepseek` case.
- **Asked at the start (PM-5.1-4).** H3 and the phase's UI-test cadence were both asked before any code, in one question.
- **The guard sweep before the first full verify (PM-5.3-4)** found one literal check on a line this stage changed: 3.4's `ProviderRegistry(adapters: [OpenAIAdapter()])` (`3.4.sh` is in 14's 6.1 inventory). It now checks the prefix. 3.4's FixtureTransport check, 5.3's band-order awk and 2.1/3.4's `Repository` greps still hold by construction.
- **6.1's static checks were dry-run on their own (PM-1.3-5)** before the full verify; all passed.
- **Coverage:** 97.47 % (gate 97 %, PM-5.5-2).

## What went wrong
1. **SwiftPM refused the plan's file names.** **Symptom:** `filename "Client.swift" used twice`. **Root cause:** 14 named the files `Providers/DeepSeek/{DTOs,Probe,Client}.swift`, and SwiftPM needs file names unique within a module. **Fix:** the files are `DeepSeek{DTOs,Probe,Client}.swift`; 14 updated; 6.2 does the same (Q-045). **Cost:** one build.
2. **Every fixture test failed with "answered in a format TokenBe does not recognize".** **Root cause:** the test harness built `ok.synthetic.json` instead of `balance.ok.synthetic.json`. The stub transport turned the missing file into a transport error, and the probe reported that as an unreadable answer. **Fix:** the path. **Cost:** one test run.
3. **`Poller` grew past SwiftLint's 250-line type body.** **Fix:** `lookback` and `Outcome` moved into an extension in the same file. **Cost:** none beyond the lint run.
4. **Found in review, not by a test.** A forced `critical` has no runway, so the banner and notification would have read `DeepSeek: < 1 h left`, which is false. **Fix:** both say the account is unavailable (Q-045, 08), and `OverviewTotalsTests` asserts the wording.

## Verify and CI failures
- Full verify run 1 (`TB_UI_TESTS=0`): `FAIL 2.1 001_initial.sql contains 03's DDL verbatim`. **Root cause:** to note `unavailable` (advisor's D9 point), I edited the `inputs_json` comment inside 03's DDL. 2.1 checks that 03's DDL and the forward-only migration match byte for byte, comments included. **Fix:** reverted; the key is documented in 07 and Q-045, and 03's comment stays as migrated. **Lesson:** 03's DDL block is the migration; never edit it outside a new migration. Cost: one 12-minute verify.
- CI on PR #28 passed on its first run (5 min 59 s), including the Swift 6.1 Release build (PM-3.4-7), with typed `throws` in `DeepSeekProbe` and the tuple-argument parameterized tests.
- `swift test` run 1: 19 issues, all in `DeepSeekTests` (item 2). Run 2: 451 tests passed.
- `swiftlint --strict`: one `type_body_length` on `Poller` (item 3); clean after.
- Full verify run 2: run 1 had passed 0.1–1.3 and nothing they check had changed, so this run started at 2.1, using a local copy of `verify-stage.sh` (PM-5.3-4). It printed `STAGE 6.1 OK` with 854 `ok` and 14 `skip` lines. The skips are 13 UI checks (Q-041) and 3.6's H2 check.

## Deviations from the docs
- **14 § 6.1:**
  - file names prefixed `DeepSeek…`;
  - the 401 fixture is `balance.401`, not `auth.401`;
  - the inventory now names every touched file (D1).
- **08 § Account detail 1:** the unavailable chip, from 13 § D-deepseek-unavailable. **08 § Popover 2:** the banner's `DeepSeek: account unavailable`.
- **07 `ui.band_change`:** inputs add `unavailable: 1`, logged only when it forced the band.
- **11:** the `balance.401` fixture.
- **05 § Remaining "first currency entry":** read as "the account's currency, which the first entry set at onboarding". Q-045 gives the reason.

## Judgment calls
- Q-045 · DeepSeek and direct-balance rules: file names, the fixture name, strict amount strings, an empty reading, currencies, which snapshot is remaining, capabilities, key-refused copy, the forced `critical` and its wording, and the Q-041 cadence for phase 6.

## Carry-forward actions
- PM-6.1-1 · agent · the PR that consumes H3 · Diff `deepseek/*.recorded.json` against the synthetic files and 02 field by field. Then:
  - update the DTOs, tests and 02;
  - add `Verified += .deepseek`;
  - delete the synthetic files that have a recorded counterpart (`401` stays synthetic unless recorded);
  - append the H3 addendum here.
- PM-6.1-2 · agent · 6.2 · Run the full UI suite once (Q-041, the owner's choice for phase 6). If it fits in that run, add a DeepSeek onboarding pass in fixture mode: tile → key → `Direct`/`CNY` → card without `≈`. Status: closed in Stage 6.2 (`DirectBalanceUITests`).
- PM-6.1-3 · agent · 7.2 · Once harness rows give a DeepSeek account spend, check that `burn_7d`, runway and the band follow, and that D-deepseek-single-app's inferred attribution uses the balance deltas from `balance_snapshot`.
- PM-6.1-4 · agent · 9.1 · `balance_snapshot` gets a row per currency every 60 s (about 1,440 a day per currency). 03's retention keeps 7 days at full rate, then the first snapshot of each day; `thinBalanceSnapshots` lands with 9.1.
- **Earlier actions that targeted this stage:** PM-3.4-4 closed (`Repository+Balance`, `Poller`'s `insertBalanceSnapshots`; status edited in `stage-3.4.md`).
