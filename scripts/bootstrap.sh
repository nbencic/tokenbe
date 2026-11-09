#!/usr/bin/env bash
# Checks the development machine (14 § Stage 0.1): macOS ≥ 15, Xcode ≥ 16.2, swiftlint present.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]; }

macos="$(sw_vers -productVersion)"
if version_ge "$macos" "15.0"; then echo "ok   macOS $macos"; else echo "FAIL macOS $macos < 15.0"; fail=1; fi

xcode="$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}')"
if [[ -n "$xcode" ]] && version_ge "$xcode" "16.2"; then echo "ok   Xcode $xcode"
else echo "FAIL Xcode ${xcode:-not found} (need ≥ 16.2; run xcode-select -s /Applications/Xcode.app)"; fail=1; fi

if command -v swiftlint >/dev/null 2>&1; then echo "ok   swiftlint $(swiftlint version)"
else echo "FAIL swiftlint missing (brew install swiftlint)"; fail=1; fi

if [[ $fail -ne 0 ]]; then exit 1; fi
cat <<'NEXT'

Next steps:
  scripts/run.sh build && scripts/run.sh test     build and test TokenBeCore
  scripts/verify-stage.sh <id>                     machine-checked definition of done (docs/14 § 0)
  docs/14-development-plan.md § 0.4                human gates (H1 Xcode project before Stage 0.4)
NEXT
