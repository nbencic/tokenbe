#!/usr/bin/env bash
# Refreshes the bundled price snapshot (14 § Stage 5.1 step 1, 10 § Release): downloads the LiteLLM feed (02 § Price
# feed), keeps only the entries with `"mode": "chat"` (05 § Price lookup ignores the rest), and writes
# Sources/TokenBeApp/Resources/prices.bundled.json (sorted keys, so a refresh diffs cleanly) and its sha256.
# Run at every release and whenever the bundled prices should move. No key is involved.
#   scripts/update-bundled-prices.sh [feed-url]
set -euo pipefail
cd "$(dirname "$0")/.."

url="${1:-https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json}"
out="Sources/TokenBeApp/Resources/prices.bundled.json"
sum="Sources/TokenBeApp/Resources/prices.bundled.sha256"
command -v jq >/dev/null || { echo "update-bundled-prices: needs jq (brew install jq)"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# 02: 20 MB body limit, as the app applies it.
curl -fsSL --max-time 60 --max-filesize 20971520 -o "$tmp/raw.json" "$url"
jq -S 'with_entries(select((.value | type) == "object" and .value.mode == "chat"))' "$tmp/raw.json" > "$tmp/chat.json"

entries="$(jq 'length' "$tmp/chat.json")"
priced="$(jq '[.[] | select((.input_cost_per_token // 0) > 0 and (.output_cost_per_token // 0) > 0)] | length' "$tmp/chat.json")"
# O-6 applies here too: a feed where most chat entries lost their input price is not shipped.
(( entries > 0 && priced * 2 > entries )) || { echo "update-bundled-prices: shape check failed ($priced of $entries priced)"; exit 1; }
# The repo is public and scanned for key-shaped strings (check-no-secrets.sh); refuse a file that would trip it.
scripts/check-no-secrets.sh --root "$tmp" >/dev/null || { echo "update-bundled-prices: key-shaped string in the feed"; exit 1; }

mv "$tmp/chat.json" "$out"
shasum -a 256 "$out" | cut -d' ' -f1 > "$sum"
echo "update-bundled-prices: $entries chat entries ($priced priced), sha256 $(cat "$sum")"
