# Postmortem — Stage 10.0.6 Recorder and H6: StepFun, SiliconFlow, DeepInfra
Date: 2026-11-18 · Branch: s10.0.6-recorder-h6 · PR: #50 · Planned size: S · Commits: 2

## Outcome
`scripts/record-fixtures.sh` now records the providers Q-062 added. Each reads its key from one environment variable, and nothing can reach `.env` or the command line.
- **xAI (`XAI_MANAGEMENT_KEY`, from 10.0.2):** validation, usage and prepaid balance.
- **Moonshot (`MOONSHOT_API_KEY`):** the international host, then the China host after a 401.
- **Novita (`NOVITA_API_KEY`):** the balance detail.
- **StepFun (`STEPFUN_API_KEY`):** `/v1/accounts`, `.ai` then `.com`.
- **SiliconFlow (`SILICONFLOW_API_KEY`):** `/v1/user/info`, `.com` then `.cn`.
- **DeepInfra (`DEEPINFRA_API_KEY`):** `/v1/me?checklist=true` and `/payment/usage?from=current`, the latter to learn whether an inference key may read it.

02 now has an `[expected]` section for StepFun, SiliconFlow and DeepInfra listing each open question. Per 12 § R2 they get no synthetic fixture, no adapter and no `ProviderID` case until H6 records them. D1–D13 are met; the soak runs, so the verify ran with `TB_UI_TESTS=0 TB_SOAK=1`. **H6 is open (owner).**

## What went as planned
- **The recorder kept its guarantees:**
  - keys go to curl on stdin;
  - `.env` is never read;
  - redaction runs on every body, and the self-test passed;
  - a missing key refuses and writes nothing (now checked for every H6 provider).
- **A recorded 401 on the international host is kept** as `<endpoint>.401.recorded.json`, so each region's refusal body is on record too.

## What went wrong
1. **DeepInfra's usage call would have failed for the wrong reason.** `/payment/usage` requires `from` (02, OpenAPI). The first draft called it without parameters, which would have recorded a 4xx about the missing parameter instead of the auth answer we want. Caught while writing 02's section; the URL now has `from=current`. Cost: none.

## Verify and CI failures
- **Dry run of 3.3, 10.0.2 and 10.0.6:** green.
- **Cumulative sweep:** result below.

## Deviations from the docs
- **The plan (14 § 10.0.6) said each H6 provider writes "a `RECORDED` marker".** The recorder writes one marker per provider folder, as for the earlier providers. For StepFun, SiliconFlow and DeepInfra, its closing message asks for a review and a commit, not a `Verified` edit, because no adapter exists yet.

## Judgment calls
- None new (Q-062).

## Carry-forward actions
- PM-10.0.6-1 · Nikola · H6 · In your own Terminal, with the keys you hold, run `scripts/record-fixtures.sh <provider>` for xai (management key), moonshot, novita, stepfun, siliconflow and deepinfra. Review the files under `Tests/Fixtures/providers/<provider>/`, then say "recorded <providers>".
- PM-10.0.6-2 · agent · when H6 closes · For each recorded provider:
  - Moonshot and Novita: diff the recording against 02 and add them to `Verified`.
  - xAI: decide from `prepaid_balance` whether it turns direct.
  - StepFun, SiliconFlow and DeepInfra: plan an adapter stage (10.0.7+).
- Earlier actions that target this stage: PM-10.0.2-2, PM-10.0.4-3 and PM-10.0.5-3 (the recorder entries) are closed by this stage; their recordings are H6.
