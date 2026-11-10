# Postmortem — Stage 3.1 Network seam, error taxonomy, retry policy
Date: 2026-11-10 · Branch: s3.1-network · PR: #11 · Planned size: M · Commits: 4

## Outcome
Every HTTP request of TokenBe now has one way out, and every failure has one name. Nothing is visible to the user yet.
- **`HTTPTransport`** is the seam (14 § 0.3), with a typed `throws(TransportError)`.
- **`URLSessionTransport`** sends through an ephemeral session:
  - timeouts of 15 s per request and 30 s per resource;
  - no waiting for connectivity, no cookies, no cache;
  - 02's `User-Agent: TokenBe/<version> (+https://github.com/nbencic/tokenbe)` on every request;
  - bodies read up to 20 MiB, checked both on `Content-Length` and while streaming.
- **`PollError`** is 04's enum verbatim. `PollError.from` classifies responses:
  - 401/403 → `auth`;
  - 429 → `rateLimited`, with `Retry-After` as seconds or an HTTP-date;
  - 5xx → `server`;
  - any other non-2xx → `providerRule` (never retried);
  - transport failures → `transport`, `cancelled`, or `decode` for an oversized body.
- **`RetryPolicy`** is 04's policy as pure functions:
  - `transport`/`server` wait 2 s, 4 s, 8 s ± 25 %, with injected RNG;
  - `rateLimited` gets one retry after `Retry-After` (capped at 300 s, default 30 s);
  - `auth`, `decode`, `schemaDrift`, `providerRule` and `cancelled` never retry;
  - backoff between attempts is interval × 2ⁿ, capped at 15 min.
- **`FixtureTransport`** (DEBUG only) answers from `Tests/Fixtures/providers` in the `{status, headers, body}` envelope (Q-026). `Transports.make(fixtureMode:version:)` honours 09's `tb.debug.fixtureMode`.
- **`NWPathMonitorAdapter`** reports reachability, consumed as an `AsyncSequence` with no dispatch queue (R6). It logs `app.network_changed {online, interface}` on each transition.
- **Verification.** 163 Core tests pass, 27 of them new in 5 suites: PollErrorMapping, RetryPolicy, URLSessionTransport, FixtureTransport and NetworkMonitor. No request leaves the machine: `StubURLProtocol` answers in-process, keyed by a unique host per test.

DoD D1–D3, D9 and D11 are met; D12 by the PR's CI; D13 by this file.

