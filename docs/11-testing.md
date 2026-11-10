# 11 — Testing

Framework: Swift Testing (`import Testing`) for Core; XCTest/XCUITest for the `TokenBeUITests` target. **No pixel snapshots** (D-no-pixel-snapshots): UI state is asserted through accessibility identifiers and texts. All tests run offline; the network is never touched in `swift test` (a `URLProtocol` stub asserts zero real requests and fails the suite otherwise).

Fixture naming: `<endpoint>.<case>.recorded.json` = captured from the live API by `scripts/record-fixtures.sh` (redacted); `<endpoint>.<case>.synthetic.json` = authored from `02` field lists for development and for error cases that cannot be recorded (429, 5xx). A provider is **verified** only when `Tests/Fixtures/providers/<p>/RECORDED` exists (`VerifiedProvidersTests`).

## Fixtures (`Tests/Fixtures/`)

```
Fixtures/
├── providers/<provider>/<endpoint>.<case>.json     # recorded by scripts/record-fixtures.sh in Milestone 0, redacted
│   e.g. openai/usage_completions.ok.json, openai/usage_completions.empty.json, openai/costs.ok.json,
│        openai/api_keys.ok.json, openai/auth.401.json, openai/rate_limit.429.json,
│        anthropic/usage_report.ok.json, anthropic/usage_report.lagging.json, anthropic/cost_report.ok.json,
│        anthropic/api_keys.ok.json, anthropic/no_org.403.json, anthropic/credit_low.400.json,
│        openrouter/credits.ok.json, openrouter/key.ok.json, openrouter/keys.ok.json,
│        deepseek/balance.ok.json, deepseek/balance.unavailable.json, deepseek/balance.cny.json,
│        xai/api_key.ok.json, xai/api_key.no_balance.json
├── harness/
│   ├── valid_500.jsonl                 # 500 lines, 3 apps, 2 providers, 12 duplicates
│   ├── partial_write.jsonl             # last line has no trailing newline
│   ├── bad_version.jsonl, bad_json.jsonl, unknown_provider.jsonl, too_long_line.jsonl, future_ts.jsonl
│   └── openrouter_cost_cents.jsonl
├── prices/litellm.snapshot.json        # trimmed to the models used in tests + one `mode: embedding` entry + one zero-price entry
├── db/
│   ├── schema_v1.sqlite                # created by migration 001 with representative rows
│   └── corrupt.sqlite                  # deliberately truncated
└── expected/
    ├── normalize.csv                   # provider,case,inputUncached,cacheWrite5m,cacheWrite1h,cacheRead,output,reasoning,requests
    ├── pricing.csv                     # provider,model,classes…,expected_cents,unpriced
    └── ledger.csv                      # remaining_cents,burn7d,burnToday,floor,expected_runway_min_s,expected_band
```
Every `providers/` file is one response in an envelope (Q-026): `{"status": 429, "headers": {"Retry-After": "12"}, "body": <the provider's JSON>}`. `headers` may be omitted. "Field names strictly from `02`" applies to `body`. `FixtureTransport` and `StubTransport` read files through the same loader (`FixtureEnvelope`), and `scripts/record-fixtures.sh` writes the same shape.

Redaction in fixtures: every key replaced with `sk-FIXTURE-<provider>-<last4>`; org/project ids replaced with `org_fixture`, `proj_fixture`; amounts kept real.

## Unit tests (one file per module; names fixed)

