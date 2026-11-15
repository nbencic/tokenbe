# Stage 5.5 — Menu bar glyph completion & metric (14 § Stage 5.5). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Model/GlyphState.swift $app/Components/MenuBarGlyph.swift Tests/TokenBeCoreTests/GlyphStateTests.swift
  Tests/TokenBeUITests/GlyphMetricUITests.swift scripts/stages/5.5.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: dashed > notched > solid (Core), the metric beside the glyph, at most 64 pt.
check "GlyphState lives in Core (logic extracted, 14 § 5.5)" bash -c "grep -qF 'public enum GlyphState' $core/Model/GlyphState.swift && ! grep -qF 'enum GlyphState' $app/Components/MenuBarGlyph.swift"
check "dashed first, then notched on low or critical" bash -c "grep -qF 'if offline || accounts.contains(where: \\.isStale) { return .dashed }' $core/Model/GlyphState.swift && grep -qF '\$0 == .low || \$0 == .critical } ? .notched : .solid' $core/Model/GlyphState.swift"
check "the app's glyph uses GlyphState.state" grep -qF 'GlyphState.state(accounts: accounts, offline: isOffline, persisted: persisted)' $app/AppModel.swift
check "tb.menubar.metric is consumed; text width ≤ 64 pt" bash -c "grep -qF 'MenuBarMetric(rawValue: menuBarMetric)' $app/AppModel.swift && grep -qF '.frame(maxWidth: 64)' $app/TokenBeApp.swift"
check "metric cases match 09's values" bash -c "grep -qF 'case none, minRunway, minRemaining, todaySpend' $core/Model/GlyphState.swift"

# Step 2: startup step 8 renders from band_state.
check "startup step 8 (glyph) follows the daily activity (04)" bash -c "grep -A1 'StartupStep(\"daily activity\")' $app/Startup.swift | grep -qF 'StartupStep(\"glyph\")'"
check "StartupSequenceTests lists the glyph step (D7)" grep -qF '"daily activity", "glyph"' Tests/TokenBeCoreTests/StartupSequenceTests.swift
check "step 8 reads band_state" grep -qF 'environment.initialBands = try await repository.fetchBandStates()' $app/Startup.swift

for suite in GlyphStateTests StartupSequenceTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "GlyphMetricUITests passed" grep -q "Test Suite 'GlyphMetricUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
# Q-041: this verify closes phase 5, so it runs the full UI suite, including 5.2–5.4's deferred UI tests.
ui_check "AnchorRunwayUITests passed (5.3, deferred to here by Q-041)" grep -q "Test Suite 'AnchorRunwayUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
ui_check "NotificationsSettingsUITests passed (5.4, deferred to here by Q-041)" grep -q "Test Suite 'NotificationsSettingsUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
