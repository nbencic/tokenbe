#!/usr/bin/env bash
# Waits for a task started by scripts/run.sh: polls every 15 s, bounded by the task's timeout,
# then prints the last 40 log lines and the exit code, and exits with it (124 timeout, 125 died without exit code).
set -euo pipefail
cd "$(dirname "$0")/.."

task="${1:-}"
state="build/run"
[[ -n "$task" && -f "$state/$task.pid" ]] || { echo "wait.sh: no task '${task}' started by run.sh" >&2; exit 2; }

pid="$(cat "$state/$task.pid")"
log="$(cat "$state/$task.log")"
timeout="$(cat "$state/$task.timeout")"
start="$(cat "$state/$task.start")"
interval="${TB_WAIT_INTERVAL:-15}"

finish() {
  echo "----- last 40 lines of $log -----"
  tail -n 40 "$log" || true
  echo "----- $task exit $1 -----"
  exit "$1"
}

while :; do
  if [[ -f "$state/$task.exit" ]]; then finish "$(cat "$state/$task.exit")"; fi
  if ! kill -0 "$pid" 2>/dev/null; then
    sleep 1   # the exit file is written just before the process ends
    if [[ -f "$state/$task.exit" ]]; then finish "$(cat "$state/$task.exit")"; fi
    echo "wait.sh: '$task' (pid $pid) ended without an exit code" >&2
    finish 125
  fi
  elapsed=$(( $(date +%s) - start ))
  if (( elapsed >= timeout )); then
    echo "wait.sh: '$task' exceeded ${timeout}s; terminating process group $pid" >&2
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 5
    kill -KILL -- "-$pid" 2>/dev/null || true
    echo 124 > "$state/$task.exit"
    finish 124
  fi
  remaining=$(( timeout - elapsed ))
  sleep $(( remaining < interval ? remaining : interval ))
done
