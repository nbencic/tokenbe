# Postmortem — Phase 6 Direct-balance providers
Date: 2026-11-15 · Stages: 6.1 (#28), 6.2 (#29)

## Outcome vs. phase map
14 § 0.5: "Direct-balance accounts, CN¥ handling."
- **Direct-balance accounts:** met.
  - **DeepSeek** (6.1) reads `GET /user/balance` every 60 s and writes one `balance_snapshot` per currency.
  - **xAI** (6.2) reads `GET /v1/api-key`. It is direct when the probe finds a numeric `remaining_balance`, and anchored otherwise.
  - Remaining is the latest snapshot in the account's currency, shown without `≈` or `±`.
  - An unavailable DeepSeek account is forced `critical`. Its page shows the header chip, and the banner and notification say why.
- **CN¥ handling:** met. A CNY account shows `CN¥` amounts in both locales tested (`FormattersTests`). Every cross-account total counts it as `+ N non-USD`; nothing is converted (`OverviewTotalsTests`).
- **Verification:**
  - Core: `DeepSeekTests`, `XAITests`, `OverviewTotalsTests`.
  - App: `DirectBalanceUITests`, run in the phase-closing UI run (Q-041).
  - Both providers stay out of `Verified` until H3 records them (R13). Release builds still offer no provider.

## Patterns across stages
1. **The plan's file names collided with SwiftPM's rule that file names must be unique within a module** (6.1). 14 had named every adapter's files `{DTOs,Probe,Client}.swift`. **Root cause:** the plan was written per folder, but SwiftPM checks per module. **Fix:** a provider prefix (Q-045), applied again in 6.2 without cost. Phase 10's Anthropic and OpenRouter adapters must use the same scheme. 14 § 10.1/10.2 name no files, so nothing there needs changing.
2. **Docs that are also code.** In 6.1, adding a key to the `inputs_json` comment in 03's DDL broke 2.1's byte-for-byte check against `001_initial.sql`. **Lesson:** 03's DDL block is the migration. A contract note goes in prose, 07, or `QUESTIONS.md`, never inside the DDL.
3. **Phase 5's direct path held up.** Phase 5 had listed `balance_snapshot`, never written by a real adapter, as phase 6's main risk. These paths needed no change: the `direct` remaining, the CN¥ symbol, the USD-only totals, and the mode-gated anchor UI. Only the "which snapshot" rule needed a fix, because a reading can hold two currencies.

## Plan and doc changes
- **14:**
  - § 6.1 and § 6.2: prefixed file names; fixture names follow the endpoint (`balance.401`, `api_key.401`); full inventories (D1); `DirectBalanceUITests` added.
- **07:**
  - `ui.band_change` adds `unavailable: 1`;
  - `poll.provider_rule` gains the `xai_no_balance_field` example.
- **08:**
  - the account header's unavailable chip;
  - the banner's `DeepSeek: account unavailable`.
- **11:** the 401 fixtures of both providers.
- **Judgment calls:** Q-045 (6.1), Q-046 (6.2).
- **Process:** the owner chose Q-041's cadence for phase 6 too: one full UI run, at 6.2. From phase 7 the owner wants UI tests run only where code was added or changed (confirmed 2026-11-15). 7.1 builds this as Q-047:
  - each suite declares the app paths it covers, and verify runs the suites whose paths the branch touched;
  - the launch and empty-popover smoke tests always run;
  - a change to shared files (`AppModel`, `Startup`, `AppEnvironment`, UI-test support) runs the full suite;
  - the full suite runs once more before 11.5.
- **Proposed for later phases:**
  - 7.2 makes harness spend the burn of both providers (PM-6.1-3, PM-6.2-2).
  - D-deepseek-single-app's inferred attribution should read balance deltas from `balance_snapshot`.

## Gates and risks
- **H3 (DeepSeek and xAI recordings):** open. The owner has both keys in `.env` and runs `scripts/record-fixtures.sh deepseek` and `xai` in their own Terminal. The consuming PR follows PM-6.1-1 and PM-6.2-1.
  - **Risk:** xAI's `remaining_balance` is `[expected]` from secondary sources. A recording may show the field is absent, which keeps xAI anchored. It may also show a different unit.
- **H2 (OpenAI):** still open (PM-3.6-1).
- **Risks for phase 7:**
  - DeepSeek and xAI have no burn until harness ingest (7.2). Until then their runway reads `Collecting…` and their band stays `unknown` (except DeepSeek's forced `critical`).
  - `balance_snapshot` grows by about 1,440 rows a day per currency until 9.1 thins it (PM-6.1-4).

## Open carry-forward actions
- **Phase 6:**
  - PM-6.1-1 · agent · the H3 PR · the DeepSeek recording diff, then `Verified += .deepseek`.
  - PM-6.1-3 · agent · 7.2 · DeepSeek burn and runway from harness spend; single-app inference from balance deltas.
  - PM-6.1-4 · agent · 9.1 · thin `balance_snapshot` per 03's retention.
  - PM-6.2-1 · agent · the H3 PR · the xAI recording diff: 13 § D-xai-balance, `Verified += .xai`.
  - PM-6.2-2 · agent · 7.2 · anchored xAI runway and estimate band from harness spend.
- **Phase 5 and earlier (unchanged):**
  - PM-5.2-3 · accepted · the reprice race.
  - PM-5.4-2 · 9.5 · the 24 h notification dedupe is lost at relaunch.
  - PM-5.5-1 · 11.3 · the metric's look.
  - PM-4.1-1 · 11.3 · the popover footer.
  - PM-4.3-3 · 9.1 / 9.4 · the daily steps.
  - PM-3.6-1 · Nikola · H2 · re-record OpenAI.
  - PM-3.6-2 · agent · the H2 PR.
  - Process: PM-4.1-2, PM-4.1-4, PM-4.2-4, PM-4.2-5, PM-4.3-1, PM-4.3-2, PM-5.1-3, PM-5.1-4, PM-5.1-5, PM-5.1-6 (owner, disk), PM-5.3-4, PM-5.5-2.
