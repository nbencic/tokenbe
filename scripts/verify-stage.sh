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
