# Stage 1.2 — Dashboard window shell (14 § Stage 1.2). Sourced by verify-stage.sh.

inventory=(
  Sources/TokenBeApp/Dashboard/DashboardView.swift Sources/TokenBeApp/Dashboard/SidebarView.swift
  Sources/TokenBeApp/Dashboard/OverviewView.swift Sources/TokenBeApp/Components/RangePicker.swift
  Sources/TokenBeApp/Components/WindowFrameKeeper.swift Sources/TokenBeCore/Model/DashboardRange.swift
  Sources/TokenBeCore/Presentation/WindowFrame.swift Sources/TokenBeCore/Presentation/Debouncer.swift
  Tests/TokenBeCoreTests/DashboardShellTests.swift Tests/TokenBeUITests/DashboardShellUITests.swift
  Tests/TokenBeUITests/UITestSupport.swift scripts/stages/1.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

for copy in "Open dashboard" "Dashboard" "Overview" "Spend by day" "No spend in this range" "Today" "7 d" "30 d" "90 d"; do
  check "Strings has 08 copy: $copy" grep -qF "\"$copy\"" Sources/TokenBeApp/Strings.swift
done
check "Dashboard is a Window scene with id 'dashboard'" grep -qF 'static let windowID = "dashboard"' Sources/TokenBeApp/Dashboard/DashboardView.swift
check "Dashboard minimum 920×600" grep -qF "CGSize(width: 920, height: 600)" Sources/TokenBeApp/Dashboard/DashboardView.swift
check "Dashboard frame save debounced 500 ms" grep -qF ".milliseconds(500)" Sources/TokenBeApp/Components/WindowFrameKeeper.swift
check "popover footer Open dashboard is ⌘D" grep -qF '.keyboardShortcut("d")' Sources/TokenBeApp/Popover/PopoverView.swift
check "⌥-click reads NSEvent.modifierFlags (O-15)" grep -qF "NSEvent.modifierFlags.contains(.option)" Sources/TokenBeApp/Popover/PopoverView.swift
check "no right-click context menu (D-context-menu)" bash -c "! grep -rqF 'contextMenu' Sources/TokenBeApp"
check "no AppKit windows created (04)" bash -c "! grep -rqE 'NSWindow\\(|NSPanel\\(|NSWindowController' Sources/TokenBeApp"
# A control appears only with its action (D6): Export… arrives in 8.3. (`Refresh` arrived with the account page in 4.2;
# 4.2.sh checks it.)
for later in "Export"; do
  check "Dashboard has no '$later' yet" bash -c "! grep -rqF '$later' Sources/TokenBeApp/Dashboard Sources/TokenBeApp/Components/RangePicker.swift"
done

for suite in DashboardRangeTests WindowFrameTests DebouncerTests SettingsSuiteResetTests; do
  check "suite $suite passed" suite_passed "$suite"
done
ui_check "DashboardShellUITests passed" grep -q "Test Suite 'DashboardShellUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"

# 14 Verify: the range the test picked and the frame persist across a relaunch. The test asserts both itself
# ("range persists across relaunch", "frame restored from tb.ui.dashboardFrame"), so the check reads that test case's
# own result, not the shared UI-test suite, which later suites may change (PM-3.4-8).
ui_check "the Dashboard range and frame persist across a relaunch (DashboardShellUITests)" grep -q \
  "Test Case '-\[TokenBeUITests.DashboardShellUITests testCommandDOpensDashboardAndRangePersists\]' passed" \
  "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the test asserts the range and the frame after the relaunch" bash -c "grep -qF 'range persists across relaunch' Tests/TokenBeUITests/DashboardShellUITests.swift && grep -qF 'frame restored from tb.ui.dashboardFrame' Tests/TokenBeUITests/DashboardShellUITests.swift"
check "owner's real TokenBe settings (tb.*) unchanged after the Dashboard UI tests" real_tb_unchanged
