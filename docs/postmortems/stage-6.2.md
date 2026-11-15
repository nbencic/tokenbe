# Postmortem — Stage 6.2 xAI adapter
Date: 2026-11-15 · Branch: s6.2-xai-adapter · PR: #29 · Planned size: S · Commits: 4

## Outcome
A user can add an xAI account with a standard API key (Debug builds; Release only once `xai/RECORDED` exists). The mode is set by the probe (D-xai-balance), which calls `GET /v1/api-key`:
- **Numeric `remaining_balance`:** the account is `direct`. A 60 s balance job writes one USD snapshot.
- **Field missing, null, or not a number:** the account is `anchored` with no balance job. Onboarding asks for the balance from the billing page. The fallback logs `poll.provider_rule rule=xai_no_balance_field`.

This stage closes phase 6. Its verify ran the full UI suite once (Q-041, the owner's choice for phase 6), including the new `DirectBalanceUITests` (PM-6.1-2). D1–D13 are met.

**Gate H3 is open for both providers.** The owner has both keys and runs the recorder. The PR that consumes H3 updates `13 § D-xai-balance` with the recorded shape and adds `Verified += .xai` (PM-6.2-1).

## What went as planned
- **6.1's lessons applied from the start:**
  - the file names were prefixed (`XAI…swift`, Q-045);
  - the 401 fixture is named after its endpoint (`api_key.401`);
  - 03's DDL was left alone.
- **Shared request code.** xAI's request is DeepSeek's with another path, so both now use `BearerRequest.get`. 6.1's Authorization check reads the shared helper.
- **Exact decimals.** `JSONDecoder` decodes `Decimal` from the number's digits: `42.505` became 4251 cents, not the 4250 a `Double` round trip gives. `XAITests` pins it.
- **The new UI suite passed on its first run.** `DirectBalanceUITests` covers DeepSeek onboarding to `direct`/`CNY` with no anchor field, the `CN¥` card without `≈`, and the unavailable banner. The run took 55 s, with 100 GiB free and the screen unlocked (PM-1.1-1, Q-039).
- **Checks dry-run before the full verify (PM-1.3-5).** 6.2's and 6.1's static checks passed on their own first.
- **Coverage:** 97.40 %.

## What went wrong
- One compile error in the new test: `LogRecord`'s level property is `lvl`. **Cost:** one build. Nothing else; the evidence is in the next section.

## Verify and CI failures
- `swift test`: 460 tests passed on the first full run.
- `swiftlint --strict`: clean on the first run.
- The full verify (UI on) is recorded below once it finishes.

## Deviations from the docs
- **14 § 6.2:** the files are prefixed (`XAI{DTOs,Probe,Client}.swift`). The fixtures include `api_key.401`. The inventory names every touched file, including `BearerRequest.swift` and `6.1.sh`. The tests include `DirectBalanceUITests`.
- **07 `poll.provider_rule`:** the `xai_no_balance_field` example.
- **11:** the `xai/api_key.401` fixture.
- **13 § D-xai-balance:** unchanged until the recording (step 3, H3).

## Judgment calls
- Q-046 · xAI: what "numeric" means, the unit (dollars), a direct account that loses the field, the snapshot's columns, capabilities, the key-refused copy, the shared request, and step 3's status (an open gate, not resolved-by-scope).

## Carry-forward actions
- PM-6.2-1 · agent · the PR that consumes H3 · Diff `xai/api_key.*.recorded.json` against 02 and the synthetic files, then:
  - confirm or correct the field names and the unit of `remaining_balance`;
  - update `13 § D-xai-balance` with the recorded shape;
  - add `Verified += .xai`;
  - drop `[expected]` from 02's xai section;
  - append `## Addendum — H3 closed` here and in `stage-6.1.md` (with PM-6.1-1).
- PM-6.2-2 · agent · 7.2 · An anchored xAI account has spend only from harness reports. When ingest lands, check its runway and the estimate band, where `usageLag` is 60 s.
- **Earlier actions that targeted this stage:** PM-6.1-2 closed (`DirectBalanceUITests`; status edited in `stage-6.1.md`).
