# Stage 3.4 — OpenAI adapter on synthetic fixtures (14 § Stage 3.4). Sourced by scripts/verify-stage.sh.

oa=Sources/TokenBeCore/Providers/OpenAI
store=Sources/TokenBeCore/Store
fx=Tests/Fixtures/providers/openai
inventory=(
  $oa/DTOs.swift $oa/Normalizer.swift $oa/Probe.swift $oa/Client.swift Sources/TokenBeCore/Normalize/TokenClasses.swift
  Sources/TokenBeCore/Scheduling/Poller.swift $store/Repository+ProviderKeys.swift $store/Repository+Usage.swift
  $store/Repository+Cost.swift $store/Repository+Poll.swift Sources/TokenBeCore/Core/CoreStrings.swift
  Sources/TokenBeCore/Network/NoNetworkInTests.swift Tests/Fixtures/expected/normalize.csv
  Tests/TokenBeCoreTests/AdapterTests/OpenAITests.swift Tests/TokenBeCoreTests/NormalizerTests.swift
  Tests/TokenBeCoreTests/PollStateTests.swift Tests/TokenBeCoreTests/PollerTests.swift scripts/stages/3.4.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1: the synthetic fixtures of 14 (names per Q-029), envelope JSON, redacted, and never a RECORDED marker.
for name in projects.ok api_keys.ok usage_completions.ok usage_completions.page2 usage_completions.empty costs.ok \
            projects.401 costs.403 usage_completions.429 usage_completions.500; do
  check "fixture $name.synthetic.json is an envelope" python3 -I -c \
    "import json,sys; e=json.load(open(sys.argv[1])); assert isinstance(e['status'], int) and 'body' in e" \
    "$fx/$name.synthetic.json"
done
check "usage_completions.429 carries Retry-After" grep -qF '"Retry-After"' $fx/usage_completions.429.synthetic.json
check "usage_completions.ok has a second page" grep -qF '"next_page": "page2"' $fx/usage_completions.ok.synthetic.json
check "no RECORDED marker for openai (synthetic only, D-synthetic-fixtures)" test ! -e $fx/RECORDED
check "openai stays out of Verified (R13)" grep -qF 'public static let providers: Set<ProviderID> = []' Sources/TokenBeCore/Providers/Verified.swift
check "fixtures pass record-fixtures.sh --verify-redacted (R11)" scripts/record-fixtures.sh --verify-redacted
check "check-no-secrets.sh over fixtures, sources and build products (14 Verify)" scripts/check-no-secrets.sh

# Step 2: every snake_case field the DTOs decode is named in 02 (R2: never a field that is in neither 02 nor a fixture).
dto_fields_in_02() {
  local missing=0
  for field in $(grep -oE '= "[a-z_]+"' $oa/DTOs.swift | cut -d'"' -f2 | sort -u); do
    grep -qF "\`$field\`" docs/02-provider-apis.md || grep -qF "\"$field\"" docs/02-provider-apis.md || {
      echo "not in 02: $field"; missing=1; }
  done
  return $missing
}
check "DTO field names all appear in 02" dto_fields_in_02
check "unknown keys are collected, not fatal" grep -qF 'allKeys' $oa/DTOs.swift
check "decode failures map to PollError.decode(field:path:)" grep -qF 'return .decode(field: key.stringValue' $oa/DTOs.swift

# Step 3: 05's normalizer row 1 and its CSV rows.
check "normalizer clamps at 0 and logs normalize.negative" bash -c "grep -qF 'max(0, uncached)' $oa/Normalizer.swift && grep -qF '.normalizeNegative' $oa/Normalizer.swift"
check "normalize.csv has the openai rows" bash -c "[[ \$(grep -c '^openai,' Tests/Fixtures/expected/normalize.csv) -ge 4 ]]"

# Step 4: the probe's 401 message is 02's sentence verbatim; copy lives in CoreStrings.
probe_copy_matches_02() {
  local sentence='This is not an Admin key. Create one at platform.openai.com → Settings → Organization → Admin keys (Organization Owner only).'
  grep -qF "$sentence" docs/02-provider-apis.md && grep -qF "$sentence" Sources/TokenBeCore/Core/CoreStrings.swift
}
check "probe 401 copy is 02's sentence (R9)" probe_copy_matches_02

# Step 5: 02's query parameters and redacted last_raw.
for literal in '"api_key_id", "model", "service_tier"' '"api_key_id", "line_item"' '"bucket_width", value: "1h"' \
               'Bearer \(key)'; do
  check "Client sends $literal (02)" grep -qF "$literal" $oa/Client.swift
done
check "last_raw is redacted, then cut to 64 KiB (R8)" bash -c "grep -qF 'limit = 64 * 1024' Sources/TokenBeCore/Providers/RawBody.swift && grep -qF 'truncated(redactor.redact(text))' Sources/TokenBeCore/Providers/RawBody.swift"

# Step 6: the poller applies 04's policy and circuit.
for literal in 'circuitThreshold = 3' 'circuitDuration: TimeInterval = 24 * 3600' 'RetryPolicy.nextDelay' 'case .usage: 48 * 3600' \
               'case .cost: 7 * 86400' 'redactor.unregister(secret: key)'; do
  check "Poller: $literal" grep -qF "$literal" Sources/TokenBeCore/Scheduling/Poller.swift
done
for evt in pollStart pollOk pollRetry pollFailed pollRateLimited pollAuthFailed pollCircuitOpen pollCircuitClose \
           pollSchemaDrift pollUnknownKeys pollProviderRule pollWriteIncomplete normalizeNegative normalizeUnknownKeys; do
  check "event .$evt has a call site" bash -c "grep -rqF '.$evt,' Sources/TokenBeCore"
done
check "07 lists poll.write_incomplete (V2, Q-029)" grep -qF '`poll.write_incomplete`' docs/07-logging.md
check "check-log-events.sh (07 ↔ Evt)" scripts/check-log-events.sh

# Step 7: the repository aggregates join Repository.
check "Repository includes providerKeys, usage, cost and poll" grep -qxF '  & ProviderKeyRepository & UsageRepository & CostRepository & PollRepository' $store/Repository.swift

# PM-3.1-1: no real request leaves a test process. PM-3.3-2: adapter, routes and transport wired into the app.
check "URLSessionTransport installs the test guard" grep -qF 'NoNetworkInTests.isActive' Sources/TokenBeCore/Network/URLSessionTransport.swift
check "the guard is DEBUG-only" bash -c "grep -A3 'static let isActive' Sources/TokenBeCore/Network/NoNetworkInTests.swift | grep -qF '#if DEBUG'"
check "FixtureTransport routes OpenAI" grep -qF 'knownRoutes: [Route] = OpenAIAdapter.fixtureRoutes' Sources/TokenBeCore/Network/FixtureTransport.swift
check "AppEnvironment gets Transports.make(fixtureMode: settings)" grep -qF 'fixtureMode: current.debugFixtureMode' Sources/TokenBeApp/Startup.swift
check "AppEnvironment registers the OpenAI adapter" grep -qF 'ProviderRegistry(adapters: [OpenAIAdapter()])' Sources/TokenBeApp/Startup.swift
check "no provider call in tests: StubTransport/FixtureTransport only (R13)" bash -c "! grep -rn 'URLSessionTransport(version: \"[^\"]*\")' Tests | grep -v URLSessionTransportTests.swift"

for suite in OpenAITests OpenAIProbeTests NormalizerTests PollStateTests PollerTests URLSessionTransportTests \
             FixtureTransportTests RepositoryAccountTests; do
  check "suite $suite passed" suite_passed "$suite"
done
