# Stage 6.1 — DeepSeek adapter (14 § Stage 6.1). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
ds=$core/Providers/DeepSeek
fixtures=Tests/Fixtures/providers/deepseek
inventory=(
  $ds/DeepSeekDTOs.swift $ds/DeepSeekProbe.swift $ds/DeepSeekClient.swift $core/Store/Repository+Balance.swift
  $fixtures/balance.ok.synthetic.json $fixtures/balance.cny.synthetic.json
  $fixtures/balance.unavailable.synthetic.json $fixtures/balance.401.synthetic.json
  Tests/TokenBeCoreTests/AdapterTests/DeepSeekTests.swift Tests/TokenBeCoreTests/OverviewTotalsTests.swift
  Tests/TokenBeCoreTests/Support/DeepSeekHarness.swift scripts/stages/6.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 2: GET /user/balance with a Bearer key; string amounts → cents via Decimal; one snapshot per currency.
check "DeepSeek calls 02's endpoint on 02's host" bash -c "grep -qF 'static let host = \"api.deepseek.com\"' $ds/DeepSeekClient.swift && grep -qF 'static let balancePath = \"/user/balance\"' $ds/DeepSeekClient.swift"
check "02's Authorization header" bash -c "grep -qF 'BearerRequest.get(host: host, path: balancePath' $ds/DeepSeekClient.swift && grep -qF '\"Authorization\": \"Bearer \\(key)\"' $core/Providers/BearerRequest.swift"
check "amounts are strings parsed strictly into cents (R7: no Double)" bash -c "grep -qF 'MinorUnits.decimal(text)' $ds/DeepSeekDTOs.swift && ! grep -nE 'Double|Float' $ds/*.swift"
check "02's fields and nothing else" bash -c "for k in is_available balance_infos total_balance granted_balance topped_up_balance; do grep -qF \"\\\"\$k\\\"\" $ds/DeepSeekDTOs.swift || exit 1; done"
check "the probe's currency is the first entry's (02)" grep -qF 'balance.balanceInfos.first, let currency = Currency(rawValue: first.currency)' $ds/DeepSeekProbe.swift

# Step 3: the balance job writes; direct remaining in the account's currency; unavailable forces critical.
check "the poller writes balance snapshots (PM-3.4-4)" bash -c "grep -qF 'try await store.insertBalanceSnapshots(reading.snapshots)' $core/Scheduling/Poller.swift && ! grep -qF '_balance_not_stored' $core/Scheduling/Poller.swift"
check "PollStore and Repository include BalanceRepository (D5)" bash -c "grep -A1 'public typealias PollStore' $core/Store/Repository.swift | grep -qF 'BalanceRepository' && grep -qF '& BandRepository & BalanceRepository' $core/Store/Repository.swift"
check "direct remaining reads the account currency's snapshot" grep -qF 'balance(accountID: accountID, currency: currency, inputs: inputs)?.amountCents' $core/Ledger/Remaining.swift
check "unavailable is evaluated before every other band rule" bash -c "grep -A1 'public static func band(_ inputs: Inputs' $core/Ledger/BandEvaluator.swift | grep -qF 'if inputs.providerUnavailable { return (.critical, false) }'"
check "the header chip copy is 13's, word for word" bash -c "grep -qF 'header chip \`Provider reports account unavailable\`' docs/13-decisions.md && grep -qF 'static let providerUnavailable = \"Provider reports account unavailable\"' $app/Strings.swift && grep -qF 'Text(Strings.providerUnavailable)' $app/Dashboard/AccountDetailView.swift"
check "08's account header lists the chip" grep -qF 'Provider reports account unavailable' docs/08-ui-spec.md

# Wiring: the app offers DeepSeek (DEBUG; Release after RECORDED) and fixture mode serves it.
check "AppEnvironment registers the DeepSeek adapter" grep -qF 'DeepSeekAdapter()' $app/Startup.swift
check "FixtureTransport routes DeepSeek" grep -qF 'DeepSeekAdapter.fixtureRoutes' $core/Network/FixtureTransport.swift
check "DeepSeek is verified exactly when its RECORDED marker exists (R13)" bash -c "if [[ -f $fixtures/RECORDED ]]; then grep -qF '.deepseek' $core/Providers/Verified.swift; else ! grep -qF '.deepseek' $core/Providers/Verified.swift; fi"

for suite in DeepSeekTests OverviewTotalsTests FormattersTests LedgerTests PollerTests VerifiedProvidersTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "fixtures are redacted (R11)" scripts/record-fixtures.sh --verify-redacted "$fixtures"
# Q-041 (the owner's choice for phase 6 too): the UI suite runs once, at 6.2; 6.1 compiles it.
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