| File | Must cover |
|---|---|
| `NormalizerTests` | every row of `expected/normalize.csv`; negative-input clamp logs `normalize.negative`; missing required key → nil + `normalize.failed`. |
| `PriceLookupTests` | 6 lookup steps each hit; `mode != chat` ignored; zero price → unpriced (V5); override beats feed; date-suffix strip; `-latest` fallback. |
| `CostFormulaTests` | `expected/pricing.csv`; 1h cache write; `_above_200k` fields present in feed but NOT applied (05); fallback multipliers logged. |
| `LedgerTests` | `expected/ledger.csv`; `M ≥ remaining → unknown`; auto-reload override → watch; negative remaining clamps to 0 + critical; burn_today gates (≥2 h, ≥$0.01); fewer than 2 closed days → burn_7d nil. |
| `BandTransitionTests` | writes `band_state` row and `ui.band_change` log on change only (no row when unchanged). |
| `AttributionTests` | split (Σ apps == key total, remainder to largest), substitute, inferred (single app, no topup), never-add. |
| `SchedulerTests` | uses `TestClock`: due ordering, tolerance coalescing (two jobs due within 5 s run in one wake), backoff sequence 2/4/8 ±25 % with seeded RNG, 429 Retry-After honored and capped at 300 s, auth ×3 → circuit 24 h, decode no-retry, Low Power ×4, clock jump >30 s reschedules, pause/resume. |
| `PollStateTests` | consecutive_failures, circuit_open_until, cursor persistence, last_raw ≤ 64 KiB and redacted. |
| `AdapterTests/<Provider>` | for each fixture case: decode → normalized rows → DB rows count and values; probe sequence returns the exact human message strings from 02 for 401/403/400/429 fixtures; unknown JSON keys logged once. |
| `IngestTailerTests` | partial line not consumed; offset persisted in same transaction (inject failure after insert → both roll back); inode change → offset 0; truncation → offset 0; dedup; conflict logged; bad file → rejected/; counters. |
| `RedactorTests` | 7 patterns; real-shaped fake keys; in-memory key exact match; output never contains > last 4 chars. |
| `LogSinkTests` | NDJSON parseable; key order; rotation at 50 MiB (use 50 KiB override for test); retention deletion; overflow drop counter emits `app.log_dropped`. |
| `SettingsTests` | every `SettingsKey` has default; clamp + log; `critical < low < watch` repair; reset keeps `onboardingDone`. |
| `MigrationTests` | fresh DB → v1; `schema_v1.sqlite` opens and migrates to current; `quick_check` ok; corrupt.sqlite → moved aside, fresh DB created, `db.corrupt` logged; backup restore path. |
| `RetentionTests` | hourly→daily roll-up after 90 d preserves Σ cents and Σ tokens exactly; monthly roll-up likewise; harness_event purge after roll-up. |
| `FormattersTests` | money (cents, hide/show cents, CN¥, ≈ ±), runway strings, token abbreviations, freshness strings; all locale-pinned to `en_US_POSIX` AND `de_DE` (separator check). |
| `KeyStoreTests` | unit tests on `InMemoryKeyStore`; `KeychainKeyStoreIntegrationTests` (tag `.keychainIntegration`, service `dev.bathyon.tokenbe.test`): write/read/overwrite/delete + attribute assertions (SEC-2); skipped when the keychain is locked. |
| `StartupSequenceTests` | log order of `04 § Startup sequence` for the steps implemented so far (grows per stage of `14`). |
| `VerifiedProvidersTests` | `Verified` set ↔ `RECORDED` markers, both directions. |
| `StringsAuditTests` | every quoted copy string in `08` exists in `Strings.swift`. |
| Stage-introduced files (`14 § 13.6`) | `CrashHandlerTests`, `LogRecordTests`, `ObservationTests`, `PollErrorMappingTests`, `RetryPolicyTests`, `URLSessionTransportTests`, `ProviderIDTests`, `PollerTests`, `AccountLifecycleTests`, `CoordinatorTests`, `FreshnessTests`, `DailyActivityTests`, `PriceFeedTests`, `RepriceTests`, `BurnTests`, `AlertPolicyTests`, `GlyphStateTests`, `OverviewTotalsTests`, `LineParserTests`, `DriftTests`, `CacheSavingsTests`, `ChartDataTests`, `CSVExporterTests`, `ExportImportTests`, `DiagnosticsBundleTests`, `UpdateCheckerTests` — each covers exactly what its stage in `14` lists. |

