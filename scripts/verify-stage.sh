#!/usr/bin/env bash
# Machine-checked stage definition of done (14 § 0, § 0.1).
#   scripts/verify-stage.sh <id>
# Runs scripts/stages/<s>.sh for every stage s up to and including <id> (regression), then the generic
# D13 postmortem check (14 § 0.6). Prints `STAGE <id> OK` or the first failing check.
set -uo pipefail
cd "$(dirname "$0")/.."

# The stage order of 14 § 0.5. A phase's last stage is the last id with that phase number.
STAGES=(0.1 0.2 0.3 0.4 0.5  1.1 1.2 1.3  2.1 2.2  3.1 3.2 3.3 3.4 3.5 3.6  4.1 4.2 4.3
        5.1 5.2 5.3 5.4 5.5  6.1 6.2  7.1 7.2 7.3  8.1 8.2 8.3 8.4  9.1 9.2 9.3 9.4 9.5
        10.0.1 10.0.2 10.0.3 10.0.4 10.0.5 10.0.6 10.1 10.2 10.3  11.1 11.2 11.3 11.4 11.5)

STAGE_HEADINGS=("## Outcome" "## What went as planned" "## What went wrong" "## Verify and CI failures"
                "## Deviations from the docs" "## Judgment calls" "## Carry-forward actions")
PHASE_HEADINGS=("## Outcome vs. phase map" "## Patterns across stages" "## Plan and doc changes"
                "## Gates and risks" "## Open carry-forward actions")

id="${1:-}"
target=-1
for i in "${!STAGES[@]}"; do [[ "${STAGES[$i]}" == "$id" ]] && target=$i; done
if (( target < 0 )); then echo "verify-stage.sh: unknown stage '${id}'" >&2; exit 2; fi

# UI tests (Q-047, the owner's request of 2026-11-15; supersedes Q-031's and Q-041's cadence): on when this branch
# changes app, Core or UI-test code, off otherwise. On, `scripts/ui-select.sh` picks the suites: those whose declared
# paths (`// ui-covers:`) the branch touched, plus LaunchSmokeTests and PopoverEmptyStateUITests; a shared file runs
# them all. `TB_UI_TESTS=0` turns them off; `TB_UI_TESTS=1` runs every suite (the full run before 11.5). Off, every
# `ui_check` prints `skip`; unit tests, lint, the guards and every other check still run, and CI is unchanged.
# The H5 soak on this Mac (Q-060, the owner's choice of 2026-11-18): `TB_SOAK=1` turns UI tests off and every
# `launch_check` into `skip`. XCUITest launches dev.bathyon.tokenbe, and the launch checks quit `TokenBe` by name; either
# would stop the soak app, which then logs `crash.previous_launch` (fault) and fails SOAK-1. The real-domain guards skip
# too: the soak app owns that domain and writes to it while the verify runs (Q-061).
SOAK=0
if [[ "${TB_SOAK:-}" == 1 ]]; then
  SOAK=1; TB_UI_TESTS=0
  echo "soak: TB_SOAK=1, the H5 soak is running; UI tests, app launches and real-domain guards are skipped (Q-060, Q-061)"
fi
if [[ "$SOAK" == 1 ]]; then
  UI_TESTS=0; ui_reason="soak running: TB_SOAK=1"
elif [[ "${TB_UI_TESTS:-}" == 0 ]]; then
  UI_TESTS=0; ui_reason="TB_UI_TESTS=0"
elif [[ "${TB_UI_TESTS:-}" == 1 ]]; then
  UI_TESTS=1; TB_UI_SUITES=ALL; ui_reason="TB_UI_TESTS=1, every suite"
else
  base="$(git merge-base origin/main HEAD 2>/dev/null || git rev-parse HEAD)"
  ui_change="$( { git diff --name-only "$base" HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } \
    | grep -E '^(Sources/|Tests/TokenBeUITests/|TokenBe\.xcodeproj/|Config/)' | head -n 1 || true)"
  if [[ -n "$ui_change" ]]; then
    UI_TESTS=1; TB_UI_SUITES="$(scripts/ui-select.sh)"; ui_reason="this branch changes $ui_change"
  else UI_TESTS=0; ui_reason="no app or UI-test change on this branch"; fi
fi
# Stage scripts run in subshells, and `run.sh uitest` (0.4) reads the selection from the environment.
export TB_UI_SUITES="${TB_UI_SUITES:-ALL}"
echo "ui-tests: $([[ "$UI_TESTS" == 1 ]] && echo "on: $TB_UI_SUITES" || echo off) ($ui_reason)"

# check <name> <command…>: runs the command quietly; on failure prints its output tail and stops. Under the soak a
# real-domain guard prints `skip` instead (Q-061).
check() {
  local name="$1"; shift
  if [[ "$SOAK" == 1 && " real_untouched real_tb_unchanged real_support_unchanged " == *" $1 "* ]]; then
    echo "skip ${STAGE} ${name} (soak running: TB_SOAK=1, the soak app writes the real domain)"; return 0
  fi
  local out; out="$(mktemp)"
  if "$@" >"$out" 2>&1; then
    echo "ok   ${STAGE} ${name}"
    rm -f "$out"
  else
    echo "FAIL ${STAGE} ${name}"
    tail -n 40 "$out" | sed 's/^/     /'
    rm -f "$out"
    exit 1
  fi
}

