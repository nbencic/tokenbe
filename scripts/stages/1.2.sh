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
# A control appears only with its action (D6): Refresh arrives in 4.1, Export… in 8.3.
for later in "Refresh" "Export"; do
  check "Dashboard has no '$later' yet" bash -c "! grep -rqF '$later' Sources/TokenBeApp/Dashboard Sources/TokenBeApp/Components/RangePicker.swift"
done

for suite in DashboardRangeTests WindowFrameTests DebouncerTests SettingsSuiteResetTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "DashboardShellUITests passed" grep -q "Test Suite 'DashboardShellUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"

# 14 Verify, on the UI-test suite (Q-014): the range the test picked persisted, and the frame was saved.
suite_value() { defaults read "dev.bathyon.tokenbe.uitests" "$1" 2>/dev/null; }
range_is_30d() { [[ "$(suite_value tb.ui.dashboardRange)" == "30d" ]]; }
frame_saved() { [[ "$(suite_value tb.ui.dashboardFrame)" =~ ^\{\{-?[0-9.]+,\ -?[0-9.]+\},\ \{[0-9.]+,\ [0-9.]+\}\}$ ]]; }
check "tb.ui.dashboardRange = 30d in the UI-test suite after the test" range_is_30d
check "tb.ui.dashboardFrame saved in the UI-test suite" frame_saved
check "owner's real TokenBe settings (tb.*) unchanged after the Dashboard UI tests" real_tb_unchanged
