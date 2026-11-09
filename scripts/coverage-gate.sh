#!/usr/bin/env bash
# Fails when TokenBeCore line coverage is below the gate (10 § CI, 14 § Stage 0.5; default 85 %).
# Run after `swift test --enable-code-coverage`. Reads the llvm-cov export JSON that SwiftPM writes, counting only
# files under Sources/TokenBeCore/ (dependencies and tests excluded).
#   scripts/coverage-gate.sh [minimum-percent]
set -euo pipefail
cd "$(dirname "$0")/.."

minimum="${1:-85}"
json="$(swift test --show-codecov-path 2>/dev/null)"
[[ -s "$json" ]] || { echo "coverage-gate: no coverage data at '$json'; run swift test --enable-code-coverage first"; exit 2; }

read -r covered count < <(jq -r '[.data[0].files[] | select(.filename | test("/Sources/TokenBeCore/")) | .summary.lines]
  | "\(map(.covered) | add // 0) \(map(.count) | add // 0)"' "$json")
[[ "$count" -gt 0 ]] || { echo "coverage-gate: no TokenBeCore files in $json"; exit 2; }

percent="$(awk -v c="$covered" -v n="$count" 'BEGIN { printf "%.2f", 100 * c / n }')"
if awk -v p="$percent" -v m="$minimum" 'BEGIN { exit !(p >= m) }'; then
  echo "coverage-gate: TokenBeCore lines $covered/$count = $percent% (minimum $minimum%)"
else
  echo "coverage-gate: FAIL TokenBeCore lines $covered/$count = $percent% < $minimum%"
  jq -r '.data[0].files[] | select(.filename | test("/Sources/TokenBeCore/")) | "\(.summary.lines.percent * 100 | floor / 100)% \(.filename | sub(".*/Sources/"; "Sources/"))"' "$json" | sort -n | head -10
  exit 1
fi
