# Stage 5.2 — Cost estimation & unpriced surfacing (14 § Stage 5.2). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Pricing/CostEstimator.swift $core/Pricing/PriceBook.swift $core/Ledger/Spend.swift
  $core/Store/Repository+Usage.swift $core/Store/Observation.swift $app/Dashboard/NumbersStrip.swift
  Tests/Fixtures/expected/pricing.csv Tests/TokenBeCoreTests/CostFormulaTests.swift
  Tests/TokenBeCoreTests/RepriceTests.swift Tests/TokenBeCoreTests/SpendTests.swift scripts/stages/5.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: 05's formula — the fallback multipliers over one denominator, half-up once, no _above_200k.
check "fallbacks 1.25/2.0/0.1 as 25/40/2 over 20" bash -c "grep -qF 'fallbackNumerator: 25' $core/Pricing/CostEstimator.swift && grep -qF 'fallbackNumerator: 40' $core/Pricing/CostEstimator.swift && grep -qF 'fallbackNumerator: 2,' $core/Pricing/CostEstimator.swift"
check "the 1h write falls back to the 5m write first" grep -qF 'entry.cacheWrite1h ?? entry.cacheWrite' $core/Pricing/CostEstimator.swift
check "no _above_200k rate is applied (05, O-7)" bash -c "! grep -v '^ *///' $core/Pricing/CostEstimator.swift | grep -n 'above_200k'"
check "no Double in the cost formula (R7)" bash -c "! grep -nE 'Double|Float' $core/Pricing/CostEstimator.swift $core/Ledger/Spend.swift"
check "pricing.csv has 16 cases" bash -c "[[ \$(tail -n +2 Tests/Fixtures/expected/pricing.csv | grep -c .) == 16 ]]"

# Step 2: every usage write is priced; reprice on a snapshot or override change.
check "the poller prices each page before writeUsagePage" bash -c "grep -B1 'try await store.writeUsagePage' $core/Scheduling/Poller.swift | grep -qF 'let priced = await price(page.rows'"
check "the app's poller gets the price book" grep -qF 'prices: environment.prices?.book' $app/Startup.swift
check "reprice after a new snapshot and each override change" bash -c "[[ \$(grep -c 'try await repriceAll()' $core/Pricing/PriceBook.swift) -ge 4 ]]"
check "reprice window is 90 days" grep -qF 'repriceWindow: TimeInterval = 90 * 86_400' $core/Pricing/PriceBook.swift
check "repriceUsage is one write (one transaction per account)" grep -qF 'database.write("repriceUsage")' $core/Store/Repository+Usage.swift

# Step 3: events, once per model per UTC day.
for evt in priceUnpriced priceFallbackMultiplier priceRepriced; do
  check "event .$evt emitted by Pricing" grep -rqF ".$evt," $core/Pricing
done
check "price events deduped per UTC day (DailyOnce)" grep -qF 'private let once = DailyOnce()' $core/Pricing/PriceBook.swift
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh

# Step 4: numbers strip and the Overview subline; 08 copy (D8).
check "account page shows the numbers strip" grep -qF 'NumbersStrip(summary: summary' $app/Dashboard/AccountDetailView.swift
check "unpriced cell only when the range has unpriced tokens, in HealthWatch" bash -c "grep -qF 'unpriced.tokens > 0' $app/Dashboard/NumbersStrip.swift && grep -qF 'Color(.healthWatch)' $app/Dashboard/NumbersStrip.swift"
check "Overview subline sums USD accounts only" bash -c "grep -qF 'Spend.totalUSD(model.accounts)' $app/Dashboard/OverviewView.swift && grep -qF 'non-USD' $app/Strings.swift"
check "the range setting rebuilds the summaries" bash -c "grep -A3 'private static let freshnessKeys' $app/AppModel.swift | grep -qF '.uiDashboardRange'"
check "Price book line counts unpriced models (PM-5.1-1)" grep -qF 'unpriced: status.unpricedModels' $app/SettingsUI/PriceBookSection.swift
for copy in 'Spend today' 'Spend in range' 'Unpriced in range' 'Total spend '; do
  check "Strings has copy: $copy" grep -qF "\"$copy" $app/Strings.swift
done

# PM-5.1-2: the silent-catch rule matches `try?`, not identifiers ending in "try" followed by `?`.
lint_selftest() {
  local d; d="$(mktemp -d)"
  printf 'struct PriceEntry {}\nfunc f(_ e: PriceEntry?) -> PriceEntry? { e }\n' > "$d/Ok.swift"
  printf 'func g() throws {}\nfunc h() { _ = try? g() }\n' > "$d/Bad.swift"
  local ok bad
  ok="$(cd "$d" && swiftlint lint --config "$OLDPWD/.swiftlint.yml" Ok.swift 2>&1 | grep -c tokenbe_no_silent_catch)"
  bad="$(cd "$d" && swiftlint lint --config "$OLDPWD/.swiftlint.yml" Bad.swift 2>&1 | grep -c tokenbe_no_silent_catch)"
  rm -rf "$d"
  [[ "$ok" == 0 && "$bad" -ge 1 ]] || { echo "self-test: PriceEntry? hits=$ok, try? hits=$bad"; return 1; }
}
check "lint self-test: \\btry\\? (PM-5.1-2)" lint_selftest

for suite in CostFormulaTests RepriceTests SpendTests FormattersTests OpenAITests; do
  check "suite $suite passed" suite_passed "$suite"
done
# 14 Verify: after a usage poll in fixture mode no row has est_cost_cents NULL with unpriced = 0.
check "the Verify SQL is asserted after a usage poll" grep -qF 'WHERE est_cost_cents IS NULL AND unpriced = 0' Tests/TokenBeCoreTests/RepriceTests.swift
# Q-041: UI tests run at the end of phase 5; every stage still compiles the UI-test target.
check "the app and UI tests compile (build-for-testing, Q-041)" scripts/run.sh build-uitest
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
