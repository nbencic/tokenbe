# Stage 0.5 — CI & secret/URL guards (14 § Stage 0.5). Sourced by scripts/verify-stage.sh.

for f in .github/workflows/ci.yml scripts/check-no-secrets.sh scripts/coverage-gate.sh scripts/stages/0.5.sh; do
  check "non-empty $f" test -s "$f"
done
for step in "swift build -c release -Xswiftc -warnings-as-errors" "swift test --enable-code-coverage" \
  "scripts/coverage-gate.sh" "swiftlint --strict" "scripts/check-log-events.sh" "scripts/check-no-secrets.sh" \
  "-configuration Release" "CODE_SIGNING_ALLOWED=NO" "runs-on: macos-15" "Xcode_16"; do
  check "ci.yml runs: $step" grep -qF -- "$step" .github/workflows/ci.yml
done

check "build-release (warnings as errors)" scripts/run.sh build-release
coverage() { swift test --enable-code-coverage >/dev/null 2>&1 && scripts/coverage-gate.sh 97; }
check "coverage gate ≥ 97 % (TokenBeCore lines, Q-035)" coverage
check "check-no-secrets.sh on the repository and build products" scripts/check-no-secrets.sh

# The guard must actually catch things: plant a key, a bearer token and an off-list URL in a scratch tree.
guard_self_test() {
  local scratch out body
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/Sources" "$scratch/Tests/Fixtures"
  body="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
  printf 'let u = URL(string: "https://evil.example.com/x")\nlet ok = URL(string: "https://api.openai.com/v1")\n' > "$scratch/Sources/A.swift"
  printf '{"key":"sk-proj-%s"}\n' "$body" > "$scratch/Tests/Fixtures/leak.json"
  printf 'Authorization: Bearer %s\n' "$body" > "$scratch/headers.txt"
  printf '{"key":"sk-FIXTURE-openai-ab12"} prefix sk-ant-admin01-\n' > "$scratch/Tests/Fixtures/ok.json"
  out="$(scripts/check-no-secrets.sh --root "$scratch")" && { echo "guard passed a planted secret"; return 1; }
  grep -q "leak.json" <<<"$out" && grep -q "headers.txt" <<<"$out" && grep -q "evil.example.com" <<<"$out" \
    && ! grep -q "ok.json" <<<"$out" && ! grep -q "api.openai.com" <<<"$out" || { echo "$out"; return 1; }
  rm -rf "$scratch"
}
check "check-no-secrets.sh catches planted key, token and URL (and only those)" guard_self_test
check ".env is git-ignored" git check-ignore -q .env