# ui_check <name> <command…>: `check` when UI tests are on and the suite the check reads ran; otherwise one `skip`
# line. The suite is the one the command names (`Test Suite 'X'`, `TokenBeUITests.X`); a check that names none (the
# run itself) runs whenever UI tests are on.
ui_check() {
  local suite; suite="$(printf '%s\n' "$@" | sed -nE "s/.*(Test Suite '|TokenBeUITests\.)([A-Za-z]+).*/\2/p" | head -n 1)"
  if [[ -n "$suite" ]]; then ui_check_for "$suite" "$@"; return; fi
  if [[ "$UI_TESTS" == 1 ]]; then check "$@"; else echo "skip ${STAGE} $1 (UI tests off: $ui_reason)"; fi
}
# ui_check_for <Suite> <name> <command…>: a check that reads what <Suite> leaves behind (Q-047).
ui_check_for() {
  local suite="$1"; shift
  if [[ "$UI_TESTS" != 1 ]]; then echo "skip ${STAGE} $1 (UI tests off: $ui_reason)"
  elif [[ "$TB_UI_SUITES" != ALL && " $TB_UI_SUITES " != *" $suite "* ]]; then
    echo "skip ${STAGE} $1 ($suite not selected: no covered path changed, Q-047)"
  else check "$@"; fi
}
# launch_check <name> <command…>: a check that launches the Debug app (`open -n`) or quits it (`osascript … quit app
# "TokenBe"`, which quits any TokenBe by name), or that reads what such a launch left behind. `check`, except while
# the H5 soak runs on this Mac (TB_SOAK=1, Q-060): then one `skip` line. Reads SOAK at call time.
launch_check() {
  if [[ "$SOAK" == 1 ]]; then echo "skip ${STAGE} $1 (soak running: TB_SOAK=1)"; else check "$@"; fi
}
# launch_check_for <Suite> <name> <command…>: `launch_check` for a launch that also needs <Suite> selected (4.1).
launch_check_for() {
  local suite="$1"; shift
  if [[ "$SOAK" == 1 ]]; then echo "skip ${STAGE} $1 (soak running: TB_SOAK=1)"; else ui_check_for "$suite" "$@"; fi
}
# suite_passed <Suite>: the last `run.sh test` (its xunit result, newer than the run's start) ran the suite, no failures.
# Reads the structured result, not console text, which SwiftPM's relay sometimes truncates (Q-022).
suite_passed() {
  local xml="build/results/test-swift-testing.xml" started="build/run/test.start"
  [[ -s "$xml" && -e "$started" && "$xml" -nt "$started" ]] || { echo "no xunit result from the last run.sh test"; return 1; }
  grep -q "<testcase classname=\"TokenBeCoreTests\.$1\"" "$xml" || { echo "suite $1 not in $xml"; return 1; }
  grep -q '<testsuite [^>]*failures="0"' "$xml" || { echo "failures in $xml"; return 1; }
}

# TokenBe's own keys (`tb.*`) in the owner's real settings domain, snapshotted before any stage runs. AppKit may write
# its own window state there (split-view widths) during UI tests; TokenBe settings must never change (Q-014, Q-020).
# Defined here, not in a stage script, because each stage runs in its own subshell.
real_tb_keys() { defaults read dev.bathyon.tokenbe 2>/dev/null | grep -E '^ *"?tb\.' || true; }
real_tb_before="$(real_tb_keys)"
real_tb_unchanged() { [[ "$(real_tb_keys)" == "$real_tb_before" ]] || { echo "tb.* keys in dev.bathyon.tokenbe changed"; return 1; }; }

# The file names in the owner's real support folder, snapshotted the same way: verification launches only ever use a
# TOKENBE_TEST_ROOT, so no stage may create or remove anything there (D10, Q-014), e.g. a real tokenbe.sqlite.
real_support_files() { ls -1A "$HOME/Library/Application Support/TokenBe" 2>/dev/null || true; }
real_support_before="$(real_support_files)"
real_support_unchanged() { [[ "$(real_support_files)" == "$real_support_before" ]] || { echo "files in ~/Library/Application Support/TokenBe changed"; diff <(echo "$real_support_before") <(real_support_files); return 1; }; }

# headings_in_order <file> <heading…>: the required `## ` headings all appear, in this order.
headings_in_order() {
  local file="$1"; shift
  [[ -s "$file" ]] || { echo "missing or empty: $file"; return 1; }
  local found; found="$(grep -E '^## ' "$file" | grep -Fx -f <(printf '%s\n' "$@"))"
  local want; want="$(printf '%s\n' "$@")"
  if [[ "$found" != "$want" ]]; then
    echo "$file: required headings missing or out of order (14 § 0.6)"
    diff <(echo "$want") <(echo "$found")
    return 1
  fi
}

for (( i = 0; i <= target; i++ )); do
  s="${STAGES[$i]}"
  script="scripts/stages/$s.sh"
  if [[ ! -f "$script" ]]; then echo "FAIL $s missing $script"; exit 1; fi
  ( STAGE="$s"; source "$script" ) || { echo "STAGE $id FAILED (stage $s)"; exit 1; }
done

STAGE="D13"
for (( i = 0; i <= target; i++ )); do
  s="${STAGES[$i]}"
  check "postmortem stage $s" headings_in_order "docs/postmortems/stage-$s.md" "${STAGE_HEADINGS[@]}"
  next="${STAGES[$((i + 1))]:-}"
  if [[ "${s%%.*}" != "${next%%.*}" ]]; then
    check "postmortem phase ${s%%.*}" headings_in_order "docs/postmortems/phase-${s%%.*}.md" "${PHASE_HEADINGS[@]}"
  fi
done

echo "STAGE $id OK"
