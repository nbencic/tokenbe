# Stage 8.1 — By-model table & drift (14 § Stage 8.1). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Ledger/Drift.swift $app/Dashboard/ByModelTable.swift
  Tests/TokenBeCoreTests/DriftTests.swift Tests/TokenBeUITests/ByModelUITests.swift
  Tests/Fixtures/providers/openai/usage_completions.unpriced.synthetic.json
  scripts/stages/8.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 05 § Drift in Core (04 I3): the rows, the line-item mapping, closed days, the threshold, unpriced never $0 (A6).
check "Core builds the By-model rows with the drift threshold" bash -c "grep -qF 'public static func rows' $core/Ledger/Drift.swift && grep -qF 'summary.byModel = Drift.rows(summary' $core/Ledger/AccountSummaryBuilder.swift && grep -qF 'thresholdPct: context.driftThresholdPct)' $core/Ledger/AccountSummaryBuilder.swift"
check "a line item maps to a usage model by its exact name (05, Q-051)" grep -qF 'public static func lineItemModel' $core/Ledger/Drift.swift
check "the inputs carry per-model usage and line-item cost (Observation)" bash -c "grep -qF 'modelUsageDays = try ModelUsageDay.fetch(db' $core/Store/Observation.swift && grep -qF 'lineItemCostDays = try LineItemCostDay.fetch(db' $core/Store/Observation.swift && grep -qF \"group_kind = 'line_item'\" $core/Ledger/Drift.swift"
check "priced and unpriced estimates are summed apart (A6: never \$0)" grep -qF 'SUM(CASE WHEN unpriced = 0 THEN COALESCE(est_cost_cents, 0) ELSE 0 END)' $core/Ledger/Drift.swift
check "the flag compares integers (|est − provider| × 100 > pct × provider)" grep -qF 'magnitude * 100 > Int128(thresholdPct) * truth' $core/Ledger/Drift.swift

# ledger.drift (07): a daily step after the harness drift, once per account, model and day; never from the builder.
check "the daily activity runs the model drift step (04)" bash -c "grep -qF 'DailyStep(\"model drift\")' $app/DailyActivityRegistration.swift && grep -qF 'Drift.report(current' $app/DailyActivityRegistration.swift && grep -qF 'model drift (yesterday' docs/04-architecture.md"
drift_order() {
  local f=$app/DailyActivityRegistration.swift h m p
  h="$(grep -n 'DailyStep("harness drift")' $f | cut -d: -f1)"; m="$(grep -n 'DailyStep("model drift")' $f | cut -d: -f1)"
  p="$(grep -n 'DailyStep("price refresh")' $f | cut -d: -f1)"
  [[ -n "$h" && -n "$m" && -n "$p" && "$h" -lt "$m" && "$m" -lt "$p" ]]
}
check "model drift runs after harness drift, before the price refresh (04)" drift_order
check "ledger.drift is logged at warn with model and drift_pct" bash -c "grep -qF '.warn, .ledgerDrift, cat: .ledger' $core/Ledger/Drift.swift && grep -qF '\"drift_pct\"' $core/Ledger/Drift.swift"
check "the summary builder never logs" bash -c "! grep -nE 'Log\\.(info|warn|error|debug)|\\.emit\\(' $core/Ledger/AccountSummaryBuilder.swift"

# The table (08 § Account detail 5): 08's columns, the unpriced flag, — without a cost row, the flag in words.
check "the account page shows the By-model table" grep -qF 'ByModelTable(rows: summary.byModel' $app/Dashboard/AccountDetailView.swift
check "08's ten columns, in order" bash -c "grep -qF 'static let byModel = \"By model\"' $app/Strings.swift && grep -qF 'static let columnEstCost = \"Est. cost\"' $app/Strings.swift && grep -qF 'static let columnProviderCost = \"Provider cost\"' $app/Strings.swift && grep -qF 'Strings.columnEstCost, Strings.columnProviderCost,' $app/Dashboard/ByModelTable.swift"
check "a flagged drift cell says so to VoiceOver, not only in colour (08 § Accessibility)" bash -c "grep -qF 'Strings.driftLabel(percent, flagged: drift.flagged' $app/Dashboard/ByModelTable.swift && grep -qF 'Color(.healthWatch)' $app/Dashboard/ByModelTable.swift"
check "the Sources strip is not lazy, so its chips exist below the By-model table (PM-7.2-6)" bash -c "grep -qF 'AdaptiveColumns(minimum: 200, spacing: 28, rowSpacing: 12)' $app/Dashboard/SourcesStrip.swift && ! grep -qF 'LazyVGrid' $app/Dashboard/SourcesStrip.swift"
check "the table computes no money (04 I3)" bash -c "! grep -nE '\\.reduce\\(|estCents \\+|providerCents \\+' $app/Dashboard/ByModelTable.swift"

for suite in DriftTests FormattersTests ObservationTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "ByModelUITests passed (E2E-8: unpriced flagged, drift flagged)" grep -q "Test Suite 'ByModelUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
