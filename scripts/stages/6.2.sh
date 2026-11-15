# Stage 6.2 — xAI adapter (14 § Stage 6.2). Sourced by scripts/verify-stage.sh. Closes phase 6.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
xai=$core/Providers/XAI
fixtures=Tests/Fixtures/providers/xai
inventory=(
  $xai/XAIDTOs.swift $xai/XAIProbe.swift $xai/XAIClient.swift $core/Providers/BearerRequest.swift
  $fixtures/api_key.ok.synthetic.json $fixtures/api_key.no_balance.synthetic.json $fixtures/api_key.401.synthetic.json
  Tests/TokenBeCoreTests/AdapterTests/XAITests.swift Tests/TokenBeUITests/DirectBalanceUITests.swift
  scripts/stages/6.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 2: probe GET /v1/api-key; a numeric remaining_balance → direct, else anchored with poll.provider_rule.
check "xAI calls 02's endpoint on 02's host" bash -c "grep -qF 'static let host = \"api.x.ai\"' $xai/XAIClient.swift && grep -qF 'static let apiKeyPath = \"/v1/api-key\"' $xai/XAIClient.swift && grep -qF 'BearerRequest.get(host: host, path: apiKeyPath' $xai/XAIClient.swift"
check "only 02's [expected] balance fields are named" bash -c "for k in remaining_balance spent_balance total_granted; do grep -qF \"\\\"\$k\\\"\" $xai/XAIDTOs.swift || exit 1; done"
check "remaining_balance is decoded as a number (Decimal), never Double (R7)" bash -c "grep -qF 'decodeIfPresent(Decimal.self, forKey: .remainingBalance)' $xai/XAIDTOs.swift && ! grep -nE 'Double|Float' $xai/*.swift"
check "the fallback is anchored without a balance job" bash -c "grep -A2 'static let anchoredCapabilities' $xai/XAIClient.swift | grep -qF 'balance: false' && grep -A2 'static let anchoredCapabilities' $xai/XAIClient.swift | grep -qF 'balanceModeDefault: .anchored'"
check "the fallback logs poll.provider_rule rule=xai_no_balance_field (14 § 6.2 step 2, 07)" bash -c "grep -qF 'static let noBalanceRule = \"xai_no_balance_field\"' $xai/XAIClient.swift && grep -qF '.pollProviderRule' $xai/XAIProbe.swift && grep -qF 'xai_no_balance_field' docs/07-logging.md"

# Wiring.
check "AppEnvironment registers the xAI adapter" grep -qF 'XAIAdapter()' $app/Startup.swift
check "FixtureTransport routes xAI" grep -qF 'XAIAdapter.fixtureRoutes' $core/Network/FixtureTransport.swift
check "xAI is verified exactly when its RECORDED marker exists (R13)" bash -c "if [[ -f $fixtures/RECORDED ]]; then grep -qF '.xai' $core/Providers/Verified.swift; else ! grep -qF '.xai' $core/Providers/Verified.swift; fi"

for suite in XAITests DeepSeekTests VerifiedProvidersTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "fixtures are redacted (R11)" scripts/record-fixtures.sh --verify-redacted "$fixtures"
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
# Q-041 (the owner's choice for phase 6): this verify closes phase 6, so it runs the full UI suite once.
ui_check "DirectBalanceUITests passed (PM-6.1-2)" grep -q "Test Suite 'DirectBalanceUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
