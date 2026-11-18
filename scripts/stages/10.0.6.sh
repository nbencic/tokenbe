# Stage 10.0.6 — Recorder and H6: StepFun, SiliconFlow, DeepInfra (14 § Stage 10.0.6, Q-062). Sourced by
# scripts/verify-stage.sh.

inventory=(scripts/record-fixtures.sh docs/02-provider-apis.md scripts/stages/10.0.6.sh)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

for var in XAI_MANAGEMENT_KEY MOONSHOT_API_KEY NOVITA_API_KEY STEPFUN_API_KEY SILICONFLOW_API_KEY DEEPINFRA_API_KEY; do
  check "record-fixtures.sh --help names $var" bash -c "scripts/record-fixtures.sh --help | grep -q $var"
done
check "each H6 provider refuses to record without its key and writes nothing" bash -c "for p in moonshot novita stepfun siliconflow deepinfra; do v=\$(echo \$p | tr a-z A-Z)_API_KEY; env -u \$v scripts/record-fixtures.sh \$p | grep -q \"set \$v\" || exit 1; done; [[ -z \"\$(git status --porcelain Tests/Fixtures/providers)\" ]]"
check "the recorder calls 02's endpoints (international first, China after a 401)" bash -c "f=scripts/record-fixtures.sh; grep -qF 'https://api.moonshot.ai/v1/users/me/balance' \$f && grep -qF 'https://api.moonshot.cn/v1/users/me/balance' \$f && grep -qF 'https://api.novita.ai/openapi/v1/billing/balance/detail' \$f && grep -qF 'https://api.stepfun.ai/v1/accounts' \$f && grep -qF 'https://api.stepfun.com/v1/accounts' \$f && grep -qF 'https://api.siliconflow.com/v1/user/info' \$f && grep -qF 'https://api.siliconflow.cn/v1/user/info' \$f && grep -qF 'https://api.deepinfra.com/v1/me?checklist=true' \$f && grep -qF 'https://api.deepinfra.com/payment/usage?from=current' \$f && test \$(grep -cF 'if [[ \"\$LAST_STATUS\" == 401 ]]; then' \$f) -eq 3"
check "the recorder's self-test still passes (redaction)" scripts/record-fixtures.sh --self-test
check "the recorder never reads .env and passes keys on stdin" bash -c "! grep -nE '(source|\\.) +[^ ]*\\.env|cat +[^ ]*\\.env' scripts/record-fixtures.sh && ! grep -nE 'curl [^|]*KEY_VALUE' scripts/record-fixtures.sh"
check "02 lists the three H6 providers and their open questions (R2: no synthetic fixture)" bash -c "grep -qF '## stepfun, siliconflow, deepinfra (not built until H6 records them)' docs/02-provider-apis.md && ! ls Tests/Fixtures/providers | grep -qE '^(stepfun|siliconflow|deepinfra)$' || ls Tests/Fixtures/providers/{stepfun,siliconflow,deepinfra}/RECORDED >/dev/null 2>&1"
check "no adapter or ProviderID case exists yet for an unrecorded H6 provider" bash -c "for p in stepfun siliconflow deepinfra; do if [[ ! -f Tests/Fixtures/providers/\$p/RECORDED ]]; then ! grep -qE \"case .*\\b\$p\\b\" Sources/TokenBeCore/Providers/ProviderID.swift || exit 1; fi; done"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
