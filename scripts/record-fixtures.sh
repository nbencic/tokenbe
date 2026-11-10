#!/usr/bin/env bash
# Records live provider responses as redacted fixtures (14 § Stage 3.3 step 6, 11 § Fixtures). HUMAN-RUN ONLY:
# the agent never runs it with keys (H2/H3, CLAUDE.md). Keys come from the environment only; this script never
# reads .env and never puts a key on a command line (curl reads the auth header from stdin).
#
#   scripts/record-fixtures.sh <provider>         record openai|anthropic|openrouter|deepseek|xai
#   scripts/record-fixtures.sh --verify-redacted [dir]   no key-shaped string under dir (default Tests/Fixtures)
#   scripts/record-fixtures.sh --self-test        offline: redact a canned body with fake keys, check the result
#   scripts/record-fixtures.sh --help
#
# Each response is written as Tests/Fixtures/providers/<provider>/<endpoint>.<case>.recorded.json in the envelope
# {"status", "headers", "body"} (Q-026): case `ok` for 2xx, else the status code. Only Content-Type and Retry-After
# are kept from the headers. Keys become sk-FIXTURE-<provider>-<last4>; org and project ids become org_fixture and
# proj_fixture (11). The marker <provider>/RECORDED holds the date (YYYY-MM-DD) on its first line.
set -uo pipefail
cd "$(dirname "$0")/.."

FIXTURES="Tests/Fixtures/providers"

