#!/usr/bin/env bash
# Prints why macOS terminated the XCUITest runner in a UI-test run (Q-039).
#   scripts/ui-kill-reason.sh [<path.xcresult>]   default: the newest result under build/DerivedData/Logs/Test
# `Test crashed with signal kill` carries no reason; the session's system log archive inside the .xcresult does:
# launchd logs the runner's exit with a RunningBoard termination context. `CacheDeleteAppContainerCaches` means the
# disk ran low and macOS's `deleted` daemon terminated the runner to purge its caches.
set -euo pipefail
cd "$(dirname "$0")/.."

result="${1:-$(ls -td build/DerivedData/Logs/Test/*.xcresult 2>/dev/null | head -n 1)}"
[[ -n "$result" && -d "$result" ]] || { echo "ui-kill-reason: no .xcresult found" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun xcresulttool export diagnostics --path "$result" --output-path "$tmp" >/dev/null 2>&1 || true
archive="$(find "$tmp" -maxdepth 3 -name '*.logarchive' | head -n 1)"
free_gb=$(( $(df -k . | awk 'NR == 2 { print $4 }') / 1024 / 1024 ))
echo "ui-kill-reason: $result (free disk now: ${free_gb} GiB)"
[[ -n "$archive" ]] || { echo "ui-kill-reason: no system log archive (Xcode keeps one only when a test fails)"; exit 0; }

reasons="$(/usr/bin/log show --archive "$archive" --style compact 2>/dev/null \
  | grep -E 'xctrunner.*exited with exit reason' \
  | sed -E 's/^([0-9-]+ [0-9:.]+).*code: (0x[0-9a-fA-F]+).*explanation:([A-Za-z]+).*/\1  \2  \3/' || true)"
if [[ -z "$reasons" ]]; then
  echo "ui-kill-reason: the runner was not terminated by the system in this run"
  exit 0
fi
echo "$reasons"
if grep -q CacheDelete <<<"$reasons"; then
  echo "ui-kill-reason: LOW DISK SPACE. macOS purged caches and killed the test runner. Free disk space (the UI" \
       "run needs ≥ ${TB_UI_MIN_FREE_GB:-20} GiB free) and rerun; this is not a test or app failure."
fi
