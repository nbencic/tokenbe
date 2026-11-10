# Postmortem — Stage 3.4 OpenAI adapter (on synthetic fixtures)
Date: 2026-11-10 · Branch: s3.4-openai-adapter · PR: #14 · Planned size: L · Commits: 8

## Outcome
Every OpenAI endpoint in 02 is decoded, normalized and written to the database. Nothing is visible to the user yet: no screen creates an account until 3.5.
- **Fixtures.** Ten synthetic envelopes under `Tests/Fixtures/providers/openai/`, built only from 02's field names. They cover a two-page usage response, an empty page, 7 days of cost, and 401, 403, 429 and 500 cases named `<endpoint>.<status>` like the recorder's output. There is no `RECORDED` marker, so OpenAI stays out of `Verified`.
- **DTOs.** Lenient `Decodable` types. Keys 02 does not list are collected and logged once per UTC day: `poll.unknown_keys` for keys in a page, `normalize.unknown_keys` for keys inside a usage result. A missing required field fails as `PollError.decode(field:path:)`. Cost amounts decode as `Decimal` from the JSON text, never through `Double`.
- **Normalizer.** 05's row 1. A negative uncached input is clamped to 0 and logged `normalize.negative`. `Fixtures/expected/normalize.csv` has the four OpenAI rows, computed by hand.
- **Probe.** 02's four steps.
  - Step 1 failing ends the probe: on a 401 with 02's admin-key sentence, on a 403 with a missing-scope message.
  - A 401/403 on steps 2–4 turns off that step's capability and keeps the redacted body.
  - Offline, 429, 5xx or an unreadable body ends the probe with a message.
  - Copy is in `Core/CoreStrings.swift`. Only the 401 sentence comes from 02; the rest is authored (Q-029).
- **Client.**
  - Keys: projects, then each project's api_keys, upserted into `provider_key`.
  - Usage: 1 h buckets over the last 48 h, grouped by api_key_id, model and service_tier, one page per call. Each page writes its rows and its cursor in one transaction, so an interrupted sequence resumes from the next page.
  - Cost: the last 7 days, paged. Each UTC day becomes per-key rows, per-line-item rows and one `total` row, in cents. A re-fetch replaces each returned day whole.
- **Poller.** `runOnce(account, job)` does one job end to end:
  - reads the key and registers it for redaction;
  - applies 04's retry policy on a `Clock` with a seeded generator in tests;
  - updates `poll_state`: attempt, success, failure, consecutive failures, the 24 h circuit after 3 auth failures, cursor, and a `last_raw` that is redacted and at most 64 KiB;
  - emits every `poll.*` event of 07.
- **V2.** A usage page whose stored rows don't add up to its results is rolled back and logged `poll.write_incomplete`, a new event added to 07 (Q-029).
- **Wiring (PM-3.3-2).**
  - `AppEnvironment` holds `Transports.make(fixtureMode: settings.debugFixtureMode, …)` and a `ProviderRegistry` with the OpenAI adapter.
  - `FixtureTransport` serves the OpenAI routes, with `page=<cursor>` selecting a later page.
- **No real network in tests (PM-3.1-1).** In a test process, a `URLSessionTransport` built without stub protocols fails every request at once. A test proves this on the production initializer.
- **Verification.** 223 Core tests in 43 suites pass, 43 tests more than 3.3. New suites: OpenAITests, OpenAIProbeTests, NormalizerTests, PollStateTests and PollerTests. Core line coverage is 93.7 %.

DoD D1–D3, D5, D9 and D11 are met; D12 by the PR's CI; D13 by this file.

## What went as planned
- The orientation spike ran before any code was written. It showed that a globally registered `URLProtocol` never reaches `URLSessionTransport`'s ephemeral session: the request went to real DNS. It also showed that `JSONDecoder` decodes `Decimal` exactly from the number text (`0.1`, 20-digit values). Both shaped the design.
- Each design choice was settled before its code and checked against the docs in a review: fixture names, cursor format, cost grouping, probe outcome, V2 handling and the test guard. Q-029 itself was written in the docs commit, after both code commits, not before them.
- Stage scripts were grepped before the `Repository` typealias grew. `2.1.sh`'s exact-line check still holds, and `3.4.sh` checks the new line.
- The synthetic fixtures passed `record-fixtures.sh --verify-redacted` and `check-no-secrets.sh` as soon as they were written (R11). Fake keys in tests are built at run time.
- The Release build (warnings as errors) passed, and `check-no-secrets.sh` was clean over its products (PM-3.3-4).
- The full Core suite looped 50 times (PM-1.2-3): 50 of 50 passed. Lint ran standalone before verify (PM-1.3-5).

## What went wrong
1. **Three test failures on the first full run, all in the tests.**
   - The guard test compared a `URLError` that carries a userInfo message; the fix compares the code.
   - The cost-paging test reused a day the second page also returned, which made duplicate primary keys. The test now uses another day, and the adapter merges buckets that share a UTC day.
   - The circuit test expected an unquoted body. `FixtureEnvelope` re-serializes a JSON-string body with its quotes.

   Cost: one targeted re-run.
