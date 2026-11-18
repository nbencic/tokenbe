# Stage 9.5 — Reset, cleanups, environment audits (14 § Stage 9.5; 09 § Reset semantics; O-14; 04 § Startup
# sequence). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $app/SettingsUI/ResetSettingsButton.swift Tests/TokenBeUITests/SettingsRoundTripUITests.swift scripts/stages/9.5.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Reset all settings… (09): a destructive confirm, then Settings.resetAll, last in Advanced (08).
check "Strings has 08's Reset all settings…" grep -qF 'resetAllSettings = "Reset all settings\u{2026}"' $app/Strings.swift
check "a destructive confirm runs Settings.resetAll" bash -c "grep -qF '.confirmationDialog(Strings.resetAllTitle, isPresented: \$confirming)' $app/SettingsUI/ResetSettingsButton.swift && grep -qF 'Button(Strings.resetConfirm, role: .destructive) { settings.resetAll() }' $app/SettingsUI/ResetSettingsButton.swift"
reset_last() {
  local f=$app/SettingsUI/AdvancedTab.swift d r
  d="$(grep -n 'DataTransferRows(repository: repository)' $f | cut -d: -f1)"; r="$(grep -n 'ResetSettingsButton(settings: settings)' $f | cut -d: -f1)"
  [[ -n "$d" && -n "$r" && "$d" -lt "$r" ]]
}
check "Reset all settings… is Advanced's last row (08)" reset_last
check "resetAll keeps tb.ui.onboardingDone and logs app.settings_reset (09)" bash -c "grep -qF 'let keep = SettingsKey.uiOnboardingDone.rawValue' $core/Settings/Settings.swift && grep -qF 'emit(.appSettingsReset, msg: \"settings reset\", ctx: [\"keys_removed\": .int(removed.count)])' $core/Settings/Settings.swift"
check "resetAll republishes every key to its live consumers" grep -qF 'for key in SettingsKey.allCases { publish(key) }' $core/Settings/Settings.swift

# O-14: a time-zone change, and wake, reach the scheduler; local-time days follow the zone.
check "NSSystemTimeZoneDidChange resets Foundation's zone and logs sched.clock_jump tz=true" bash -c "grep -A3 'notifications(named: .NSSystemTimeZoneDidChange)' $app/Startup.swift | grep -qF 'NSTimeZone.resetSystemTimeZone()' && grep -qF 'clockJumped(wall: now(), mono: clock.now, reason: \"timezone\")' $core/Scheduling/PollCoordinator+Inputs.swift && grep -qF '\"tz\": .bool(reason == \"timezone\" ||' $core/Scheduling/PollCoordinator.swift"
check "the log turns over at local midnight in the current zone" grep -qF 'calendar: Calendar = .autoupdatingCurrent,' $core/Logging/NDJSONSink.swift
check "sleep/wake reaches the scheduler (04)" grep -qF 'await coordinator.systemDidWake()' $app/Startup.swift
check "07 lists clock_jump's timezone reason" grep -qF "reason (\`drift\`,\`wake\`,\`timezone\`" docs/07-logging.md

# PM-0.2-3: every event is produced in a test (four exempt by design, Q-059); PM-7.3-5: the test-root key note.
check "check-log-events.sh --from-tests" scripts/check-log-events.sh --from-tests
check "a DEBUG test-root launch says the key is stored in plain text (PM-7.3-5)" bash -c "grep -qF 'Text(Strings.testRootKeyNote(plainText.path))' $app/Onboarding/Step2Key.swift && grep -A3 'static var testRootKeyFile' $app/Onboarding/Step2Key.swift | grep -qF '#if DEBUG'"
check "1.3.sh guards no Settings control any more (PM-8.3-1)" bash -c "! grep -qE '^for later in ' scripts/stages/1.3.sh"

# 04 § Startup sequence, audited: StartupSequenceTests holds all 8 steps; the app declares and logs them in order.
check "StartupSequenceTests asserts all 8 steps of 04" grep -qF 'static let implementedSteps = ["logging", "database", "accounts", "prices", "ingest", "scheduler", "daily activity", "glyph"]' Tests/TokenBeCoreTests/StartupSequenceTests.swift
declared() { grep -oE 'StartupStep\("[a-z ]+"\)' $app/Startup.swift | cut -d'"' -f2 | paste -sd, -; }
# 04's 8 steps in order; `login item` (1.3, Q-023) sits between ingest and the scheduler.
want="logging,database,accounts,prices,ingest,login item,scheduler,daily activity,glyph"
check "Startup declares 04's steps in order" bash -c "[[ \"\$(grep -oE 'StartupStep\\(\"[a-z ]+\"\\)' $app/Startup.swift | cut -d'\"' -f2 | paste -sd, -)\" == '$want' ]]"

APP="build/DerivedData/Build/Products/Debug/TokenBe.app"
audit_root="$(mktemp -d)/tokenbe-verify-9.5"
audit_log() { cat "$audit_root"/Logs/TokenBe/tokenbe-*.ndjson 2>/dev/null; }
launch_once() { # launch_once <launches so far, this one included>
  local i
  open -n --env "TOKENBE_TEST_ROOT=$audit_root" "$APP" || return 1
  for i in $(seq 1 60); do [[ "$(audit_log | grep -c '"startup_step":"glyph"')" -ge "$1" ]] && break; sleep 0.5; done
  [[ "$(audit_log | grep -c '"startup_step":"glyph"')" -ge "$1" ]] || { echo "launch $1 did not reach step 8"; return 1; }
  osascript -e 'quit app "TokenBe"' >/dev/null
  for i in $(seq 1 40); do pgrep -f "$APP/Contents/MacOS/TokenBe" >/dev/null || break; sleep 0.5; done
  ! pgrep -f "$APP/Contents/MacOS/TokenBe" >/dev/null || { echo "TokenBe did not exit"; return 1; }
}
logged_steps() { # each launch logs the 8 steps (and the login item) in 04's order
  local steps; steps="$(audit_log | grep -oE '"startup_step":"[a-z ]+"' | cut -d'"' -f4 | paste -sd, -)"
  [[ "$steps" == "$want,$want" ]] || { echo "steps: $steps"; return 1; }
}
launch_fields() { # step 1's app.launch carries 04's fields
  local line; line="$(audit_log | grep '"evt":"app.launch"' | grep '"msg":"launch"' | head -n 1)"
  for field in version build macOS locale timezone; do
    grep -q "\"$field\":" <<<"$line" || { echo "app.launch has no $field: $line"; return 1; }
  done
}
clean_audit() { ! audit_log | grep -E '"lvl":"(error|fault)"'; }
check "launch clean on a throwaway root: all 8 startup steps" launch_once 1
check "relaunch on the same data: all 8 startup steps" launch_once 2
check "each launch logs 04's 8 steps in order (login item between ingest and scheduler)" logged_steps
check "step 1 logs version, build, macOS, locale, timezone (04)" launch_fields
check "zero error/fault records across both launches (D10)" clean_audit

for suite in SettingsTests SchedulerTests IngestTailerTests StartupSequenceTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "SettingsRoundTripUITests passed (E2E-6: every tab, relaunch, Reset)" grep -q "Test Suite 'SettingsRoundTripUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
