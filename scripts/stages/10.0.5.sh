# Stage 10.0.5 — Novita (14 § Stage 10.0.5, 02 § novita, Q-062). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
nv=$core/Providers/Novita
fixtures=Tests/Fixtures/providers/novita
inventory=(
  $nv/NovitaClient.swift $nv/NovitaProbe.swift $nv/NovitaDTOs.swift $app/Onboarding/Step1Provider.swift
  $fixtures/balance.ok.synthetic.json $fixtures/balance.rounding.synthetic.json $fixtures/balance.401.synthetic.json
  $fixtures/balance.drift.synthetic.json Tests/TokenBeCoreTests/AdapterTests/NovitaTests.swift scripts/stages/10.0.5.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

check "ProviderID.novita after Moonshot, named Novita" bash -c "grep -qF 'case openai, anthropic, openrouter, deepseek, xai, moonshot, novita' $core/Providers/ProviderID.swift && grep -qF 'case .novita: \"Novita\"' $core/Providers/ProviderID.swift"
check "02's endpoint on 02's host" bash -c "grep -qF 'static let host = \"api.novita.ai\"' $nv/NovitaClient.swift && grep -qF 'static let balancePath = \"/openapi/v1/billing/balance/detail\"' $nv/NovitaClient.swift"
check "only 02's fields; 1/10000 USD strings → cents once, Decimal never Double (05, R7)" bash -c "grep -qF 'case availableBalance, cashBalance, creditLimit, pendingCharges, outstandingInvoices' $nv/NovitaDTOs.swift && grep -qF 'return MinorUnits.cents(units / 10_000)' $nv/NovitaDTOs.swift && grep -qF 'guard let units = MinorUnits.decimal(text) else {' $nv/NovitaDTOs.swift && ! grep -nE 'Double|Float' $nv/*.swift"
check "snapshot: available → amount, cash → topped up, USD" grep -qF 'amountCents: decoded.value.availableCents, grantedCents: nil, toppedUpCents: decoded.value.cashCents' $nv/NovitaClient.swift
check "registered, fixture-routed, not Verified until recorded (R13)" bash -c "grep -qF 'NovitaAdapter()' $app/Startup.swift && grep -qF 'NovitaAdapter.fixtureRoutes' $core/Network/FixtureTransport.swift && if [[ -f $fixtures/RECORDED ]]; then grep -qF '.novita' $core/Providers/Verified.swift; else ! grep -qF '.novita' $core/Providers/Verified.swift; fi"
check "harness: OpenAI-compatible normalizer, novita price prefix, cache savings from harness" bash -c "grep -qE 'case \\.openai, \\.openrouter, \\.moonshot, \\.novita[,:]' $core/Normalize/HarnessNormalizer.swift && grep -qF 'case .novita: \"novita\"' $core/Pricing/Lookup.swift && grep -qE 'case \\.deepseek, \\.xai, \\.moonshot, \\.novita[,:].*\\.success' $core/Ledger/CacheSavings.swift"
check "app: glyph N, caption Balance only, lag help, key-rejected copy" bash -c "grep -qF 'case .novita: \"N\"' $app/Components/ProviderGlyph.swift && grep -qE 'case \\.deepseek, \\.moonshot, \\.novita[,:].*captionBalanceOnly' $app/Onboarding/Step1Provider.swift && grep -qF 'case .novita: \"The balance updates' $app/Strings.swift && grep -qF 'case .novita: CoreStrings.Novita.keyRejected' $core/Network/PollError.swift"
check "onboarding's tile grid scrolls, so Cancel and Continue stay in the 440 pt window (08)" bash -c "grep -A2 'ScrollView {' $app/Onboarding/Step1Provider.swift | grep -qF 'LazyVGrid(columns: columns'"
check "the URL allowlist names api.novita.ai" grep -qF '"api.novita.ai"' scripts/check-no-secrets.sh
check "docs: 02 § novita, 05 currency and normalizer rows, 06 provider list, 08 tiles, the reporters" bash -c "grep -qF '## novita' docs/02-provider-apis.md && grep -qF '**Novita** reports USD in 1/10000 units' docs/05-normalization-pricing-runway.md && grep -qF '| novita per-response (harness) |' docs/05-normalization-pricing-runway.md && grep -qF '\`moonshot\`, \`novita\` (lowercase; Q-062)' docs/06-harness-ingest.md && grep -qF '7 tiles (OpenAI, Anthropic, OpenRouter, DeepSeek, xAI, Moonshot, Novita)' docs/08-ui-spec.md && test \$(grep -l 'moonshot | novita' docs/reporters/* $app/Resources/reporters/* README.md | wc -l) -eq 5"

for suite in NovitaTests MoonshotTests ProviderIDTests SettingsTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "fixtures are redacted (R11)" scripts/record-fixtures.sh --verify-redacted "$fixtures"
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
