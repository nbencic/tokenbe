# Stage 10.0.2 — xAI on its Management API (14 § Stage 10.0.2, Q-062). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
xai=$core/Providers/XAI
fixtures=Tests/Fixtures/providers/xai
inventory=(
  $xai/XAIDTOs.swift $xai/XAIProbe.swift $xai/XAIClient.swift $core/Providers/BearerRequest.swift
  $core/Scheduling/Job.swift $app/Onboarding/Step1Provider.swift
  $fixtures/validation.ok.synthetic.json $fixtures/validation.legacy.synthetic.json
  $fixtures/validation.organization.synthetic.json $fixtures/validation.401.synthetic.json
  $fixtures/usage.ok.synthetic.json $fixtures/usage.limit.synthetic.json $fixtures/usage.403.synthetic.json
  $fixtures/usage.drift.synthetic.json
  Tests/TokenBeCoreTests/AdapterTests/XAITests.swift scripts/check-no-secrets.sh scripts/record-fixtures.sh
  scripts/stages/10.0.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# The guard (Q-062): a management key can buy credit and change limits, so TokenBe names exactly two management
# paths, on one host, and no other billing path.
check "xAI's host is management-api.x.ai; the inference API is gone" bash -c "grep -qF 'static let host = \"management-api.x.ai\"' $xai/XAIClient.swift && ! grep -rnF --include='*.swift' 'api.x.ai/v1' Sources && ! grep -rnF '/v1/api-key' $xai"
paths_allowed() { # every path literal in the xAI adapter is one of the two 02 allows
  local found want
  found="$(grep -rhoE '"/[^"]*"' $xai/*.swift | sort -u | paste -sd' ' -)"
  want='"/auth/management-keys/validation" "/v1/billing/teams/\(team)/usage"'
  [[ "$found" == "$want" ]] || { echo "xAI path literals: $found"; return 1; }
}
check "the xAI adapter names exactly the validation and usage paths" paths_allowed
check "no code names another management billing path (top-up, limits, billing info, payment method, invoices, prepaid)" bash -c "! grep -rnoiE '\"[^\" ]*/[^\" ]*(top-?up|spending-limits|billing-info|payment-method|invoice|prepaid)[^\" ]*\"' Sources/TokenBeCore Sources/TokenBeApp --include='*.swift'"
check "only the xAI adapter names the management host" bash -c "test \"\$(grep -rlF --include='*.swift' 'management-api.x.ai' Sources)\" == '$xai/XAIClient.swift'"
check "the recorder reads only validation, usage and prepaid balance on the management host" bash -c "! grep -nF 'api.x.ai/v1' scripts/record-fixtures.sh && test \$(grep -cE 'management-api|/billing/teams/' scripts/record-fixtures.sh) -ge 3 && ! grep -niE 'top-?up|spending-limits|billing-info|payment-method|invoice' scripts/record-fixtures.sh"
check "the URL allowlist names management-api.x.ai, not api.x.ai" bash -c "grep -qF '\"management-api.x.ai\"' scripts/check-no-secrets.sh && ! grep -qF '\"api.x.ai\"' scripts/check-no-secrets.sh"

# Probe and cost job.
check "capabilities: cost only, anchored, USD" bash -c "grep -A2 'public static let capabilities' $xai/XAIClient.swift | grep -qF 'usage: false, cost: true, balance: false' && grep -A2 'public static let capabilities' $xai/XAIClient.swift | grep -qF 'balanceModeDefault: .anchored'"
check "the usage request: daily USD per model, Etc/GMT, wrapped in analyticsRequest (02)" bash -c "grep -qF 'static let timeUnit = \"TIME_UNIT_DAY\"' $xai/XAIDTOs.swift && grep -qF 'static let groupBy = \"description\"' $xai/XAIDTOs.swift && grep -qF 'static let value = \"usd\"' $xai/XAIDTOs.swift && grep -qF 'static let timezone = \"Etc/GMT\"' $xai/XAIDTOs.swift && grep -qF '{\"analyticsRequest\":' $xai/XAIDTOs.swift"
check "the team: scopeId for SCOPE_TEAM, else the deprecated teamId" grep -qF 'if scope == "SCOPE_TEAM", let scopeId, !scopeId.isEmpty { return scopeId }' $xai/XAIDTOs.swift
check "cost rows: description per model and total per day" bash -c "grep -qF 'rows += models.map { row(\"description\", \$0, amounts[\$0] ?? 0) }' $xai/XAIClient.swift && grep -qF 'rows.append(row(\"total\", \"\"' $xai/XAIClient.swift"
check "xAI's cost runs on the keys period (04, Q-062)" bash -c "grep -qF 'case (.cost, .xai): .pollKeysIntervalS' $core/Scheduling/Job.swift && grep -qF 'for job in Job.scheduled {' $core/Scheduling/PollCoordinator+Inputs.swift"
check "xAI's money is Decimal, never Double (R7)" bash -c "! grep -nE 'Double|Float' $xai/*.swift"
check "onboarding's xAI caption is Management key (08)" grep -qF 'case .openrouter, .xai: Strings.captionOpenRouter' $app/Onboarding/Step1Provider.swift

# Docs (D9).
check "02 § xai: management host, the two paths, the never-called list" bash -c "grep -qF 'Base: \`https://management-api.x.ai\`' docs/02-provider-apis.md && grep -qF 'GET /auth/management-keys/validation' docs/02-provider-apis.md && grep -qF 'POST /v1/billing/teams/{team_id}/usage' docs/02-provider-apis.md && grep -qF 'Never called: \`prepaid/top-up\`' docs/02-provider-apis.md"
check "13 § D-xai-balance records the soak's response and Q-062" bash -c "grep -F '| D-xai-balance |' docs/13-decisions.md | grep -qF 'Q-062'"
check "07 names xAI's rules" bash -c "grep -qF 'xai_usage_limit_reached' docs/07-logging.md && grep -qF 'xai_key_has_no_team' docs/07-logging.md"
check "08's xAI caption" grep -qF '`Management key` (xAI, Q-062)' docs/08-ui-spec.md
check "01 S1 lists xAI's management key" grep -qF 'xAI (management key, Q-062)' docs/01-product-scope.md

for suite in XAITests CoordinatorTests VerifiedProvidersTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "fixtures are redacted (R11)" scripts/record-fixtures.sh --verify-redacted "$fixtures"
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
