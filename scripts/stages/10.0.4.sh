# Stage 10.0.4 — Moonshot (Kimi) (14 § Stage 10.0.4, 02 § moonshot, Q-062). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
ms=$core/Providers/Moonshot
fixtures=Tests/Fixtures/providers/moonshot
inventory=(
  $ms/MoonshotClient.swift $ms/MoonshotProbe.swift $ms/MoonshotDTOs.swift $core/Providers/ProviderID.swift
  $fixtures/balance.ok.synthetic.json $fixtures/balance_cn.ok.synthetic.json $fixtures/balance.401.synthetic.json
  $fixtures/balance.owing.synthetic.json $fixtures/balance.not_ok.synthetic.json $fixtures/balance.drift.synthetic.json
  Tests/TokenBeCoreTests/AdapterTests/MoonshotTests.swift scripts/stages/10.0.4.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

check "ProviderID.moonshot, after xAI (08 tile order), named Moonshot" bash -c "grep -qF 'case openai, anthropic, openrouter, deepseek, xai, moonshot' $core/Providers/ProviderID.swift && grep -qF 'case .moonshot: \"Moonshot\"' $core/Providers/ProviderID.swift"
check "02's endpoint on both regions' hosts" bash -c "grep -qF 'static let hostUSD = \"api.moonshot.ai\"' $ms/MoonshotClient.swift && grep -qF 'static let hostCNY = \"api.moonshot.cn\"' $ms/MoonshotClient.swift && grep -qF 'static let balancePath = \"/v1/users/me/balance\"' $ms/MoonshotClient.swift"
check "the poll's host follows the account currency (no new column)" bash -c "grep -qF 'currency == Currency.cny.rawValue ? hostCNY : hostUSD' $ms/MoonshotClient.swift && grep -qF 'trace: trace, currency: account.currency' $core/Scheduling/Poller.swift"
check "the probe tries China only after a 401, logged at debug as poll.region_fallback" bash -c "grep -qF 'catch .auth(let status, _) where status == 401' $ms/MoonshotProbe.swift && grep -qF 'log.emit(.debug, .pollRegionFallback' $ms/MoonshotProbe.swift && grep -qF '| \`poll.region_fallback\` | debug |' docs/07-logging.md"
check "only 02's fields; amounts are Decimal, never Double (R7)" bash -c "for k in available_balance voucher_balance cash_balance; do grep -qF \"\\\"\$k\\\"\" $ms/MoonshotDTOs.swift || exit 1; done && ! grep -nE 'Double|Float' $ms/*.swift"
check "snapshot: available → amount, voucher → granted, cash → topped up" bash -c "grep -qF 'amountCents: balance.availableCents, grantedCents: balance.voucherCents, toppedUpCents: balance.cashCents' $ms/MoonshotClient.swift"
check "status false / code ≠ 0 is the moonshot_status_not_ok rule (07)" bash -c "grep -qF 'guard decoded.value.status, decoded.value.code == 0 else { throw .providerRule(Self.notOKRule) }' $ms/MoonshotClient.swift && grep -qF 'moonshot_status_not_ok' docs/07-logging.md"
check "registered, fixture-routed, Moonshot not Verified until recorded (R13)" bash -c "grep -qF 'MoonshotAdapter()' $app/Startup.swift && grep -qF 'MoonshotAdapter.fixtureRoutes' $core/Network/FixtureTransport.swift && if [[ -f $fixtures/RECORDED ]]; then grep -qF '.moonshot' $core/Providers/Verified.swift; else ! grep -qF '.moonshot' $core/Providers/Verified.swift; fi"
check "harness: OpenAI-compatible normalizer, moonshot price prefix, cache savings from harness" bash -c "grep -qF 'case .openai, .openrouter, .moonshot:' $core/Normalize/HarnessNormalizer.swift && grep -qF 'case .moonshot: \"moonshot\"' $core/Pricing/Lookup.swift && grep -qF 'case .deepseek, .xai, .moonshot: .success([\"harness\"])' $core/Ledger/CacheSavings.swift"
check "app: glyph K, caption Balance only, lag help" bash -c "grep -qF 'case .moonshot: \"K\"' $app/Components/ProviderGlyph.swift && grep -qF 'case .deepseek, .moonshot: Strings.captionBalanceOnly' $app/Onboarding/Step1Provider.swift && grep -qF 'case .moonshot: \"The balance updates' $app/Strings.swift"
check "the URL allowlist names both Moonshot hosts" bash -c "grep -qF '\"api.moonshot.ai\" \"api.moonshot.cn\"' scripts/check-no-secrets.sh"
check "docs: 02 § moonshot, 05 normalizer row, 06 provider list, 08 tiles, the reporters" bash -c "grep -qF '## moonshot' docs/02-provider-apis.md && grep -qF '| moonshot per-response (harness) |' docs/05-normalization-pricing-runway.md && grep -qF '\`xai\`, \`moonshot\` (lowercase; Q-062)' docs/06-harness-ingest.md && grep -qF '6 tiles (OpenAI, Anthropic, OpenRouter, DeepSeek, xAI, Moonshot)' docs/08-ui-spec.md && test \$(grep -l 'deepseek | xai | moonshot' docs/reporters/* $app/Resources/reporters/* README.md | wc -l) -eq 5"

for suite in MoonshotTests ProviderIDTests SettingsTests VerifiedProvidersTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "fixtures are redacted (R11)" scripts/record-fixtures.sh --verify-redacted "$fixtures"
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
