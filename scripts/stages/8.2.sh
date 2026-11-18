# Stage 8.2 — Spend-by-day chart & cache savings (14 § Stage 8.2). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Ledger/SpendChart.swift $core/Ledger/CacheSavings.swift
  $app/Dashboard/SpendByDayChart.swift $app/Dashboard/CacheTile.swift
  Tests/TokenBeCoreTests/CacheSavingsTests.swift Tests/TokenBeCoreTests/ChartDataTests.swift
  scripts/stages/8.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Core computes (04 I3): the chart's stacks from 05's daily rule, the savings with the estimator's own rates.
check "the builder fills the chart's days and daily spend and the cache savings" bash -c "grep -qF 'summary.dailySpend = daily.filter' $core/Ledger/AccountSummaryBuilder.swift && grep -qF 'summary.cacheSavings = CacheSavings.figure(summary' $core/Ledger/AccountSummaryBuilder.swift"
check "the stacks are USD accounts only; other currencies are counted, not converted (05 § Currency)" bash -c "grep -qF 'guard account.currency == .usd else' $core/Ledger/SpendChart.swift && grep -qF 'nonUSD += 1' $core/Ledger/SpendChart.swift"
check "savings subtract two CostEstimator totals (same rates and fallbacks as the estimate)" bash -c "grep -qF 'static func total(_ classes: TokenClasses, entry: PriceEntry?, fallbacks: inout' $core/Pricing/CostEstimator.swift && grep -qF 'CostEstimator.total(uncached' $core/Ledger/CacheSavings.swift && grep -qF 'CostEstimator.roundHalfUp(total)' $core/Ledger/CacheSavings.swift"
check "each provider's source: Anthropic provider (+ 9.1's rollup), DeepSeek and xAI harness, OpenAI not computed (05, D-openai-cache-savings-off)" bash -c "grep -qF 'case .anthropic: .success([\"provider\", \"rollup\"])' $core/Ledger/CacheSavings.swift && grep -qF 'case .deepseek, .xai: .success([\"harness\"])' $core/Ledger/CacheSavings.swift && grep -qF 'case .openai: .failure(.openAIAggregate)' $core/Ledger/CacheSavings.swift"
check "no money is a Double in the chart (plotted in cents)" bash -c "! grep -nE 'Double' $core/Ledger/SpendChart.swift && grep -qF 'y: .value(\"Spend\", segment.figure.cents)' $app/Dashboard/SpendByDayChart.swift"

# The Overview (08 § Overview 3 and 5): 08's order, the visible-only chart, O-3's palette, the tooltip, the tile.
overview_order() {
  local f=$app/Dashboard/OverviewView.swift b c a t
  b="$(grep -n 'RunwayBoard(model' $f | cut -d: -f1)"; c="$(grep -n 'SpendByDayChart(accounts: model.accounts' $f | cut -d: -f1)"
  a="$(grep -n 'AppsThisPeriod(accounts' $f | cut -d: -f1)"; t="$(grep -n 'CacheTile(accounts' $f | cut -d: -f1)"
  [[ -n "$b" && -n "$c" && -n "$a" && -n "$t" && "$b" -lt "$c" && "$c" -lt "$a" && "$a" -lt "$t" ]]
}
check "the Overview shows board, chart, apps, cache tile in 08's order" overview_order
check "the chart renders only while visible (onAppear / onDisappear)" bash -c "grep -qF '.onAppear { visible = true }' $app/Dashboard/SpendByDayChart.swift && grep -qF '.onDisappear { visible = false }' $app/Dashboard/SpendByDayChart.swift && grep -qF 'if visible { chart(data) }' $app/Dashboard/SpendByDayChart.swift"
check "O-3's palette: blue, purple, teal, orange, pink, indigo, mint, brown" grep -qF 'static let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .mint, .brown]' $app/Dashboard/SpendByDayChart.swift
check "a hover tooltip lists the day's accounts and total" bash -c "grep -qF '.onContinuousHover' $app/Dashboard/SpendByDayChart.swift && grep -qF 'tooltip(data, day: hoveredDay)' $app/Dashboard/SpendByDayChart.swift"
check "the empty state keeps 1.2's text and ids" bash -c "grep -qF 'Strings.noSpendInRange' $app/Dashboard/SpendByDayChart.swift && grep -qF 'dashboard.spendByDay.empty' $app/Dashboard/SpendByDayChart.swift"
check "08's tile sentence and OpenAI's documented reason" bash -c "grep -qF '\"Saved \\(amount) via cache (net of writes)\"' $app/Strings.swift && grep -qF 'OpenAI aggregate cache counts are unreliable' $app/Strings.swift"
check "the views compute no money (04 I3)" bash -c "! grep -nE '\\.reduce\\(|cents \\+|cents \\*' $app/Dashboard/SpendByDayChart.swift $app/Dashboard/CacheTile.swift"

for suite in CacheSavingsTests ChartDataTests CostFormulaTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "DrilldownUITests passed (the chart, its tooltip and the cache tile)" grep -q "Test Suite 'DrilldownUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