usage() {
  cat <<'EOF'
usage: scripts/record-fixtures.sh <provider> | --verify-redacted [dir] | --self-test | --help

Environment variable per provider (the key is read from it, never from .env or the command line):
  openai      OPENAI_ADMIN_KEY            Admin key (Organization Owner creates it)
  anthropic   ANTHROPIC_ADMIN_KEY         Admin key (needs an Organization)
  openrouter  OPENROUTER_MANAGEMENT_KEY   Management (provisioning) key
  deepseek    DEEPSEEK_API_KEY            Standard key
  xai         XAI_API_KEY                 Standard key

Writes Tests/Fixtures/providers/<provider>/*.recorded.json and RECORDED, then runs --verify-redacted on them.
Review the files, then commit them with Verified.swift updated (13 § D-verified-providers).
EOF
}

# --- redaction (python3 -I: isolated, no site or cwd imports) --------------------------------------------------
# redact <provider> <status> <headers-file> <body-file> <out-file>; the live key, if any, arrives on stdin.
redact() {
  python3 -I - "$@" <<'PY'
import json, re, sys
provider, status, headers_path, body_path, out_path = sys.argv[1:6]
secret = sys.stdin.read().strip()

def fixture_key(value):
    tail = re.sub(r"[^A-Za-z0-9]", "", value)[-4:]
    return "sk-FIXTURE-%s-%s" % (provider, tail)

# 07's key patterns 2, 6, 5, 1 (most specific first, so each key is replaced whole), then header patterns 3 and 4;
# pattern 7, the exact live key, runs first of all.
KEY = [r"sk-ant-[A-Za-z0-9_\-]{8,}", r"sk-or-v1-[A-Za-z0-9]{8,}", r"xai-[A-Za-z0-9]{8,}", r"sk-[A-Za-z0-9_\-]{8,}"]
HEADER = r"""(?i)(authorization|x-api-key|x-goog-api-key)(["']?)\s*[:=]\s*(["']?)(?:[A-Za-z]+\s+)?[^\s"',}]+"""
BEARER = r"""(?i)bearer\s+[^\s"',}]{8,}"""

def scrub(text):
    if secret:
        text = text.replace(secret, fixture_key(secret))
    for pattern in KEY:
        text = re.sub(pattern, lambda m: m.group(0) if m.group(0).startswith("sk-FIXTURE-") else fixture_key(m.group(0)), text)
    text = re.sub(HEADER, lambda m: "%s%s: %s«redacted:header»" % (m.group(1), m.group(2), m.group(3)), text)
    text = re.sub(BEARER, "Bearer «redacted:token»", text)
    text = re.sub(r"\borg[-_][A-Za-z0-9]{6,}", "org_fixture", text)
    text = re.sub(r"\bproj_[A-Za-z0-9]{6,}", "proj_fixture", text)
    return text

raw = open(body_path, encoding="utf-8", errors="replace").read()
clean = scrub(raw)
try:
    body = json.loads(clean)
except ValueError:
    body = clean
keep = {"content-type", "retry-after"}
headers = {}
for line in open(headers_path, encoding="latin-1"):
    name, sep, value = line.partition(":")
    if sep and name.strip().lower() in keep:
        headers[name.strip()] = scrub(value.strip())
with open(out_path, "w", encoding="utf-8") as out:
    json.dump({"status": int(status), "headers": headers, "body": body}, out, indent=2, sort_keys=True, ensure_ascii=False)
    out.write("\n")
PY
}

verify_redacted() {
  local dir="${1:-Tests/Fixtures}"
  [[ -d "$dir" ]] || { echo "record-fixtures: no directory $dir"; return 0; }
  scripts/check-no-secrets.sh --root "$dir"
}

# --- self-test (offline) -----------------------------------------------------------------------------------------
self_test() {
  local scratch random key ant headers body out
  scratch="$(mktemp -d)"
  random="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40)"
  key="$(printf 'sk-%s-%s' admin "$random")"
  ant="$(printf 'sk-%s-%s' ant-admin01 "$random")"
  # Raw input outside the checked tree; only the redacted fixture goes under out/.
  headers="$scratch/in/headers"; body="$scratch/in/body"; out="$scratch/out/openai/costs.ok.recorded.json"
  mkdir -p "$scratch/in" "$scratch/out/openai"
  printf 'HTTP/2 200\r\ncontent-type: application/json\r\nset-cookie: session=%s\r\nopenai-organization: org-%s\r\n' \
    "$random" "$random" > "$headers"
  printf '{"data":[{"api_key_id":"key_1","note":"%s","other":"%s","auth":"Authorization: Bearer %s","project_id":"proj_%s","org":"org-%s"}]}' \
    "$key" "$ant" "$random" "$random" "$random" > "$body"
  printf '%s' "$key" | redact openai 200 "$headers" "$body" "$out" || { echo "self-test: redact failed"; return 1; }
  local tail4="${random: -4}"
  python3 -I - "$out" "$tail4" <<'PY' || { echo "self-test: envelope check failed"; cat "$out"; return 1; }
import json, sys
env = json.load(open(sys.argv[1]))
tail = sys.argv[2]
assert env["status"] == 200, env
assert env["headers"] == {"content-type": "application/json"}, env["headers"]
row = env["body"]["data"][0]
assert row["note"] == "sk-FIXTURE-openai-" + tail, row
assert row["other"] == "sk-FIXTURE-openai-" + tail, row
assert row["auth"] == "Authorization: «redacted:header»", row
assert row["project_id"] == "proj_fixture" and row["org"] == "org_fixture", row
assert row["api_key_id"] == "key_1", row
PY
  if grep -qF "$random" "$out"; then echo "self-test: random key body survived redaction"; return 1; fi
  verify_redacted "$scratch/out" || { echo "self-test: check-no-secrets flagged the redacted output"; return 1; }
  # And the guard itself must catch an unredacted body.
  cp "$body" "$scratch/out/openai/raw.json"
  if verify_redacted "$scratch/out" >/dev/null; then echo "self-test: an unredacted body passed --verify-redacted"; return 1; fi
  rm -rf "$scratch"
  echo "record-fixtures self-test: ok"
}

# --- recording ---------------------------------------------------------------------------------------------------
# fetch <provider> <endpoint> <url> <header-name> <scheme>: one GET, written as an enveloped, redacted fixture.
fetch() {
  local provider="$1" endpoint="$2" url="$3" header="$4" scheme="$5" tmp status case out
  tmp="$(mktemp -d)"
  # The auth header goes to curl on stdin (--config -), so it never appears in ps or the shell history.
  status="$(printf 'header = "%s: %s%s"\n' "$header" "$scheme" "$KEY_VALUE" |
    curl --silent --show-error --max-time 30 --config - "${EXTRA_HEADERS[@]}" \
      -H "User-Agent: TokenBe/record-fixtures (+https://github.com/nbencic/tokenbe)" \
      --dump-header "$tmp/headers" --output "$tmp/body" --write-out '%{http_code}' "$url")" || {
    echo "  $endpoint: request failed"; rm -rf "$tmp"; return 1; }
  if [[ "$status" =~ ^2 ]]; then case="ok"; else case="$status"; fi
  out="$FIXTURES/$provider/$endpoint.$case.recorded.json"
  printf '%s' "$KEY_VALUE" | redact "$provider" "$status" "$tmp/headers" "$tmp/body" "$out" || { rm -rf "$tmp"; return 1; }
  echo "  $endpoint: HTTP $status → $out"
  rm -rf "$tmp"
}

record() {
  local provider="$1" var now
  case "$provider" in
    openai) var=OPENAI_ADMIN_KEY ;; anthropic) var=ANTHROPIC_ADMIN_KEY ;; openrouter) var=OPENROUTER_MANAGEMENT_KEY ;;
    deepseek) var=DEEPSEEK_API_KEY ;; xai) var=XAI_API_KEY ;;
    *) usage; exit 2 ;;
  esac
  KEY_VALUE="${!var:-}"
  [[ -n "$KEY_VALUE" ]] || { echo "record-fixtures: set $var in your shell (see --help)"; exit 2; }
  mkdir -p "$FIXTURES/$provider"
  now="$(date -u +%s)"
  EXTRA_HEADERS=()
  echo "Recording $provider (02 endpoints) into $FIXTURES/$provider"
  case "$provider" in
    openai)
      local base="https://api.openai.com/v1/organization"
      fetch openai projects "$base/projects?limit=100" Authorization "Bearer " || return 1
      # The fixture holds proj_fixture; the keys call needs the first project's live id.
      local project
      project="$(curl_project_id "$base")"
      [[ -n "$project" ]] || { echo "  api_keys: no project found"; return 1; }
      fetch openai api_keys "$base/projects/${project}/api_keys?limit=100" Authorization "Bearer " || return 1
      fetch openai usage_completions "$base/usage/completions?start_time=$((now - 172800))&bucket_width=1h&group_by%5B%5D=api_key_id&group_by%5B%5D=model&group_by%5B%5D=service_tier" Authorization "Bearer " || return 1
      fetch openai costs "$base/costs?start_time=$((now - 604800))&group_by%5B%5D=api_key_id&group_by%5B%5D=line_item" Authorization "Bearer " || return 1
      ;;
    anthropic)
      local base="https://api.anthropic.com/v1/organizations" hour week
      EXTRA_HEADERS=(-H "anthropic-version: 2023-06-01")
      hour="$(date -u -r $((now - 172800)) +%Y-%m-%dT%H:00:00Z)"; week="$(date -u -r $((now - 604800)) +%Y-%m-%dT00:00:00Z)"
      fetch anthropic organization "$base/me" x-api-key "" || return 1
      fetch anthropic api_keys "$base/api_keys?limit=100&status=active" x-api-key "" || return 1
      fetch anthropic workspaces "$base/workspaces?limit=100" x-api-key "" || return 1
      fetch anthropic usage_report "$base/usage_report/messages?starting_at=$hour&bucket_width=1h&limit=48&group_by%5B%5D=api_key_id&group_by%5B%5D=model&group_by%5B%5D=service_tier" x-api-key "" || return 1
      fetch anthropic cost_report "$base/cost_report?starting_at=$week&group_by%5B%5D=workspace_id&group_by%5B%5D=description" x-api-key "" || return 1
      ;;
    openrouter)
      local base="https://openrouter.ai/api/v1"
      fetch openrouter key "$base/key" Authorization "Bearer " || return 1
      fetch openrouter credits "$base/credits" Authorization "Bearer " || return 1
      fetch openrouter keys "$base/keys?include_disabled=false&offset=0" Authorization "Bearer " || return 1
      ;;
    deepseek)
      fetch deepseek balance "https://api.deepseek.com/user/balance" Authorization "Bearer " || return 1
      ;;
    xai)
      fetch xai api_key "https://api.x.ai/v1/api-key" Authorization "Bearer " || return 1
      ;;
  esac
  printf '%s\nrecorded by scripts/record-fixtures.sh %s\n' "$(date -u +%F)" "$provider" > "$FIXTURES/$provider/RECORDED"
  unset KEY_VALUE
  if verify_redacted "$FIXTURES/$provider"; then
    echo "Done. Review $FIXTURES/$provider, add $provider to Verified.swift, then commit."
  else
    echo "record-fixtures: a key-shaped string survived redaction in $FIXTURES/$provider. Do NOT commit; fix and re-run."
    return 1
  fi
}

# The first project's live id (the recorded fixture holds proj_fixture instead).
curl_project_id() {
  printf 'header = "Authorization: Bearer %s"\n' "$KEY_VALUE" |
    curl --silent --max-time 30 --config - "$1/projects?limit=1" |
    python3 -I -c 'import json,sys; d=json.load(sys.stdin); print((d.get("data") or [{}])[0].get("id",""))'
}

case "${1:-}" in
  --help|-h|"") usage ;;
  --self-test) self_test ;;
  --verify-redacted) verify_redacted "${2:-}" ;;
  -*) usage; exit 2 ;;
  *) record "$1" ;;
esac
