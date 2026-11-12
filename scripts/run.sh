#!/usr/bin/env bash
# Runs a long task in the background with a log file and a timeout (14 § 0, D-run-wrapper).
#   scripts/run.sh <task>            start, then wait via scripts/wait.sh; exits with the task's exit code
#   scripts/run.sh --detach <task>   start and return at once; collect later with scripts/wait.sh <task>
# Log: build/logs/<task>-<timestamp>.log   State: build/run/<task>.{pid,log,timeout,start,exit}
set -euo pipefail
cd "$(dirname "$0")/.."

detach=0
if [[ "${1:-}" == "--detach" ]]; then detach=1; shift; fi
task="${1:-}"

# task → command and timeout (seconds). Later stages add their tasks here (build-app, uitest, perf, load).
case "$task" in
  build)         cmd=(swift build);                                         timeout=900 ;;
  build-release) cmd=(swift build -c release -Xswiftc -warnings-as-errors); timeout=900 ;;
  # The structured result (build/results/test-swift-testing.xml) is what stage checks read: SwiftPM's console
  # relay occasionally loses the tail of the output although every test ran (Q-022).
  test)          cmd=(swift test --xunit-output build/results/test.xml);  timeout=900 ;;
  lint)          cmd=(swiftlint --strict);                                  timeout=300 ;;
  build-app)     cmd=(xcodebuild -project TokenBe.xcodeproj -scheme TokenBe -configuration Debug
                      -derivedDataPath build/DerivedData build);                timeout=900 ;;
  build-app-release) cmd=(xcodebuild -project TokenBe.xcodeproj -scheme TokenBe -configuration Release
                      -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO); timeout=900 ;;
  # `TB_UI_ONLY=<Suite>[/<test>]` runs one UI-test suite or case (reruns and spikes); unset runs them all.
  uitest)        cmd=(xcodebuild -project TokenBe.xcodeproj -scheme TokenBe -configuration Debug
                      -derivedDataPath build/DerivedData test ${TB_UI_ONLY:+-only-testing:TokenBeUITests/$TB_UI_ONLY});
                 timeout=1800 ;;
  *) echo "run.sh: unknown task '${task}'. Known: build build-release test lint build-app build-app-release uitest" >&2; exit 2 ;;
esac

state="build/run"; logs="build/logs"
mkdir -p "$state" "$logs" build/results
if [[ -f "$state/$task.pid" ]] && kill -0 "$(cat "$state/$task.pid")" 2>/dev/null && [[ ! -f "$state/$task.exit" ]]; then
  echo "run.sh: task '$task' is already running (pid $(cat "$state/$task.pid")); use scripts/wait.sh $task" >&2
  exit 3
fi

log="$logs/$task-$(date +%Y%m%d-%H%M%S).log"
rm -f "$state/$task.exit"
echo "$log" > "$state/$task.log"
echo "$timeout" > "$state/$task.timeout"
date +%s > "$state/$task.start"

# Job control gives the task its own process group, so wait.sh can kill the whole tree on timeout.
set -m
( set +e; "${cmd[@]}"; echo $? > "$state/$task.exit" ) > "$log" 2>&1 < /dev/null &
pid=$!
set +m
disown "$pid" 2>/dev/null || true
echo "$pid" > "$state/$task.pid"
echo "run.sh: started '$task' (pid $pid, timeout ${timeout}s), log $log"

if [[ $detach -eq 1 ]]; then exit 0; fi
exec scripts/wait.sh "$task"