## E2E (XCTest UI tests + fixture mode `tb.debug.fixtureMode=true`)
| ID | Scenario | Pass criteria |
|---|---|---|
| E2E-1 | Fresh launch, no accounts | Onboarding sheet shown; popover shows Empty state; `app.launch` logged. |
| E2E-2 | Add OpenAI with fixture key | Probe passes with fixture; Step 3 shows `anchored`; set anchor $100; popover card shows `≈ $100 ± …`; runway shows Day-1 collecting. |
| E2E-3 | Harness ingest | copy `valid_500.jsonl` into ingest/ in 5 bursts while running → 488 harness_event rows (500−12 dup); `kill -9` after burst 3, relaunch, copy remaining → still 488; By-app table lists 3 apps; `rejected/` receives `bad_json.jsonl`. |
| E2E-4 | Band + notification | drive fixture costs so runway < 2 d → card red, glyph notch, one notification, `ui.band_change` logged; drive back to healthy → no notification. |
| E2E-5 | Stale/offline | stub transport to fail → after 3× interval cards dim, glyph dashed, banner "Offline"; recover → normal within one interval. |
| E2E-6 | Settings round-trip | change every control in each tab → UserDefaults value matches; relaunch → UI reflects; Reset keeps onboardingDone. |
| E2E-7 | Export/Import | Export JSON → wipe DB → Import → row counts identical, remaining identical; export contains no `sk-`. |
| E2E-8 | Unpriced model | fixture usage for model `made-up-model-1` → by-model row flagged, excluded from runway, one `price.unpriced` warn per day, `est_cost_cents NULL`. |
| E2E-9 | Band traceability | for every `ui.band_change` record in a fixture run there is a `poll.ok` or `ledger.*` record for the same `acct` within the preceding 2 s (script `scripts/check-traceability.sh`). |

## Load, perf, security
| ID | Procedure | Pass |
|---|---|---|
| LOAD-1 | Generator inserts 5 years of synthetic data (5 accounts, 20 models, 10 keys, hourly rows for 90 d + daily beyond) then runs roll-ups and `incremental_vacuum` | DB file < 250 MB; Overview renders < 300 ms (measured with `ContinuousClock`); popover open < 100 ms. |
| PERF-1 | `scripts/perf-idle.sh`: launch Release build with fixture mode, sample `ps -o rss,%cpu` every 10 s for 10 min idle | RSS ≤ 60 MB (p95), CPU ≤ 0.1 % avg. |
| PERF-2 | Same with popover held open 2 min; then dashboard open 2 min | ≤ 75 MB / ≤ 90 MB. |
| PERF-3 | Energy: `powermetrics` not required; instead count wakeups via `sched.tick` log: ≤ 2 wakeups/min idle with 4 accounts. | |
| SEC-1 | `scripts/check-no-secrets.sh`: run E2E-2 and E2E-7 with keys set to `sk-FIXTURE-…`, then grep `tokenbe.sqlite`, all logs, diagnostics zip (unzipped), export JSON, and the `.app` bundle for `sk-FIXTURE` and `FIXTURE` | zero matches outside Keychain. |
| SEC-2 | Keychain item attributes | Login keychain (Q-027): written with `kSecAttrAccessible = WhenUnlockedThisDeviceOnly` and `kSecAttrSynchronizable = false`, service `dev.bathyon.tokenbe`, account `<provider>`. The login keychain does not report `kSecAttrAccessible` back, so the test asserts class, service and account, and that no synchronizable copy exists. |
| SOAK-1 | 14 days on maintainer machine, real keys, log level info | zero `fault`; every `error` event has a matching entry in `docs/QUESTIONS.md` or a fix commit. |

## Test doubles (names fixed)
- `TestClock: Clock` — manual `advance(by:)`; all scheduling tests use it.
- `StubTransport: HTTPTransport` — maps `(method, path)` → fixture file or error; records calls; asserts order.
- `MemoryRepository: Repository` — NOT allowed for integration tests; use a temp-file GRDB database (`DatabaseQueue(path: tmp)`) so SQL is exercised. `MemoryRepository` may be used only in pure UI view-model tests.
- `CapturingLogSink` — collects records for assertions on `evt` names and redaction.

## Definition of done
- `swift test` green on CI with `-warnings-as-errors`.
- Coverage gate: ≥ 85 % lines in `TokenBeCore` (measured with `swift test --enable-code-coverage`; CI fails below).
- Every `evt` in 07's table is produced by at least one test (`CapturingLogSink` union across suite, checked by `scripts/check-log-events.sh --from-tests`).
