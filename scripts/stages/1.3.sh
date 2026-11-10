# Stage 1.3 — Settings window: General, Privacy (static), Advanced (logging) (14 § Stage 1.3). Sourced by verify-stage.sh.

inventory=(
  Sources/TokenBeApp/SettingsUI/SettingsView.swift Sources/TokenBeApp/SettingsUI/GeneralTab.swift
  Sources/TokenBeApp/SettingsUI/PrivacyTab.swift Sources/TokenBeApp/SettingsUI/AdvancedTab.swift
  Sources/TokenBeApp/HotKey/HotKeyCenter.swift Sources/TokenBeApp/Components/HotKeyRecorder.swift
  Sources/TokenBeApp/LoginItems.swift Sources/TokenBeCore/Presentation/Shortcut.swift
  Sources/TokenBeCore/Presentation/AccountOrder.swift Sources/TokenBeCore/Settings/LoginItem.swift
  Tests/TokenBeCoreTests/SettingsWindowTests.swift Tests/TokenBeUITests/SettingsGeneralUITests.swift
  scripts/stages/1.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

for copy in "Launch at login" "Hide cents" "Appearance" "Global shortcut" "Currency display" \
            "Conversion is not in v1" "Open log folder" "Log level" "Log retention"; do
  check "Strings has copy: $copy" grep -qF "\"$copy\"" Sources/TokenBeApp/Strings.swift
done
check "Strings has Settings… (08 § Popover 4)" grep -qF 'settingsEllipsis = "Settings\u{2026}"' Sources/TokenBeApp/Strings.swift
check "popover footer Settings… is ⌘," grep -qF '.keyboardShortcut(",")' Sources/TokenBeApp/Popover/PopoverView.swift
check "Settings is a SwiftUI Settings scene" grep -qE '^    Settings \{' Sources/TokenBeApp/TokenBeApp.swift
check "MenuBarExtra(.window) kept (04, 08; Q-023)" grep -qF '.menuBarExtraStyle(.window)' Sources/TokenBeApp/TokenBeApp.swift
check "no NSStatusItem (08)" bash -c "! grep -rqE 'NSStatusItem|NSStatusBar\\.system|NSPopover' Sources/TokenBeApp"
check "global shortcut uses Carbon RegisterEventHotKey (D-hotkey-carbon)" grep -qF "RegisterEventHotKey(" Sources/TokenBeApp/HotKey/HotKeyCenter.swift
check "no global event monitor (09)" bash -c "! grep -rqF 'addGlobalMonitorForEvents' Sources"
check "launch at login via SMAppService.mainApp" grep -qF "SMAppService.mainApp.register()" Sources/TokenBeApp/LoginItems.swift
check "ui.hotkey_failed emitted" grep -qF "uiHotkeyFailed" Sources/TokenBeApp/HotKey/HotKeyCenter.swift
check "app.login_item_failed emitted" grep -qF "appLoginItemFailed" Sources/TokenBeCore/Settings/LoginItem.swift
check "check-log-events.sh (14 Verify)" scripts/check-log-events.sh

# A control appears only with its action (D6): later tabs and rows arrive with their stages.
for later in "Accounts" "Sources" "Alerts"; do
  check "SettingsView has no '$later' tab yet" bash -c "! grep -qF 'tab$later' Sources/TokenBeApp/SettingsUI/SettingsView.swift"
done
for later in "Export" "integrity" "Back up" "Reset all" "Import" "Last daily run" "Check for updates"; do
  check "Settings tabs have no '$later' yet" bash -c "! grep -rqF '$later' Sources/TokenBeApp/SettingsUI"
done

for suite in ShortcutTests LoginItemControllerTests AccountOrderTests SettingSpecBoundsTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "SettingsGeneralUITests passed" grep -q "Test Suite 'SettingsGeneralUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"

# 14 Verify, on the UI-test suite (Q-014): each value the test set last.
suite_is() { [[ "$(defaults read "dev.bathyon.tokenbe.uitests" "$1" 2>/dev/null)" == "$2" ]] || { echo "$1 is '$(defaults read "dev.bathyon.tokenbe.uitests" "$1" 2>&1)', want '$2'"; return 1; }; }
for pair in tb.general.launchAtLogin=1 tb.menubar.metric=todaySpend tb.popover.pinnedMetric=remaining \
            tb.popover.sort=name tb.ui.hideCents=0 tb.ui.useSystemAccent=0 tb.ui.appearance=dark \
            tb.ui.shortcut=ctrl+alt+t tb.log.level=info; do
  check "UI-test suite: ${pair%%=*} = ${pair#*=}" suite_is "${pair%%=*}" "${pair#*=}"
done
check "owner's real TokenBe settings (tb.*) unchanged after the Settings UI tests" real_tb_unchanged