2. **About 40 lint findings on the first lint run:**
   - nesting deeper than one level in the DTOs and the probe;
   - parameter counts over five (`recordPollFailure`, `get`, the poller's failure paths);
   - one large tuple;
   - the `ok` enum case, renamed `succeeded`;
   - one-letter test names.

   The fixes: top-level DTO types, `CircuitRule` and `Poller.Run` parameter structs, the response type inferred from the call site, a `CostGroup` struct, and the probe split into `OpenAIProbe` with a `scope` helper. Cost: one rebuild and one re-lint. Lint had not run on any slice before the tests were written, which is why the findings piled up.
3. **The no-network guard was off on CI, and two requests reached `api.openai.com`.** The guard was keyed on a property of the local runner, and the guard test aimed at a real provider URL. Either choice alone would have been harmless; together, a guard failure became a real request. See CI run 2 under Verify and CI failures, and PM-3.4-9.
4. **Mixed failure classes could open the circuit.** `consecutive_failures` counted every class, so `500, 500, 401` opened the 24 h circuit, but 04 requires 3 consecutive **auth** failures. The final review before merge caught it; no test or check did, because `PollStateTests.circuit` only covered all-server and all-auth runs. Fix: a change of class restarts the streak at 1 (Q-029). A table test covers `500,500,401`, `401,500,401,401`, `401,401,401` and `500,401,401,401`. Cost: one fix, plus a re-verify and a re-run of CI.
5. **Redundant protocol conformances.** The four new repository extensions declared their protocol again, which `Repository` already includes. The build rejected them, as in 2.2. Cost: one rebuild.

## Verify and CI failures
- Verify run 1: FAIL at `3.2 KeychainKeyStoreIntegrationTests ran (not skipped)`, after 460 checks. The suite had run. `3.2.sh` looked for `<skipped` in the two lines after the test case, and this run's parallel order put `FixtureDBTests.regenerate()` there, which is skipped by design. The check now asserts that the test case's element is self-closing, so it has no `<skipped/>` or `<failure>` child (PM-3.4-6). No product code changed.
- Verify run 2: `STAGE 3.4 OK`, 603 checks across stages 0.1–3.4 and D13, the UI suites included.
- CI run 1 (PR #14, head dcbadc1): `build-test` failed in the Release build. Swift 6.1, the CI compile gate (PM-0.5-1), rejected `Poller.retrying<T>` with "non-sendable result type 'T' cannot be sent from nonisolated context". The local Swift 6.4 accepted it. Fix: `T: Sendable`. The local toolchain can't reproduce 6.1 diagnostics, so the Swift 6.1 gate stays CI's job (PM-3.4-7).
- Verify run 3 (after the circuit and `Sendable` fixes): FAIL at `1.2 tb.ui.dashboardRange = 30d in the UI-test suite after the test`, after 236 checks.
  - `DashboardShellUITests` passed, including its own relaunch check that `30 d` persisted. Afterwards, though, the UI-test suite held `7d`. No UI test clicks `7 d` after that test.
  - The UI test order and steps matched runs 1 and 2, which passed this check. This stage changed no Dashboard or Settings code, so a later test's Dashboard toggle (`SettingsGeneralUITests`, ⌃⌥K/⌃⌥T) most likely races the range binding now and then.
  - Re-run unchanged; carried as PM-3.4-8.
- Verify run 4 (on ad6f9ad): stopped before the end, when CI run 2 failed. The verify runs before it never reached a real host: locally, `swift test` loads XCTest, so the guard was on.
- CI run 2 (PR #14, head ad6f9ad): `build-test` failed in `Test TokenBeCore`. **On the CI runner the no-network guard was off.** That runner does not load XCTest, and `isActive` keyed on `XCTestCase`. The guard's own test then sent two real requests to `https://api.openai.com/v1/organization/projects`, one from the production initializer and one from `Transports.make(fixtureMode: false)`, and both got HTTP 401.
  - No key was involved: the request had no `Authorization` header, and no secret exists in CI. Still, it broke R13 ("never call a provider API during `swift test`").
  - Fixes:
    - the guard is on in every DEBUG process whose main bundle is not an `.app` (`isTestProcess`, with its own test);
    - the guard test stops at `#require(isActive)` before sending;
    - it aims at `https://guard.invalid/…`, so a failed guard can never reach a provider again;
    - it checks the guard's counter, which a DNS failure would not move.
  - `3.4.sh` checks that the guard test aims at `.invalid` (PM-3.4-9).
- Verify run 5 (on 9d9f5bd): `STAGE 3.4 OK`, 605 checks across stages 0.1–3.4 and D13, the UI suites included. The UI-test suite held `tb.ui.dashboardRange = 30d` this time (PM-3.4-8 stays open).
- CI run 3 (PR #14, head 9d9f5bd): `build-test` passed: build, 223 tests, coverage gate, lint, event-table check, app build and the secret guard. The guard tests ran and passed on CI's runner. This file's final update re-runs CI before the merge.

## Deviations from the docs
- 14 step 1, 11 § Fixtures: the error fixtures are `projects.401`, `costs.403`, `usage_completions.429` and `usage_completions.500`, not `auth.401` and the rest. Page 2 is `usage_completions.page2`. `FixtureTransport` can only serve `<endpoint>.<case>` names (Q-029). 14 and 11 are reworded.
- 07: new event `poll.write_incomplete` for V2. 04 requires a logged error, and 07 had no event for it (Q-029).
- 14 Inventory additions:
  - `Network/NoNetworkInTests.swift` (PM-3.1-1);
  - `Logging/EventLog.swift` (`EventLog`, `DailyOnce`);
  - `Providers/RawBody.swift` (redact then truncate, `ResponseTrace`).
- Changed outside the inventory:
  - `ProviderAdapter.swift`: `PollContext.trace`, `UsagePage.expected`.
  - `Database.swift`: `StoreError.writeIncomplete`.
  - `URLSessionTransport.swift`: the guard. `NoNetworkInTests` needs no `@unchecked Sendable`: nothing requires it to be `Sendable` (R6).
  - `FixtureTransport.swift`: `knownRoutes` and page cases.
  - `AppEnvironment.swift` and `Startup.swift`: the wiring.
  - `StubTransport.swift`: `replace`.
  - `MemoryRepository.swift`: the new aggregates.
  - `2.1.sh`: a comment. `3.2.sh`: the skipped-test check (PM-3.4-6).
  - Postmortems 3.1 and 3.3: carry-forward statuses.

## Judgment calls
- Q-029, covering:
  - fixture names and the page-case rule;
  - the implicit page wrappers, plus required and optional fields;
  - usage row merging and the provisional rule;
  - the cursor format `<start_time> <next_page>`;
  - cost grouping, rounding, the zero total and day replacement;
  - key status;
  - probe outcome and authored copy;
  - poller lookbacks, `acct`, error classes, retry logging, `last_raw` on decode failure, circuit events and balance jobs;
  - V2 in every build;
  - the test guard;
  - wiring at launch.

## Carry-forward actions
- PM-3.4-1 · agent · 3.5 · Onboarding treats `ProbeResult.humanMessage == nil` as success, and shows the message otherwise (Q-029). `Transports.make` cannot pass `cases`, so fixture mode always serves `ok`. 3.5's UI tests for the 401 and wrong-key paths need a DEBUG way to choose a case, for example a test-root env var naming `openai/projects=401`; log the choice in a Q. The Keys & apps table wants "created" and "last used". OpenAI's `created_at`/`last_used_at` are decoded, but 03's `provider_key` has no columns for them, so log a Q (a migration, or show `first_seen_at`/`last_seen_at`).
- PM-3.4-2 · agent · 3.6 · Recorded fixtures will carry keys 02 does not list, such as `object` on usage results and `has_more`/`first_id` on lists. They will show up as `poll.unknown_keys`/`normalize.unknown_keys`. Add each confirmed key to 02 and to the DTO in the same PR. Check the real error-body shape, and the format of `redacted_value`.
- PM-3.4-3 · agent · 4.x pricing · `usage_bucket.est_cost_cents` is NULL and `unpriced` is 0 for provider rows. The pricing stage reprices them (`price.repriced`).
- PM-3.4-4 · agent · DeepSeek stage · A balance-capable account's `balance` job fails as `providerRule("<p>_balance_not_stored")` until `Repository+Balance` and the poller's write exist.
- PM-3.4-5 · agent · process · Run `swiftlint --strict` after each implementation slice, not only before verify.
- PM-3.4-7 · agent · process · Generic helpers that cross actor or task boundaries get `Sendable` constraints from the start. Swift 6.1, CI's gate, is stricter than the local toolchain here. After pushing, read CI's Release-build step first.
- PM-3.4-8 · agent · 4.2 (next Dashboard stage) · Find out what wrote `tb.ui.dashboardRange = 7d` after `DashboardShellUITests` in verify run 3. Suspects: the Dashboard that `SettingsGeneralUITests` opens with the shortcut, or the segmented picker taking keyboard input. Then make `1.2.sh`'s check independent of later suites, for example by having the Dashboard test write its own marker.
- PM-3.4-9 · agent · process · A test that proves a guard must never send to a real provider host, even when the guard fails: use `.invalid` hosts and `#require` the precondition before acting. Runner-dependent detection (XCTest loaded, process names) must be tested on CI's runner, not only locally. Closed here for the network guard.
- PM-3.4-6 · agent · process · Checks on xunit results look at one `<testcase>` element, never at "the next N lines". Swift Testing's order is parallel, so neighbours change from run to run. Closed in this stage for `3.2.sh`; follow the rule in new stage scripts.
- Earlier actions targeting 3.4:
  - PM-3.1-1: closed (5c141ad).
  - PM-3.3-2 and PM-3.1-3: closed (5c141ad).
