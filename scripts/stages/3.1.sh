# Stage 3.1 — Network seam, error taxonomy, retry policy (14 § Stage 3.1). Sourced by scripts/verify-stage.sh.

net=Sources/TokenBeCore/Network
inventory=(
  $net/HTTPTransport.swift $net/URLSessionTransport.swift $net/PollError.swift $net/RetryPolicy.swift
  $net/FixtureTransport.swift $net/NetworkMonitor.swift
  Tests/TokenBeCoreTests/Support/StubTransport.swift Tests/TokenBeCoreTests/Support/SeededRNG.swift
  Tests/TokenBeCoreTests/PollErrorMappingTests.swift Tests/TokenBeCoreTests/RetryPolicyTests.swift
  Tests/TokenBeCoreTests/URLSessionTransportTests.swift Tests/TokenBeCoreTests/FixtureTransportTests.swift
  scripts/stages/3.1.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# Step 1–2: one seam; URLSession only behind it (04: TokenBeApp never touches URLSession).
check "HTTPTransport.send throws TransportError (typed)" grep -qF 'func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse' $net/HTTPTransport.swift
urlsession_only_in_transport() {
  ! grep -rnwE 'URLSession' Sources | grep -vE '^[^:]+:[0-9]+: *//' | grep -qv "^$net/URLSessionTransport.swift:"
}
check "URLSession used only in URLSessionTransport (04)" urlsession_only_in_transport
for setting in 'URLSessionConfiguration.ephemeral' 'timeoutIntervalForRequest = 15' 'timeoutIntervalForResource = 30' \
               'waitsForConnectivity = false' 'httpShouldSetCookies = false' 'urlCache = nil' \
               '"TokenBe/\(version) (+https://github.com/nbencic/tokenbe)"' 'maxBodyBytes = 20 * 1024 * 1024'; do
  check "URLSessionTransport: $setting" grep -qF "$setting" $net/URLSessionTransport.swift
done
# Step 3–4: 04's taxonomy verbatim; the retry constants of 04.
for case in 'case transport(URLError)' 'case auth(http: Int, body: String)' 'case rateLimited(retryAfter: Duration?)' \
            'case server(http: Int, body: String)' 'case decode(field: String, path: String)' \
            'case schemaDrift(unknownKeys: [String])' 'case providerRule(String)' 'case cancelled'; do
  check "PollError has $case (04)" grep -qF "$case" $net/PollError.swift
done
for constant in 'transientDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]' 'jitter = 0.25' \
                'rateLimitDefault = Duration.seconds(30)' 'retryAfterCap = Duration.seconds(300)' \
                'backoffCap = Duration.seconds(15 * 60)'; do
  check "RetryPolicy: $constant (04)" grep -qF "$constant" $net/RetryPolicy.swift
done
# Step 5: fixture transport is DEBUG-only; step 6: NWPathMonitor without a dispatch queue (R6).
check "FixtureTransport is compiled in DEBUG only" bash -c "head -n 1 $net/FixtureTransport.swift | grep -qx '#if DEBUG'"
check "no DispatchQueue in Network (R6)" bash -c "! grep -rqE 'DispatchQueue|\\.start\\(queue' $net"
check "app.network_changed emitted" grep -qF '.appNetworkChanged' $net/NetworkMonitor.swift
# 3.3 added record-fixtures.sh, so committed provider fixtures must pass its redaction check (R11, Q-026, Q-028).
check "Tests/Fixtures passes record-fixtures.sh --verify-redacted (R11)" scripts/record-fixtures.sh --verify-redacted
check "check-log-events.sh" scripts/check-log-events.sh
check "check-no-secrets.sh URL allowlist (14 Verify)" scripts/check-no-secrets.sh

for suite in PollErrorMappingTests RetryPolicyTests URLSessionTransportTests FixtureTransportTests NetworkMonitorTests; do
  check "suite $suite passed" suite_passed "$suite"
done
