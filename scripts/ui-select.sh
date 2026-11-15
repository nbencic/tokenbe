#!/usr/bin/env bash
# Change-based UI-test selection (Q-047, the owner's request of 2026-11-15).
#   scripts/ui-select.sh            prints the UI suites to run, space-separated, or ALL
#   scripts/ui-select.sh --explain  also prints why each suite was chosen (stderr)
# Each suite in Tests/TokenBeUITests declares the paths it covers on `// ui-covers:` lines (repo-relative path
# prefixes, or `always`). A suite runs when the branch diff touches one of its paths or the suite file itself.
# LaunchSmokeTests and PopoverEmptyStateUITests always run. A change to a shared file runs every suite.
set -uo pipefail
cd "$(dirname "$0")/.."

explain=0
[[ "${1:-}" == "--explain" ]] && explain=1
say() { if (( explain )); then echo "$*" >&2; fi; }

# Files every suite goes through: the composition root, the app model and its data feed, the UI-test helpers, the
# project and its build settings.
SHARED='^(Sources/TokenBeApp/(AppModel|Startup|AppEnvironment|TokenBeApp)\.swift|Sources/TokenBeCore/Store/Observation\.swift|Tests/TokenBeUITests/UITestSupport\.swift|TokenBe\.xcodeproj/|Config/)'
ALWAYS=(LaunchSmokeTests PopoverEmptyStateUITests)

# What this branch changes: commits since main, uncommitted edits, untracked files.
changed_files() {
  local base
  base="$(git merge-base origin/main HEAD 2>/dev/null || git rev-parse HEAD)"
  { git diff --name-only "$base" HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
}
changed="$(changed_files)"

shared="$(grep -E "$SHARED" <<<"$changed" | head -n 1 || true)"
if [[ -n "$shared" ]]; then
  say "ALL: shared file $shared"
  echo ALL
  exit 0
fi

# covers <suite file>: the declared prefixes, one per line.
covers() { sed -n 's|^// ui-covers:||p' "$1" | tr ' ' '\n' | sed '/^$/d'; }

selected=("${ALWAYS[@]}")
for name in "${ALWAYS[@]}"; do say "$name: always"; done
for file in Tests/TokenBeUITests/*.swift; do
  suite="$(basename "$file" .swift)"
  [[ "$suite" == UITestSupport ]] && continue
  [[ " ${ALWAYS[*]} " == *" $suite "* ]] && continue
  if grep -qxF "$file" <<<"$changed"; then
    say "$suite: its file changed"; selected+=("$suite"); continue
  fi
  while IFS= read -r prefix; do
    hit="$(grep -F "$prefix" <<<"$changed" | awk -v p="$prefix" 'index($0, p) == 1' | head -n 1)"
    if [[ -n "$hit" ]]; then say "$suite: $hit"; selected+=("$suite"); break; fi
  done < <(covers "$file")
done
echo "${selected[*]}"
