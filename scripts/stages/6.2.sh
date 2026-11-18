# Stage 6.2 — xAI adapter (14 § Stage 6.2). Sourced by scripts/verify-stage.sh. Closes phase 6.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
xai=$core/Providers/XAI
fixtures=Tests/Fixtures/providers/xai
inventory=(
  $xai/XAIDTOs.swift $xai/XAIProbe.swift $xai/XAIClient.swift $core/Providers/BearerRequest.swift
  $fixtures/validation.ok.synthetic.json $fixtures/usage.ok.synthetic.json
  Tests/TokenBeCoreTests/AdapterTests/XAITests.swift Tests/TokenBeUITests/DirectBalanceUITests.swift
  scripts/stages/6.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 2 (GET /v1/api-key, direct or anchored by remaining_balance) is superseded by 10.0.2: the recorded endpoint has
# no balance, and xAI moved to its Management API (Q-062). 10.0.2.sh checks the new probe and cost job.
check "xAI's money is Decimal, never Double (R7)" bash -c "! grep -nE 'Double|Float' $xai/*.swift"

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
