# Stage 4.1 — Scheduler, coordinator, pollers; Sources tab; Refresh/Pause (14 § Stage 4.1). Sourced by
# scripts/verify-stage.sh.

app=Sources/TokenBeApp
sched=Sources/TokenBeCore/Scheduling
inventory=(
  $sched/Job.swift $sched/SchedulerLoop.swift $sched/AccountPoller.swift $sched/PollCoordinator.swift
  $sched/PollCoordinator+Inputs.swift $app/SettingsUI/SourcesTab.swift $app/Popover/PopoverView.swift
  Tests/TokenBeCoreTests/SchedulerTests.swift Tests/TokenBeCoreTests/CoordinatorTests.swift
  Tests/TokenBeCoreTests/Support/SchedulerHarness.swift Tests/TokenBeUITests/RefreshPauseUITests.swift
  scripts/stages/4.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 08's copy and 14's Sources labels, verbatim in Strings.swift (R9, D8).
for copy in 'Refreshed \(freshness)' 'Paused \u{00B7} resumes \(time)' 'Resume' 'Pause polling for 1 h' 'Sources' \
            'Balance every' 'Anthropic usage every' 'OpenAI usage every' 'Keys every' 'Low Power multiplier'; do
  check "Strings has copy: $copy" grep -qF "\"$copy\"" $app/Strings.swift
done
check "no inline Text copy in views (D8)" bash -c "! grep -rnE 'Text\\(\"[A-Za-z]' $app --include=*.swift | grep -v Strings.swift"

# Step 1: the jobs, the loop and its 04 constants, one poller per account, the coordinator.
check "Job lives in Scheduling/Job.swift only" bash -c "grep -qF 'public enum Job: String' $sched/Job.swift && ! grep -rqF 'enum Job' Sources/TokenBeCore/Model"
check "cost is not a minute-cadence job (04 § Daily activity)" grep -qF 'minuteCadence: [Job] = [.usage, .balance, .keys]' $sched/Job.swift
check "Low Power multiplies the interval (04)" grep -qF 'lowPower ? settings.lowPowerMultiplier : 1' $sched/Job.swift
check "tolerance 5 s (04)" grep -qF 'static var tolerance: Duration { .seconds(5) }' $sched/SchedulerLoop.swift
check "backoff between attempts uses RetryPolicy.backoff (04)" grep -qF 'RetryPolicy.backoff(interval:' $sched/SchedulerLoop.swift
check "clock jump threshold 30 s (04)" grep -qF 'clockJumpThreshold: Duration { .seconds(30) }' $sched/PollCoordinator.swift
check "overrun at 2 × interval (04)" grep -qF 'overrunFactor: Int { 2 }' $sched/PollCoordinator.swift
check "the loop sleeps on the injected clock with the tolerance" grep -qF 'clock.sleep(until: deadline, tolerance: Schedule.tolerance)' $sched/PollCoordinator.swift
check "I1: AccountPoller claims the job before its first suspension" bash -c "grep -A8 'public func run(_ job: Job' $sched/AccountPoller.swift | grep -qF 'inFlight.insert(job)'"
check "the phase is recorded (fetch/decode/write)" bash -c "grep -qF 'phase.set(.fetch)' $sched/Poller.swift && grep -qF 'phase.set(.decode)' Sources/TokenBeCore/Providers/RawBody.swift && grep -qF 'phase.set(.write)' $sched/Poller.swift"
for evt in schedTick schedSkip schedOverlapSkipped schedOverrun schedClockJump schedLowPower; do
  check "event .$evt has a call site" bash -c "grep -rqF '.$evt,' $sched"
done
check "app.network_changed is logged by NWPathMonitorAdapter" grep -qF '.appNetworkChanged' Sources/TokenBeCore/Network/NetworkMonitor.swift
check "no Timer, DispatchQueue or Thread in Scheduling (R6)" bash -c "! grep -rnE '\\b(Timer|DispatchQueue|Thread)\\b' $sched"
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh

# Step 2: startup step 6 (04), after the login item, which 04 does not order (2.1.sh checks the first five).
check "startup runs the scheduler step after the login item" bash -c "grep -A1 'StartupStep(\"login item\")' $app/Startup.swift | grep -qF 'StartupStep(\"scheduler\")'"
# Later stages insert steps before the scheduler (5.1: `prices`), so any steps may sit between accounts and scheduler.
check "StartupSequenceTests lists the scheduler step (D7)" grep -qE '"logging", "database", "accounts", ("[a-z ]+", )*"scheduler"' Tests/TokenBeCoreTests/StartupSequenceTests.swift
# 4.2 routes the monitor through `networkMonitor()` (a DEBUG offline seam for its UI test, Q-036); production stays
# `NWPathMonitorAdapter`.
check "Startup's network monitor is NWPathMonitorAdapter outside DEBUG test roots" bash -c "grep -A7 'private func networkMonitor()' $app/Startup.swift | grep -qF 'return NWPathMonitorAdapter()'"
for literal in 'coordinator.follow(repository.observeSummaryInputs())' 'coordinator.follow(networkMonitor())' \
               'coordinator.follow(settings)' 'NSProcessInfoPowerStateDidChange' 'NSWorkspace.didWakeNotification' \
               'coordinator?.shutdown()'; do
  check "Startup wires $literal" grep -qF "$literal" $app/Startup.swift
done
check "ManualNetworkMonitor is the test seam (14 § 0.3, PM-3.1-4)" grep -qF 'final class ManualNetworkMonitor: NetworkMonitor' Tests/TokenBeCoreTests/Support/SchedulerHarness.swift

# Steps 3–5: Sources tab, popover header and footer, AppModel state; account.paused and overrides.
tab_order() {
  local file=$app/SettingsUI/SettingsView.swift a s p
  a="$(grep -n 'value: SettingsTab.accounts' $file | cut -d: -f1)"
  s="$(grep -n 'value: SettingsTab.sources' $file | cut -d: -f1)"
  p="$(grep -n 'value: SettingsTab.privacy' $file | cut -d: -f1)"
  [[ -n "$a" && -n "$s" && -n "$p" && "$a" -lt "$s" && "$s" -lt "$p" ]]
}
check "Sources tab between Accounts and Privacy (08)" tab_order
for key in pollBalanceIntervalS pollUsageIntervalAnthropicS pollUsageIntervalOpenAIS pollKeysIntervalS pollLowPowerMultiplier; do
  check "Sources tab binds $key (D4)" grep -qF "\$settings.$key" $app/SettingsUI/SourcesTab.swift
done
check "pause writes now + 3600 to tb.poll.pausedUntil" bash -c "grep -qF 'pauseDuration: TimeInterval = 3600' $app/AppModel.swift && grep -qF 'settings.pollPausedUntil = Date().addingTimeInterval(Self.pauseDuration)' $app/AppModel.swift"
check "resume writes 0" grep -qF 'environment?.settings.pollPausedUntil = 0' $app/AppModel.swift
check "header freshness is the oldest account success (Core)" grep -qF 'AccountSummary.refreshedAt(accounts)' $app/AppModel.swift
check "the refresh button spins while jobs are in flight" grep -qF 'isActive: model.inFlightCount > 0' $app/Popover/PopoverView.swift
check "AppModel follows CoordinatorState" grep -qF 'let states = coordinator.states' $app/AppModel.swift
check "summaries carry account.paused (PM-3.5-3)" grep -qF 'isPaused: record.paused' Sources/TokenBeCore/Ledger/AccountSummaryBuilder.swift
check "account.interval_override_json has its Accounts-tab disclosure" grep -qF 'update { $0.intervalOverrideJson = json }' $app/SettingsUI/AccountsTab.swift
check "Remove account… stops the account's polls first" bash -c "grep -A6 'private func remove()' $app/SettingsUI/AccountsTab.swift | grep -qF 'await coordinator?.stop(record.id)'"
check "onboarding Done runs no poll of its own (PM-3.6-3)" bash -c "! grep -qE 'runOnce|poller' $app/Onboarding/OnboardingSheet.swift"

for suite in SchedulerTests CoordinatorTests ObservationTests AccountSummaryBuilderTests FormattersTests StartupSequenceTests \
             PollerTests SettingsTests; do
  check "suite $suite passed" suite_passed "$suite"
done
ui_check "RefreshPauseUITests passed" grep -q "Test Suite 'RefreshPauseUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"

# 14 Verify: the Debug app runs 3 min in fixture mode on a throwaway TOKENBE_TEST_ROOT with one seeded OpenAI account and
# `tb.poll.usageIntervalOpenAIS = 60`; the log shows `poll.ok usage` every 60 s ± 5 s and no error or fault (D10).
# Settings go in as launch arguments (the argument domain, never stored), so nothing is left in the UI-test suite.
# It launches the app, so it runs when UI tests do (Q-034).
APP="build/DerivedData/Build/Products/Debug/TokenBe.app"
cad_root="$(mktemp -d)/tokenbe-verify-4.1"
cad_log() { cat "$cad_root"/Logs/TokenBe/tokenbe-*.ndjson 2>/dev/null; }
cad_quit() {
  local i
  osascript -e 'quit app "TokenBe"' >/dev/null
  for i in $(seq 1 40); do pgrep -f "$APP/Contents/MacOS/TokenBe" >/dev/null || return 0; sleep 0.5; done
  echo "TokenBe did not exit"; return 1
}
cad_launch() {
  open -n --env "TOKENBE_TEST_ROOT=$cad_root" "$APP" --args -tb.debug.fixtureMode '<true/>' \
    -tb.poll.usageIntervalOpenAIS '<integer>60</integer>' -tb.poll.pausedUntil '<real>0</real>' \
    -tb.ui.onboardingDone '<true/>' -tb.log.level info
}
cadence_run() {
  local i db="$cad_root/Application Support/TokenBe/tokenbe.sqlite"
  cad_launch || return 1
  for i in $(seq 1 60); do cad_log | grep -q '"startup_step":"scheduler"' && break; sleep 0.5; done
  cad_quit || return 1
  # One OpenAI account and its 4 poll_state rows, as onboarding writes them; the key built from parts (Q-028).
  sqlite3 "$db" "INSERT INTO account (id, provider, label, keychain_ref, balance_mode, currency, capabilities, org_id,
      org_name, auto_reload_enabled, paused, created_at) VALUES ('0190f0a0-0000-7000-8000-0000000004a1', 'openai',
      'OpenAI', 'openai', 'anchored', 'USD', '{\"balance\":false,\"balance_mode_default\":\"anchored\",\"cost\":true,\"currency_hint\":\"USD\",\"key_names\":true,\"per_key_usage\":true,\"usage\":true,\"usage_lag_s\":3600}',
      'org_fixture', 'Fixture Org', 0, 0, '2026-11-12T00:00:00.000Z');
    INSERT INTO poll_state (account_id, job) SELECT '0190f0a0-0000-7000-8000-0000000004a1', job
      FROM (SELECT 'usage' AS job UNION SELECT 'cost' UNION SELECT 'balance' UNION SELECT 'keys');" || return 1
  local key="sk-""admin-$(printf 'Cd9%.0s' $(seq 1 14))"
  printf '{"openai":"%s"}' "$key" > "$cad_root/test-keychain.json"
  cad_launch || return 1
  caffeinate -i -d -t 200 &
  sleep 190
  cad_quit
}
cadence_ok() {
  python3 -I - "$cad_root" <<'PY'
import json, sys, glob, datetime
root = sys.argv[1]
recs = []
for path in sorted(glob.glob(root + "/Logs/TokenBe/tokenbe-*.ndjson")):
    for line in open(path):
        recs.append(json.loads(line))
bad = [r for r in recs if r["lvl"] in ("error", "fault")]
if bad:
    print("error/fault records:", bad[:3]); sys.exit(1)
ts = [datetime.datetime.fromisoformat(r["ts"].replace("Z", "+00:00")) for r in recs
      if r["evt"] == "poll.ok" and r.get("job") == "usage"]
if len(ts) < 3:
    print("only %d poll.ok usage records" % len(ts)); sys.exit(1)
gaps = [(b - a).total_seconds() for a, b in zip(ts, ts[1:])]
print("usage poll.ok gaps (s):", [round(g, 1) for g in gaps])
if any(abs(g - 60) > 5 for g in gaps):
    sys.exit(1)
PY
}
ui_check "fixture-mode run: account seeded, 190 s of polling" cadence_run
ui_check "poll.ok usage every 60 s ± 5 s, zero error/fault (14 Verify, D10)" cadence_ok
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
