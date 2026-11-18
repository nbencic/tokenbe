#!/usr/bin/env bash
# 07 § Definition of done, 14 D3: the Mandatory events table of docs/07-logging.md and the `Evt` enum list exactly
# the same event names, both directions, each once.
set -euo pipefail
cd "$(dirname "$0")/.."

doc="docs/07-logging.md"
enum_file="Sources/TokenBeCore/Logging/Evt.swift"

# `--from-tests` (11, PM-0.2-3): every event is produced in some test, i.e. `Tests/` names its `Evt` case or its
# `cat.event` string. The exemptions have no producer in a test by design (Q-059):
#   ledger.auto_zero         no producer in V1 (O-18)
#   ledger.reconcile         no V1 code path creates a reconcile row (Q-042)
#   ui.hotkey_failed         app-only: Carbon's RegisterEventHotKey failing (1.3.sh checks the producer)
#   crash.previous_launch    app-only: the running sentinel at launch (0.4.sh checks the producer)
if [[ "${1:-}" == "--from-tests" ]]; then
  exempt=" ledger.auto_zero ledger.reconcile ui.hotkey_failed crash.previous_launch "
  missing=0
  while read -r name evt; do
    [[ "$exempt" == *" $evt "* ]] && continue
    if ! grep -rqE "\.$name\b|\"$evt\"" Tests/; then echo "no test produces $evt (.$name)"; missing=1; fi
  done < <(grep -oE 'case [a-zA-Z]+ = "[a-z_]+\.[a-z_]+"' "$enum_file" | sed -E 's/case ([a-zA-Z]+) = "([^"]+)"/\1 \2/')
  if [[ $missing -eq 0 ]]; then echo "check-log-events --from-tests: every event is produced in a test (4 exempt)"; fi
  exit $missing
fi

# Column 1 of every table row under "## Mandatory events", up to the next "## " heading; compound rows split.
table="$(awk '/^## Mandatory events/ {inside = 1; next} /^## / {inside = 0} inside && /^\| `/' "$doc" \
  | cut -d'|' -f2 | grep -oE '`[a-z_]+\.[a-z_]+`' | tr -d '`' | sort)"
enum="$(grep -oE '= "[a-z_]+\.[a-z_]+"' "$enum_file" | cut -d'"' -f2 | sort)"

status=0
if [[ -z "$table" ]]; then echo "check-log-events: no events found in $doc"; exit 1; fi
dup_table="$(uniq -d <<<"$table")"
dup_enum="$(uniq -d <<<"$enum")"
if [[ -n "$dup_table" ]]; then echo "duplicate in $doc: $dup_table"; status=1; fi
if [[ -n "$dup_enum" ]]; then echo "duplicate in $enum_file: $dup_enum"; status=1; fi
only_doc="$(comm -23 <(echo "$table") <(echo "$enum"))"
only_enum="$(comm -13 <(echo "$table") <(echo "$enum"))"
if [[ -n "$only_doc" ]]; then echo "in $doc but not in Evt: $only_doc"; status=1; fi
if [[ -n "$only_enum" ]]; then echo "in Evt but not in $doc: $only_enum"; status=1; fi
if [[ $status -eq 0 ]]; then echo "check-log-events: $(wc -l <<<"$table" | tr -d ' ') events match"; fi
exit $status
