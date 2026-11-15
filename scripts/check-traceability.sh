#!/usr/bin/env bash
# E2E-9 (11): every `ui.band_change` caused by data (ctx.trigger `data`, or no trigger) follows a `poll.ok` or `ledger.*`
# record for the same `acct` within the preceding 2 s. A poll commits its rows before it logs `poll.ok`, so a
# `poll.ok` up to 2 s after the change counts too. Changes caused by Alerts settings, time passing or the launch
# (`settings`, `clock`, `launch`) have no such record by construction and are not joined (Q-042).
#   scripts/check-traceability.sh <file.ndjson | log folder>...
# Prints one line per untraced change and exits 1, or `traceability: N band changes traced` and exits 0.
set -euo pipefail
if (( $# == 0 )); then echo "usage: $0 <file.ndjson | folder>..." >&2; exit 2; fi
files=()
for arg in "$@"; do
  if [[ -d "$arg" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$arg" -maxdepth 1 -name '*.ndjson' | sort)
  else
    files+=("$arg")
  fi
done
(( ${#files[@]} > 0 )) || { echo "check-traceability: no NDJSON files" >&2; exit 2; }

# shellcheck disable=SC2016
result="$(cat "${files[@]}" | jq -R 'fromjson? // empty' | jq -s -r '
  def ms: (.ts[0:19] + "Z" | fromdateiso8601) * 1000 + ((.ts[20:23] // "0") | tonumber? // 0);
  [ .[] | select(type == "object" and has("ts") and has("evt")) | . + {t: ms} ] as $all
  | [ $all[] | select(.evt == "ui.band_change" and ((.ctx.trigger // "data") == "data")) ] as $changes
  | [ $changes[] | . as $c
      | select([ $all[] | select(.acct == $c.acct and
                                 (((.evt == "poll.ok" or (.evt | startswith("ledger."))) and .t <= $c.t and .t >= $c.t - 2000)
                                  or (.evt == "poll.ok" and .t > $c.t and .t <= $c.t + 2000))) ] | length == 0)
      | "untraced ui.band_change acct=\(.acct) ts=\(.ts) \(.ctx.from)->\(.ctx.to)" ] as $bad
  | if ($bad | length) > 0 then ($bad | join("\n")) else "ok \($changes | length)" end
')"
if [[ "$result" == ok* ]]; then
  echo "traceability: ${result#ok } band changes traced"
else
  echo "$result"
  exit 1
fi
