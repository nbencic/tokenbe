# Stage 1.1 — Composition root, AppModel, popover empty state, glyph states (14 § Stage 1.1). Sourced by verify-stage.sh.

inventory=(
  Sources/TokenBeApp/AppEnvironment.swift Sources/TokenBeApp/AppModel.swift Sources/TokenBeApp/Strings.swift
  Sources/TokenBeApp/Popover/PopoverView.swift Sources/TokenBeApp/Popover/EmptyStateView.swift
  Sources/TokenBeApp/Popover/AccountCardView.swift Sources/TokenBeApp/Components/MenuBarGlyph.swift
  Sources/TokenBeCore/Model/AccountSummary.swift Sources/TokenBeCore/Model/Formatters.swift
  Sources/TokenBeCore/Model/Band.swift Sources/TokenBeCore/Model/Money.swift
  Sources/TokenBeCore/Presentation/PopoverTracker.swift Tests/TokenBeCoreTests/FormattersTests.swift
  Tests/TokenBeUITests/PopoverEmptyStateUITests.swift scripts/stages/1.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

identifiers() { [[ "$(grep -h "accessibilityIdentifier" Sources/TokenBeApp/Popover/*.swift | wc -l | tr -d ' ')" -ge 6 ]]; }
check "≥ 6 accessibility identifiers in Popover/ (summed)" identifiers
for copy in "No accounts yet" "Add a provider key to start tracking." "No data yet" "Quit"; do
  check "Strings has 08 copy: $copy" grep -qF "\"$copy\"" Sources/TokenBeApp/Strings.swift
done
# A control appears only with its action (D6): no later-stage controls in the popover yet.
for later in "Add account" "Open dashboard" "Settings…" "Pause polling" "arrow.clockwise"; do
  check "popover has no '$later' yet" bash -c "! grep -rqF '$later' Sources/TokenBeApp/Popover Sources/TokenBeApp/Strings.swift"
done
for shape in "case solid" "case notched" "case dashed"; do
  check "glyph shape: $shape" grep -qF "$shape" Sources/TokenBeApp/Components/MenuBarGlyph.swift
done
check "PopoverTracker emits ui.popover_open" grep -q "uiPopoverOpen" Sources/TokenBeCore/Presentation/PopoverTracker.swift
check "PopoverTracker emits ui.popover_close" grep -q "uiPopoverClose" Sources/TokenBeCore/Presentation/PopoverTracker.swift

latest_test_log() { ls -t build/logs/test-*.log | head -n 1; }
for suite in FormattersTests PopoverTrackerTests; do
  check "suite $suite passed" grep -q "Suite $suite passed" "$(latest_test_log)"
done
# 0.4's check runs the whole UI-test bundle; this asserts the 1.1 test was part of it and passed.
check "PopoverEmptyStateUITests passed" grep -q "Test Suite 'PopoverEmptyStateUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
