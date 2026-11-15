# Stage 5.4 — Notifications (14 § Stage 5.4). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Notifications/Notifier.swift $core/Ledger/AlertPolicy.swift $app/Notifications/Notifier.swift
  $app/Notifications/UNNotifier.swift Tests/TokenBeCoreTests/Support/RecordingNotifier.swift
  Tests/TokenBeCoreTests/AlertPolicyTests.swift Tests/TokenBeUITests/NotificationsSettingsUITests.swift
  scripts/stages/5.4.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: the seam (14 § 0.3), category band with open/snooze, authorization at the first alert (not at launch).
check "Notifier: authorize and deliver" bash -c "grep -qF 'func authorize() async -> Bool' $core/Notifications/Notifier.swift && grep -qF 'func deliver(_ notice: AlertNotice) async throws' $core/Notifications/Notifier.swift"
check "UNNotifier: category band, actions open and snooze" bash -c "grep -qF 'category = \"band\"' $app/Notifications/UNNotifier.swift && grep -qF 'openAction = \"open\"' $app/Notifications/UNNotifier.swift && grep -qF 'snoozeAction = \"snooze\"' $app/Notifications/UNNotifier.swift"
check "authorization is requested only from AlertCenter's first send, not at launch" bash -c "! grep -rqF 'requestAuthorization' $app --include=*.swift --exclude=UNNotifier.swift && grep -qF 'authorized = await notifier.authorize()' $core/Ledger/AlertPolicy.swift"
check "Snooze 24 h writes tb.alerts.snoozedUntil.<p>" grep -qF 'settings.setSnoozedUntil(provider, Date().addingTimeInterval(AlertPolicy.snooze)' $app/AppDelegate.swift
check "UI tests never reach macOS notifications (FileNotifier under a test root, DEBUG only)" bash -c "grep -B4 'struct FileNotifier' $app/Notifications/UNNotifier.swift | grep -qF '#if DEBUG'"

# Step 2: the policy.
check "transitions into low/critical; unknown > 24 h; stale > 6 h; 24 h dedupe" bash -c "grep -qF 'unknownAfter: TimeInterval = 24 * 3600' $core/Ledger/AlertPolicy.swift && grep -qF 'staleAfter: TimeInterval = 6 * 3600' $core/Ledger/AlertPolicy.swift && grep -qF 'dedupeWindow: TimeInterval = 24 * 3600' $core/Ledger/AlertPolicy.swift"
check "quiet hours wrap past midnight" grep -qF 'return minute >= settings.quietStart || minute < settings.quietEnd' $core/Ledger/AlertPolicy.swift
for evt in uiNotificationSent uiNotificationDenied; do
  check "event .$evt emitted" grep -qF ".$evt," $core/Ledger/AlertPolicy.swift
done
check "the app runs the policy after each band evaluation" grep -qF 'await alerts.process(evaluated, transitions: transitions' $app/AppModel.swift

# Step 3: Alerts tab controls (D4) and O-11's banner.
for key in alertsNotifyLow alertsNotifyCritical alertsNotifyUnknown alertsNotifyStale alertsQuietHoursEnabled \
           alertsQuietStart alertsQuietEnd; do
  check "Alerts tab controls $key" grep -qF "\$settings.$key" $app/SettingsUI/AlertsTab.swift
done
check "AlertSettings reads every notification key and snoozedUntil" bash -c "for k in alertsNotifyLow alertsNotifyCritical alertsNotifyUnknown alertsNotifyStale alertsQuietHoursEnabled alertsQuietStart alertsQuietEnd; do grep -qF \"settings.\$k\" $core/Ledger/AlertPolicy.swift || exit 1; done; grep -qF 'settings.snoozedUntil(provider)' $core/Ledger/AlertPolicy.swift"
for copy in 'Send test notification' 'Notifications are off in System Settings' 'Open System Settings' 'Quiet hours'; do
  check "Strings has copy: $copy" grep -qF "\"$copy\"" $app/Strings.swift
done
check "08's Open and Snooze 24 h" bash -c "grep -qF 'open = \"Open\"' $core/Core/CoreStrings.swift && grep -qF 'snooze = \"Snooze 24 h\"' $core/Core/CoreStrings.swift"
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh

for suite in AlertPolicyTests BandTransitionTests; do
  check "suite $suite passed" suite_passed "$suite"
done
# 14 Verify: E2E-4 — a fixture driven to critical gives exactly one notification in a Core test.
check "E2E-4 is a Core test with RecordingNotifier" grep -qF 'E2E-4: a fixture driven to critical gives exactly one notification' Tests/TokenBeCoreTests/AlertPolicyTests.swift
check "the app and UI tests compile (build-for-testing, Q-041)" scripts/run.sh build-uitest
ui_check "NotificationsSettingsUITests passed" grep -q "Test Suite 'NotificationsSettingsUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
