#!/usr/bin/env bash
# Secret and outbound-URL guard (14 § Stage 0.5, 07 § Redaction, 12 § R4/R8).
#  1. No key-shaped string (the 07 patterns) in any tracked file, Tests/Fixtures included, nor in build products.
#  2. No `.env` file is tracked.
#  3. Every URL literal in Swift sources points at an allowlisted host (02's endpoints, the LiteLLM feed, GitHub).
#   scripts/check-no-secrets.sh             check the repository
#   scripts/check-no-secrets.sh --root DIR  check every file under DIR instead (used by the stage self-test)
set -uo pipefail
cd "$(dirname "$0")/.."

root=""
if [[ "${1:-}" == "--root" ]]; then root="${2:?--root needs a directory}"; fi

# 07 patterns 1-6 (pattern 7, the exact pass, needs the live key cache and has no static form).
key_re='sk-[A-Za-z0-9_-]{8,}|sk-ant-[A-Za-z0-9_-]{8,}|xai-[A-Za-z0-9]{8,}|sk-or-v1-[A-Za-z0-9]{8,}'
key_re+='|(authorization|x-api-key|x-goog-api-key)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?([a-z]+[[:space:]]+)?[A-Za-z0-9._~+/=-]{16,}'
key_re+='|bearer[[:space:]]+[A-Za-z0-9._~+/=-]{16,}'

allowed_hosts=(
  "api.openai.com" "api.anthropic.com" "openrouter.ai" "api.deepseek.com" "api.x.ai"
  "raw.githubusercontent.com/BerriAI/litellm" "api.github.com/repos/nbencic/tokenbe" "github.com/nbencic/tokenbe"
)

status=0
fail() { echo "check-no-secrets: $*"; status=1; }

# Matches that are not secrets: the fixture placeholder of 11 (`sk-FIXTURE-<provider>-<last4>`) and bare
# key-format prefixes in prose, which end in `-` or `_` (e.g. `sk-ant-admin01-…` in 02).
not_secret() { grep -viE ':(sk-FIXTURE-[A-Za-z0-9]*-?[A-Za-z0-9]{0,4}|[A-Za-z0-9_-]*[-_])$'; }

# 1. Key patterns in files (each match on its own line: file:line:match).
if [[ -n "$root" ]]; then
  hits="$(grep -rnoiIE "$key_re" "$root" 2>/dev/null | not_secret)"
else
  hits="$(git ls-files -z | xargs -0 grep -noiIE "$key_re" 2>/dev/null | not_secret)"
fi
[[ -z "$hits" ]] || fail "key-shaped strings found:"$'\n'"$(cut -c1-160 <<<"$hits")"

# 1b. Key patterns in build products (binaries included), when they exist.
if [[ -z "$root" ]]; then
  for products in build/DerivedData/Build/Products .build/out/Products .build/release .build/debug; do
    [[ -d "$products" ]] || continue
    found="$(grep -roaiE "$key_re" "$products" 2>/dev/null | not_secret | cut -d: -f1 | sort -u | head -5)"
    [[ -z "$found" ]] || fail "key-shaped strings in build products:"$'\n'"$found"
  done
fi

# 2. No tracked .env files.
if [[ -z "$root" ]]; then
  envs="$(git ls-files | grep -E '(^|/)\.env($|\.)')"
  [[ -z "$envs" ]] || fail ".env files are tracked: $envs"
fi

# 3. URL literals in Swift sources.
sources="${root:-.}/Sources"
if [[ -d "$sources" ]]; then
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    rest="${url#*://}"
    ok=0
    if [[ "$url" == https://* ]]; then
      for host in "${allowed_hosts[@]}"; do
        if [[ "$rest" == "$host" || "$rest" == "$host"/* || "$rest" == "$host"\?* ]]; then ok=1; break; fi
      done
    fi
    [[ $ok -eq 1 ]] || fail "URL outside the allowlist in Sources/: $url"
  done < <(grep -rhoE --include='*.swift' 'https?://[^"[:space:]\\)]+' "$sources" 2>/dev/null | sort -u)
fi

[[ $status -eq 0 ]] && echo "check-no-secrets: clean"
exit $status
