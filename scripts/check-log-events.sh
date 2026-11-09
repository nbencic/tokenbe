#!/usr/bin/env bash
# 07 § Definition of done, 14 D3: the Mandatory events table of docs/07-logging.md and the `Evt` enum list exactly
# the same event names, both directions, each once.
set -euo pipefail
cd "$(dirname "$0")/.."

doc="docs/07-logging.md"
enum_file="Sources/TokenBeCore/Logging/Evt.swift"

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