## What went as planned
- The Release build with warnings as errors (the Swift 6.1 gate, PM-0.5-1) compiled the whole Network module on the first try, including typed throws and the `NWPathMonitor` `AsyncSequence`.
- Before coding, the earlier stage scripts were grepped for prohibitions on networking code. None existed, so no regression check had to change (unlike 2.2's `1.3.sh`).
- No fixture file was committed (R11). Every fixture test writes into a `TempDirectory`.
- Full Core suite looped 50 times (PM-1.2-3): 50 of 50 passed.
- `check-no-secrets.sh` (the URL allowlist of 14's Verify) passed. The only URL literal in Sources is the allowlisted `github.com/nbencic/tokenbe` in the User-Agent.

## What went wrong
1. **Two test compile errors.**
   - `#expect(value.mutatingCall())` cannot compile, because the macro passes the receiver as an immutable `$0`. The calls were collected first and then compared.
   - A `catch` clause in a `do` block that mixes `try #require` with typed throws binds `any Error`, so the error had to be cast to `TransportError`.

   Cost: one test build.
2. **Nine SwiftLint violations on the first lint.**
   - `optional_data_string_conversion`: `String(decoding:as:)` replaced by the failable initializer, with an explicit fallback in `PollError`.
   - `static_over_final_class` in the `URLProtocol` stub.
   - One short identifier.

   Lint ran standalone before verify (PM-1.3-5), so it cost no verify run.
3. **Verify run 1 stopped at 0.4's UI tests: `Timed out while enabling automation mode`.** The screen had locked during the run (`IOConsoleLocked` was `true` at the failure). It was unlocked when the run started. Every 3.1 check passed when run standalone. The full verify was re-run once the console was unlocked. A run that keeps only the system awake (`caffeinate -i`) does not stop the display from sleeping and the screen from locking. Verify now uses `caffeinate -d` too (PM-3.1-5).

## Verify and CI failures
- Verify run 1: 148 checks passed through stage 0.4's builds. Then `UI tests (LaunchSmokeTests)` failed: the runner could not enable automation mode because the screen was locked (item 3). The 3.1 checks run standalone (static checks and the five suites) all passed.
- Verify run 2, after the owner unlocked the screen (about 8 min later; a watcher started the run on unlock and kept the display awake with `caffeinate -d`): `STAGE 3.1 OK`, 454 checks across stages 0.1–3.1 and D13, the UI suites included.
- CI: PR #11 `build-test` passed on the first run (6 m 19 s) on Xcode 16.4 / Swift 6.1: build, tests, coverage gate, lint, event-table check, app build and the secret guard. This was the first 6.1 compile of the typed throws and the `NWPathMonitor` `AsyncSequence`.

## Deviations from the docs
- 14 § Stage 3.1 step 3: `PollError.from(status:body:urlError:)` → `from(_ response:now:)` and `from(_ transportError:)`, because `Retry-After` needs the headers. 14 is reworded (Q-026).
- 14 step 5: the "scenario name" of `tb.debug.fixtureMode` → 09's Bool plus a per-endpoint case (R1: 09 wins). 14 is reworded (Q-026).
- 14 inventory: `Tests/Support/{StubTransport,SeededRNG}.swift` → `Tests/TokenBeCoreTests/Support/`, the SwiftPM test target, as Q-024 did for 2.1. 14 is corrected.
- 11 § Fixtures and `Tests/Fixtures/README.md`: the fixture envelope is added (Q-026).
- 14 § 0.3 lists `NetworkMonitor` under 4.1, while 3.1 step 6 builds it. The protocol and the production adapter are built now; the test double and the wiring come with the 4.1 consumer (Q-026).
- 14 Tests: `FixtureTransportTests` and `NetworkMonitorTests` are added to 3.1's list.

## Judgment calls
- Q-026, covering:
  - the fixture envelope and its location;
  - Bool fixture mode with per-endpoint cases;
  - `providerRule` for other non-2xx statuses, and `decode` for oversized bodies;
  - translation-only catches in the transport (the poller logs);
  - no `AppEnvironment` or `Startup` wiring until the first consumer;
  - `NWPathMonitor` as an `AsyncSequence`;
  - the `interface` names, and why the first status is not logged;
  - 11's suite-wide guard carried to 3.4.

## Carry-forward actions
- PM-3.1-1 · agent · 3.4 · 11 requires a suite-wide guard: "a URLProtocol stub asserts zero real requests and fails the suite otherwise". Adapters first send in 3.4. Add the guard there, for example a test-target `URLSessionTransport` factory that always installs the stub, plus a `3.4.sh` grep that bans a bare `URLSessionTransport(version:)` followed by `send` in Tests.
- PM-3.1-2 · agent · 3.6 · `scripts/record-fixtures.sh` writes each response in the `{status, headers, body}` envelope of 11 § Fixtures (Q-026), so recorded files load through `FixtureEnvelope`.
- PM-3.1-3 · agent · 3.3/3.4 · Wire `Transports.make(fixtureMode: settings.debugFixtureMode, version:)` into `AppEnvironment` with the first adapter, and add each adapter's routes to `FixtureTransport.knownRoutes`.
- PM-3.1-4 · agent · 4.1 · `ManualNetworkMonitor` and the `NWPathMonitorAdapter` wiring, with `sched.skip reason=offline`.
- PM-3.1-5 · agent · process · Run verify under `caffeinate -i -d`, keeping the display awake as well. `-i` alone let the screen lock mid-run and cost one verify run.
- Earlier actions targeting 3.1: none. Phase 2's risk notes are addressed: the host allowlist passes, and no provider is called during `swift test`. The second is guarded per test now; the suite-wide guard is PM-3.1-1.
