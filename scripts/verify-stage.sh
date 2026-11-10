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
        10.1 10.2 10.3  11.1 11.2 11.3 11.4 11.5)

STAGE_HEADINGS=("## Outcome" "## What went as planned" "## What went wrong" "## Verify and CI failures"
                "## Deviations from the docs" "## Judgment calls" "## Carry-forward actions")
PHASE_HEADINGS=("## Outcome vs. phase map" "## Patterns across stages" "## Plan and doc changes"
                "## Gates and risks" "## Open carry-forward actions")

id="${1:-}"
target=-1
for i in "${!STAGES[@]}"; do [[ "${STAGES[$i]}" == "$id" ]] && target=$i; done
if (( target < 0 )); then echo "verify-stage.sh: unknown stage '${id}'" >&2; exit 2; fi

# check <name> <command…>: runs the command quietly; on failure prints its output tail and stops.
check() {
  local name="$1"; shift
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
