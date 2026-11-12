# Stage 4.2 — Freshness, stale, offline; account page shell (14 § Stage 4.2). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Ledger/Freshness.swift $app/Dashboard/AccountDetailView.swift $app/Dashboard/BadgesRow.swift
  $app/Dashboard/SourcesStrip.swift $app/Components/BandDot.swift Tests/TokenBeCoreTests/FreshnessTests.swift
  Tests/TokenBeUITests/StaleOfflineUITests.swift scripts/stages/4.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 08's copy, verbatim in Strings.swift (R9, D8).
for copy in 'Offline \u{2014} showing last known values' 'Key missing' 'Balance: \(word)' 'Usage: \(word)' \
            'Cost: \(word)' 'Lag: \(interval)' 'Usage' 'Cost' 'Balance' 'ok' 'failed' 'n/a' 'next \(interval)' 'Refresh'; do
  check "Strings has copy: $copy" grep -qF "\"$copy\"" $app/Strings.swift
done
check "badge words are 08's" bash -c "grep -qF 'case perKey = \"per key\"' $core/Providers/Capabilities.swift && grep -qF 'case orgOnly = \"org only\"' $core/Providers/Capabilities.swift && grep -qF 'case direct, anchored, none' $core/Providers/Capabilities.swift && grep -qF 'case provider, estimated' $core/Providers/Capabilities.swift"
check "no inline Text copy in views (D8)" bash -c "! grep -rnE 'Text\\(\"[A-Za-z]' $app --include=*.swift | grep -v Strings.swift"

# Step 1: Freshness in Core (05: stale past multiplier × interval; primary job per mode; the scheduler's interval).
check "primary job: balance for direct, usage otherwise" grep -qF 'mode == .direct ? .balance : .usage' $core/Ledger/Freshness.swift
check "stale is strictly past the threshold (05)" grep -qF 'summaries[index].isStale = staleAt.map { now > $0 } ?? false' $core/Ledger/Freshness.swift
check "the threshold uses the scheduler's interval (override, Low Power)" grep -qF 'job.interval(for: summary.provider, settings: context.settings, override: summary.intervalOverride' $core/Ledger/Freshness.swift
check "AppModel reads tb.alerts.staleMultiplier (D4, 09)" grep -qF 'staleMultiplier: settings.alertsStaleMultiplier' $app/AppModel.swift
check "stale is re-evaluated on time, without a Timer (R6)" bash -c "grep -qF 'try await ContinuousClock().sleep(for: .seconds(delay))' $app/AppModel.swift && ! grep -nE 'Timer(\\.|\\()' $app/AppModel.swift"
check "Low Power and next runs come from CoordinatorState" bash -c "grep -qF 'public var isLowPower: Bool' $core/Scheduling/PollCoordinator+Inputs.swift && grep -qF 'public var nextDue: [String: [Job: Date]]' $core/Scheduling/PollCoordinator+Inputs.swift"
check "summaries carry each job's last error, never last_raw (PM-2.2-3)" bash -c "grep -A1 'SELECT account_id, job' $core/Store/Observation.swift | grep -qF 'last_error_class, last_error_message' && ! grep -A1 'SELECT account_id, job' $core/Store/Observation.swift | grep -qF 'last_raw'"
check "poll_state stores the human message (Q-036)" grep -qF 'message: error.humanMessage(provider:' $core/Scheduling/Poller.swift
check "poll.failed keeps the raw cause in ctx.detail (07)" bash -c "grep -qF '\"detail\": .string(error.summary)' $core/Scheduling/Poller.swift && grep -qF 'attempts, err, detail' docs/07-logging.md"

# Step 2: the account page: header, badges with help, sources strip; Refresh; no 5.3 controls yet (D6).
check "sidebar account rows open the account page" grep -qF '.tag(Item.account(account.id))' $app/Dashboard/SidebarView.swift
check "the Dashboard shows the selected account's page" grep -qF 'AccountDetailView(model: model, summary: account)' $app/Dashboard/DashboardView.swift
check "header Refresh runs that account's jobs" grep -qF 'model.refreshNow(summary.id)' $app/Dashboard/AccountDetailView.swift
check "toolbar Refresh (08)" grep -qF 'dashboard.toolbar.refresh' $app/Dashboard/DashboardView.swift
check "each badge has a help popover" grep -qF '.popover(isPresented: $showsHelp' $app/Dashboard/BadgesRow.swift
check "a failed source shows its message in HealthLow" bash -c "grep -qF 'source.state == .failed ? Color(.healthLow)' $app/Dashboard/SourcesStrip.swift"
for later in "Set anchor" "Add top-up" "Export"; do
  check "Dashboard has no '$later' yet (5.3, 8.3)" bash -c "! grep -rqF '$later' $app/Dashboard"
done

# Step 3: popover stale overlay, Offline banner, dashed glyph.
check "glyph dashed when any account is stale or offline (08)" grep -qF 'isOffline || accounts.contains(where: \.isStale) ? .dashed : .solid' $app/AppModel.swift
check "glyph state is exposed as glyph.<state>" grep -qF '.accessibilityIdentifier("glyph.\(state.rawValue)")' $app/Components/MenuBarGlyph.swift
check "Offline banner while offline" bash -c "grep -qF 'if model.isOffline { offlineBanner }' $app/Popover/PopoverView.swift"
check "offline puts every card under the overlay" grep -qF 'dimmed: summary.isStale || model.isOffline' $app/Popover/PopoverView.swift
check "overlay: opacity 0.6, freshness HealthLow and stale text (08)" bash -c "grep -qF '.opacity(dimmed ? 0.6 : 1)' $app/Popover/AccountCardView.swift && grep -qF 'stale: dimmed' $app/Popover/AccountCardView.swift"
check "a card opens its account page (08)" grep -qF 'model.showAccount(summary.id)' $app/Popover/PopoverView.swift

# Step 4: sidebar rows reflect needsKey.
check "sidebar rows read Key missing" bash -c "grep -B1 -A2 'if account.needsKey' $app/Dashboard/SidebarView.swift | grep -qF 'Strings.keyMissing'"

# The offline seam is DEBUG and test-root only (Q-036).
check "FixedNetworkMonitor is DEBUG only" bash -c "grep -B3 'public struct FixedNetworkMonitor' $core/Network/NetworkMonitor.swift | grep -qF '#if DEBUG'"
check "TOKENBE_TEST_OFFLINE needs a test root" grep -qF 'paths.testRoot != nil, ProcessInfo.processInfo.environment[Self.testOfflineVariable] == "1"' $app/Startup.swift

for suite in FreshnessTests CoordinatorTests ObservationTests AccountSummaryBuilderTests PollerTests FormattersTests; do
  check "suite $suite passed" suite_passed "$suite"
done
# 14 Verify: E2E-5 (11) is the UI test: usage failing → past the threshold the card dims and the glyph is dashed;
# offline → banner; ok again → normal on the first poll.
ui_check "StaleOfflineUITests passed (E2E-5)" grep -q "Test Suite 'StaleOfflineUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
