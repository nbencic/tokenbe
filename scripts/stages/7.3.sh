# Stage 7.3 — Drilldown polish (14 § Stage 7.3). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
dash=$app/Dashboard
inventory=(
  $dash/AccountDetailView.swift $dash/ByAppTable.swift $dash/DriftChip.swift $dash/AppsThisPeriod.swift
  $dash/DashboardView.swift $core/Ledger/Attribution.swift $core/Ledger/Attribution+Harness.swift
  Tests/TokenBeCoreTests/AttributionDrilldownTests.swift Tests/TokenBeUITests/DrilldownUITests.swift
  scripts/stages/7.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Overview app row → account page filtered by app (filter chip with ✕); Core picks the account (04 I3; Q-050).
check "Apps this period rows are buttons that open the app (08 Overview 4)" bash -c "grep -qF 'Button { open(total) }' $dash/AppsThisPeriod.swift && grep -qF 'dashboard.overview.apps.row.\\(total.row.elementID)' $dash/AppsThisPeriod.swift"
check "Core picks the account a row opens" bash -c "grep -qF 'public static func drilldownAccount' $core/Ledger/Attribution.swift && grep -qF 'Attribution.drilldownAccount(total, accounts: model.accounts)' $dash/DashboardView.swift"
check "Core filters the By-app rows and totals them" bash -c "grep -qF 'public static func filtered' $core/Ledger/Attribution.swift && grep -qF 'Attribution.filtered(summary.byApp' $dash/ByAppTable.swift && ! grep -qE 'byApp\\.(reduce|filter)' $dash/ByAppTable.swift"
check "the filter chip has its ✕ (Clear app filter)" bash -c "grep -qF 'dashboard.account.byApp.filter.clear' $dash/ByAppTable.swift && grep -qF 'static let clearAppFilter = \"Clear app filter\"' $app/Strings.swift"
check "leaving the account clears the filter; it is never persisted" bash -c "grep -qF 'onChange(of: model.dashboardSelection)' $dash/DashboardView.swift && grep -qF '@State private var appFilter: AppFilter?' $dash/DashboardView.swift"
check "a filtered table's footer reads App total (Q-050)" grep -qF 'filter == nil ? Strings.total : Strings.appTotal' $dash/ByAppTable.swift

# Drift chip (06 precedence 2): Core computes the days with the Alerts threshold; the page shows the newest.
check "the summary carries the drift days (Core, 04 I3)" bash -c "grep -qF 'public var harnessDrift: [HarnessDrift]' $core/Model/AccountSummary.swift && grep -qF 'Attribution.harnessDrifts(summary' $core/Ledger/AccountSummaryBuilder.swift"
check "the drift threshold comes from tb.alerts.driftThresholdPct and rebuilds on change" bash -c "grep -qF 'driftThresholdPct: settings?.alertsDriftThresholdPct' $app/AppModel.swift && grep -qF '.alertsDriftThresholdPct])' $app/AppModel.swift"
check "the header shows the drift chip" grep -qF 'DriftChip(drift: summary.harnessDrift' $dash/AccountDetailView.swift
check "the daily step and the chip share one rule" grep -qF 'harnessDrifts(account, days: [day], today: nil' $core/Ledger/Attribution+Harness.swift
check "no new log event (14 § 7.3: Events none new)" bash -c "! grep -nE 'Log\\.(info|warn|error|debug)|\\.emit\\(' $dash/DriftChip.swift $dash/AppsThisPeriod.swift"

# The unassigned sentinel is the Unassigned row everywhere, with one element id.
check "the sentinel's rows have the element id unassigned" grep -qF 'appID == Attribution.unassignedID ? "unassigned"' $core/Ledger/Attribution.swift

for suite in AttributionTests FormattersTests ObservationTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "DrilldownUITests passed (row → filtered account, chip ✕, drift chip)" grep -q "Test Suite 'DrilldownUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
