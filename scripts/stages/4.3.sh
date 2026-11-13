# Stage 4.3 — Daily activity (14 § Stage 4.3). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Scheduling/DailyActivity.swift $app/DailyActivityRegistration.swift $app/SettingsUI/SourcesTab.swift
  $app/SettingsUI/AdvancedTab.swift Tests/TokenBeCoreTests/DailyActivityTests.swift
  Tests/TokenBeUITests/DailyRunNowUITests.swift scripts/stages/4.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

for copy in 'Run daily tasks now' 'Last daily run'; do
  check "Strings has 08 copy: $copy" grep -qF "\"$copy\"" $app/Strings.swift
done

# Step 1: the runner (Core) and its registration (04: identifier, 86400/3600, .utility, repeats; startup step 7).
check "a failing step does not stop the run" bash -c "grep -A12 'for step in steps' $core/Scheduling/DailyActivity.swift | grep -qF 'summary.failed.append(step.name)'"
check "sched.daily_start / sched.daily_end / sched.daily_step_failed logged" bash -c "for e in schedDailyStart schedDailyEnd schedDailyStepFailed; do grep -qF \".\$e,\" $core/Scheduling/DailyActivity.swift || exit 1; done"
check "end record carries steps_ok, steps_failed and each step's duration" bash -c "grep -qF 'ctx[\"steps_ok\"]' $core/Scheduling/DailyActivity.swift && grep -qF 'ctx[\"steps_failed\"]' $core/Scheduling/DailyActivity.swift && grep -qF 'ctx[Self.durationKey(step.name)]' $core/Scheduling/DailyActivity.swift"
for literal in 'identifier = "dev.bathyon.tokenbe.daily"' 'interval: TimeInterval = 86_400' 'tolerance: TimeInterval = 3_600' \
               'scheduler.qualityOfService = .utility' 'scheduler.repeats = true'; do
  check "registration: $literal (04)" grep -qF "$literal" $app/DailyActivityRegistration.swift
done
check "startup step 7 after the scheduler (04)" bash -c "grep -A1 'StartupStep(\"scheduler\")' $app/Startup.swift | grep -qF 'StartupStep(\"daily activity\")'"
check "StartupSequenceTests lists the daily activity step (D7)" grep -qF '"scheduler", "daily activity"' Tests/TokenBeCoreTests/StartupSequenceTests.swift
check "terminate invalidates the activity" grep -qF 'environment?.daily?.invalidate()' $app/Startup.swift
check "no Timer, DispatchQueue or Thread (R6)" bash -c "! grep -nE '\\b(Timer|DispatchQueue|Thread)\\b' $core/Scheduling/DailyActivity.swift $app/DailyActivityRegistration.swift"

# Step 2: the steps, in 04's order, and the weekly gate.
# Later stages register at their 04 positions (PM-4.3-3): 5.1's price refresh sits between cost polls and backup.
order() {
  local f=$app/DailyActivityRegistration.swift a p b c d
  a="$(grep -n 'DailyStep("cost polls")' $f | cut -d: -f1)"; b="$(grep -n 'DailyStep("db backup")' $f | cut -d: -f1)"
  p="$(grep -n 'DailyStep("price refresh")' $f | cut -d: -f1)"
  c="$(grep -n 'DailyStep("weekly integrity_check"' $f | cut -d: -f1)"; d="$(grep -n 'DailyStep("incremental_vacuum")' $f | cut -d: -f1)"
  [[ -n "$a" && -n "$p" && -n "$b" && -n "$c" && -n "$d" && "$a" -lt "$p" && "$p" -lt "$b" && "$b" -lt "$c" && "$c" -lt "$d" ]]
}
check "steps in 04's order: cost polls, price refresh, backup, weekly integrity, vacuum" order
check "integrity every 7th run (04)" bash -c "grep -qF 'integrityEvery = 7' $app/DailyActivityRegistration.swift && grep -qF 'gate: .everyNthRun(Self.integrityEvery)' $app/DailyActivityRegistration.swift"
check "cost polls run for accounts with capabilities.cost" grep -qF 'capabilities.cost else { continue }' $core/Scheduling/DailyActivity.swift

# Step 3: 09 bookkeeping and the two controls.
for literal in 'settings.dailyLastRunAt = Date().timeIntervalSince1970' 'settings.dailyRunCount = runNumber' \
               'settings.dbLastBackupAt = Date().timeIntervalSince1970' 'settings.dbLastIntegrityCheckAt = Date().timeIntervalSince1970'; do
  check "writes $literal (D4)" grep -qF "$literal" $app/DailyActivityRegistration.swift
done
check "09 has no tb.poll.costDailyLocalTime (D-daily-no-fixed-time)" bash -c "! grep -qF 'costDailyLocalTime' docs/09-settings-spec.md"
check "Sources: Run daily tasks now runs the activity" bash -c "grep -A2 'Button(Strings.runDailyTasksNow)' $app/SettingsUI/SourcesTab.swift | grep -qF 'await daily.run()'"
check "Advanced: Last daily run reads tb.daily.lastRunAt" grep -qF 'settings.dailyLastRunAt' $app/SettingsUI/AdvancedTab.swift
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh

for suite in DailyActivityTests StartupSequenceTests; do
  check "suite $suite passed" suite_passed "$suite"
done
# 14 Verify: Run daily tasks now → sched.daily_start … db.backup … db.vacuum … sched.daily_end (the UI test asserts the
# order from the app's log, and the account page's `Cost · ok · HH:mm`, PM-4.2-2).
ui_check "DailyRunNowUITests passed" grep -q "Test Suite 'DailyRunNowUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the test asserts the 14 Verify order" grep -qF '["sched.daily_start", "poll.ok cost", "db.backup", "db.vacuum", "sched.daily_end"]' Tests/TokenBeUITests/DailyRunNowUITests.swift
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
