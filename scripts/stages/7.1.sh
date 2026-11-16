# Stage 7.1 — Apps bound to provider keys (14 § Stage 7.1). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Store/Repository+Apps.swift $core/Ledger/Attribution.swift
  $app/Dashboard/ByAppTable.swift $app/Dashboard/AppsThisPeriod.swift $app/Dashboard/AppsPage.swift
  $app/SettingsUI/BoundAppPicker.swift
  Tests/TokenBeCoreTests/AttributionTests.swift Tests/TokenBeUITests/AppsBindingUITests.swift
  scripts/ui-select.sh scripts/stages/7.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Q-047: every UI suite declares the paths it covers, and every declared path exists.
suites_declare_paths() {
  local file prefix missing=0
  for file in Tests/TokenBeUITests/*.swift; do
    [[ "$(basename "$file")" == UITestSupport.swift ]] && continue
    grep -q '^// ui-covers:' "$file" || { echo "$file declares no // ui-covers: paths"; missing=1; }
    for prefix in $(sed -n 's|^// ui-covers:||p' "$file"); do
      [[ "$prefix" == always ]] && continue
      compgen -G "$prefix*" >/dev/null || { echo "$file: no path starts with $prefix"; missing=1; }
    done
  done
  return "$missing"
}
check "every UI suite declares the paths it covers, and they exist (Q-047)" suites_declare_paths
check "the smoke suites always run (Q-047)" bash -c "for s in LaunchSmokeTests PopoverEmptyStateUITests; do grep -qx '// ui-covers: always' Tests/TokenBeUITests/\$s.swift || exit 1; done"
check "run.sh passes the selected suites to xcodebuild (Q-047)" grep -qF 'cmd+=("-only-testing:TokenBeUITests/$suite")' scripts/run.sh
check "ui-select.sh selects a suite through its covered path" bash -c "scripts/ui-select.sh --explain 2>&1 >/dev/null | grep -qE '^(LaunchSmokeTests: always|ALL: shared file)'"

# Step 1: Repository+Apps per 14 § 2.1 step 5 (upsertApp, fetchApps, bind, unbind, fetchBindings); Attribution's key
# path: per key, cost rows where available, else the estimate; Σ rows == provider total, remainder to the largest.
check "Repository has the apps aggregate (14 § 2.1 step 5)" bash -c "grep -qF '& AppRepository' $core/Store/Repository.swift && for m in 'func upsertApp(displayName' 'func upsertApp(id' 'func fetchApps' 'func bind(appID' 'func unbind(key' 'func fetchBindings'; do grep -qF \"\$m\" $core/Store/Repository+Apps.swift || exit 1; done"
check "a new app and its binding are one transaction (R7)" bash -c "grep -A10 'public func upsertApp(displayName' $core/Store/Repository+Apps.swift | grep -qF 'if let binding { try Self.bind(db'"
check "the app name is immutable (O-13): no UPDATE of app.name" bash -c "! grep -nE 'UPDATE app SET[^\"]*\\bname\\b' $core/Store/*.swift"
check "attribution reads per-key cost rows (group_kind = 'api_key_id')" grep -qF "group_kind = 'api_key_id'" $core/Store/Observation.swift
check "attribution uses Spend.daily's day rule (Σ rows == provider total)" grep -qF 'Spend.daily(account, today: today, inputs: inputs)' $core/Ledger/Attribution.swift
check "AccountSummary carries the By-app rows" bash -c "grep -qF 'public var byApp: [AppRow]' $core/Model/AccountSummary.swift && grep -qF 'Attribution.rows(summary' $core/Ledger/AccountSummaryBuilder.swift"

# Step 2: the UI.
check "the By-app Total comes from Core, not the view (04 I3)" bash -c "grep -qF 'summary.byAppTotal = Attribution.total(summary.byApp)' $core/Ledger/AccountSummaryBuilder.swift && ! grep -qE 'byApp\.reduce' $app/Dashboard/ByAppTable.swift"
check "the account page shows the By-app table" grep -qF 'ByAppTable(model: model, summary: summary' $app/Dashboard/AccountDetailView.swift
check "the Overview shows Apps this period" grep -qF 'AppsThisPeriod(accounts: model.accounts' $app/Dashboard/OverviewView.swift
check "the sidebar ends with Apps, which opens the Apps page" bash -c "grep -qF 'case apps' $app/Dashboard/SidebarView.swift && grep -qF 'AppsPage(model: model)' $app/Dashboard/DashboardView.swift"
check "Keys & apps has the Bound app picker with New app… (08)" bash -c "grep -qF 'BoundAppPicker(model: model' $app/SettingsUI/AccountsTab.swift && grep -qF 'Strings.newApp' $app/SettingsUI/BoundAppPicker.swift"
check "popover row 4 reads and writes tb.popover.expanded.<provider> (09)" bash -c "grep -qF 'isPopoverExpanded(summary.provider)' $app/Popover/AccountCardView.swift && grep -qF 'setPopoverExpanded(summary.provider' $app/Popover/AccountCardView.swift"
check "08's copy: By app, Apps this period, Name…, New app…, (unnamed key …)" bash -c "grep -qF 'static let byApp = \"By app\"' $app/Strings.swift && grep -qF 'static let appsThisPeriod = \"Apps this period\"' $app/Strings.swift && grep -qF 'static let nameKey = \"Name\\u{2026}\"' $app/Strings.swift && grep -qF 'static let newApp = \"New app\\u{2026}\"' $app/Strings.swift && grep -qF '\"(unnamed key \\(hint))\"' $app/Strings.swift"
check "app writes log ui.error on failure (R5)" bash -c "grep -A8 'private func appsWrite' $app/AppModel.swift | grep -qF 'Log.error(.uiError'"
# 7.3 adds the row click → app filter; until then the Overview rows are not buttons (D6).
check "Apps this period rows are not buttons yet (7.3, D6)" bash -c "! grep -qE 'Button|onTapGesture' $app/Dashboard/AppsThisPeriod.swift"
# 7.2 added split, harness and inferred (7.2.sh checks them); the key kind stays first.
check "the key badge exists (08)" bash -c "grep -A3 'public enum AttributionKind' $core/Ledger/Attribution.swift | grep -qE 'case key'"

for suite in AttributionTests ObservationTests SpendTests RepositoryAccountTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "AppsBindingUITests passed (bind key → By-app row renamed; Total equals provider total)" grep -q "Test Suite 'AppsBindingUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
