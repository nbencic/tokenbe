# 04 — Architecture

## Stack (final, after iteration)

| Layer | Choice | Not allowed |
|---|---|---|
| Language | Swift 6, language mode 6, strict concurrency `complete`, macOS 15.0 deployment target | Objective-C files except bridging for C APIs; Rust/other toolchains |
| UI | SwiftUI: `MenuBarExtra(.window)`, `Settings` scene, `NavigationSplitView`, Swift Charts, `@Observable` models | AppKit windows except `NSStatusItem` fallback if `MenuBarExtra` cannot render the template glyph; third-party UI libs |
| Concurrency | `actor` per account (`AccountPoller`), `actor PollCoordinator`, `actor IngestService`, `ContinuousClock` for all scheduling, `Date()` only for timestamps | `DispatchQueue` for app logic; `Timer`; `@unchecked Sendable` without an invariant comment |
| Persistence | SQLite via GRDB `DatabasePool`; all SQL in `TokenBeCore/Store` | SwiftData, Core Data, SQL in views |
| Networking | `URLSession.shared`-derived session with `waitsForConnectivity = false`, timeouts 15 s request / 30 s resource, gzip default, HTTP/2 | Third-party HTTP clients |
| Secrets | Keychain (`kSecClassGenericPassword`, service `dev.bathyon.tokenbe`, account = `account.keychain_ref`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) | Secrets in UserDefaults, DB, files, logs |
| Scheduling | One `SchedulerLoop` task for minute-cadence jobs; one `NSBackgroundActivityScheduler` identifier `dev.bathyon.tokenbe.daily` for daily jobs | Per-account timers; launchd agents; helper processes |
| File watching | FSEvents (`FSEventStreamCreate`, latency 1.0 s, flags `kFSEventStreamCreateFlagFileEvents | UseCFTypes`) on the ingest folder | Polling the folder; vnode sources on the directory |
| Logging | `os.Logger` (subsystem `dev.bathyon.tokenbe`) + NDJSON file sink (`07`) | print(); swift-log |
| Updates | Daily GitHub releases check (`02 § Update check`) | Sparkle in V1 |
| Distribution | Developer ID, notarized `.dmg`, Homebrew cask | Mac App Store in V1 |
| Dependencies | GRDB only | Anything else without a `13-decisions.md` entry |

## Modules (SwiftPM targets)

```
TokenBeCore            (library, no AppKit/SwiftUI imports)
  Providers/           ProviderAdapter protocol + 5 adapters + Capabilities
  Normalize/           TokenClasses, per-provider normalizers (05)
  Pricing/             PriceBook actor, lookup, cost formulas (05)
  Ledger/              Runway, bands, estimate band math (05)
  Ingest/              IngestService actor, FSEvents wrapper, line parser (06)
  Store/               Schema.sql, Migrator, Repository (03)
  Logging/             Log, NDJSONSink, Redactor, Breadcrumbs (07)
  Scheduling/          SchedulerLoop, PollCoordinator, AccountPoller, DailyActivity
  Model/               value types shared with UI (AccountSummary, AppRow, …)
TokenBeApp             (executable) SwiftUI views, view models, notifications, Settings, onboarding
TokenBeCoreTests       fixtures + unit + integration
```
Rule: `TokenBeApp` never imports GRDB or URLSession directly. It talks to `TokenBeCore` through `AppModel` (an `@Observable @MainActor` class) that exposes value types only.

## Concurrency model

- `PollCoordinator` (actor) owns `[AccountID: AccountPoller]` and the single `SchedulerLoop` task.
- `AccountPoller` (actor) owns that account's `poll_state`, its adapter instance, and an `inFlight: Set<Job>`. A job is one of `usage`, `cost`, `balance`, `keys`.
- Invariant I1: at most one in-flight task per `(account, job)`. The coordinator checks `inFlight` before dispatch; a violation attempt logs `sched.overlap_skipped` and is skipped.
- Invariant I2: all DB writes go through `Repository` (actor-isolated to the pool's writer queue). Views read via `ValueObservation` on `DatabasePool` reader connections, mapped to value types.
- Invariant I3: the UI never computes money. `Ledger` computes `AccountSummary` (remaining, band, paces, estimate band) in Core; views render it.
- Cancellation: a job whose duration exceeds `2 × its interval` is cancelled by the coordinator, logged `sched.overrun` with the phase name the poller last recorded (`fetch`, `decode`, `write`), and retried at the next tick.

## Scheduler

### Minute-cadence loop (`SchedulerLoop`)
```
loop:
  now = clock.now
  due = jobs.filter { $0.nextDue <= now && !poller.inFlight.contains($0) && !circuitOpen($0) }
  for job in due: Task { await poller.run(job) }    // fire-and-forget, tracked in inFlight
  next = jobs.map(\.nextDue).min()
  try await clock.sleep(until: next, tolerance: .seconds(5))   // tolerance lets the OS coalesce
```
Jobs and default intervals (user-tunable in `09`): `balance` 60 s (openrouter, deepseek, xai); `usage` 60 s (anthropic), 300 s (openai); `keys` 3600 s (openai, anthropic, openrouter). After a sleep/wake (`NSWorkspace.didWakeNotification`) or a wall-clock jump > 30 s versus the monotonic clock, log `sched.clock_jump` with both deltas and recompute `nextDue` from `now` (never catch up missed ticks).

### Daily activity (`NSBackgroundActivityScheduler`, identifier `dev.bathyon.tokenbe.daily`)
`interval = 86400`, `tolerance = 3600`, `qualityOfService = .utility`, `repeats = true`. Runs, in order, each logged with duration: cost polls (openai, anthropic) → roll-ups (`03`) → price refresh → update check → DB backup → weekly `integrity_check` (every 7th run) → `incremental_vacuum`. If any step throws, the remaining steps still run; the failure is logged and the step is retried at the next activity.
Manual "Refresh now" in Settings triggers the same function out of band.

### Low Power Mode
If `ProcessInfo.processInfo.isLowPowerModeEnabled` is true, all minute-cadence intervals are multiplied by 4. Logged once per transition as `sched.low_power`.

## Error taxonomy (one enum, used by every adapter)

```swift
enum PollError: Error, Sendable {
  case transport(URLError)                       // DNS, timeout, offline
  case auth(http: Int, body: String)             // 401, 403
  case rateLimited(retryAfter: Duration?)        // 429
  case server(http: Int, body: String)           // 5xx
  case decode(field: String, path: String)       // JSON present but shape wrong
  case schemaDrift(unknownKeys: [String])        // decoded, but with unexpected keys (non-fatal; logged, not thrown)
  case providerRule(String)                      // e.g. "costs endpoint bucket_width must be 1d"
  case cancelled
}
```

## Retry policy (per job attempt)

- `transport`, `server`: retry up to 3 times within the attempt with delays 2 s, 4 s, 8 s ± 25 % jitter; then fail the attempt.
- `rateLimited`: wait `retryAfter` if present (cap 300 s) else 30 s; one retry; then fail the attempt.
- `auth`: no retry. `consecutive_failures += 1`. At 3 consecutive auth failures `circuit_open_until = now + 24h`; the account card shows "Key rejected · Fix…"; polls stop until the user re-tests the key (which resets the circuit).
- `decode`: no retry. Attempt fails. `poll_state.last_raw` holds the body. After 3 consecutive decode failures on the same job, the account badge shows "Provider changed its response · Copy diagnostics".
- Backoff between attempts after a failed attempt: interval × 2^n, cap 15 min, reset on success.

## Invariants (asserted in DEBUG, logged `error` and degraded in RELEASE)

- V1 `remaining_cents ≥ −burn_7d_cents` (one day of negative drift allowed; beyond that the estimate is marked `unknown` and the user is asked to re-anchor).
- V2 For any provider usage page, `Σ results.tokens` equals the sum of rows written for that page (write completeness).
- V3 One in-flight task per `(account, job)`.
- V4 Every `harness_event` resolves to exactly one `app_id` or to the sentinel app `unassigned`.
- V5 `PriceBook.lookup` never returns a zero price; it returns `nil` (unpriced) or a positive value.
- V6 `band_state.inputs_json` is written in the same transaction as any `band` change.
- V7 `ingest_file.offset/last_size/last_mtime` and the `harness_event` + `usage_bucket` rows produced from the same read are committed in ONE transaction (`06 § Tailing`). A crash between them is impossible by construction.

## Resource targets (measured, `11 § PERF`)

| State | RSS | CPU |
|---|---|---|
| Idle, popover closed, 5 accounts | ≤ 60 MB | ≤ 0.1 % avg over 1 h |
| Popover open | ≤ 75 MB | — |
| Dashboard window open | ≤ 90 MB | — |
| During a poll cycle | — | ≤ 50 ms CPU per cycle |
Dashboard and Settings windows are released on close (`NSWindow.isReleasedWhenClosed` semantics via SwiftUI `WindowGroup` with no retained model copies). Charts render only while visible.

## Startup sequence (deterministic order)

1. Init logging (file sink first, then OSLog). Log `app.launch` with version, build, macOS version, locale, timezone.
2. Open DB, run PRAGMAs, `quick_check`, migrations. Any failure → alert, stop.
3. Load accounts; for each, read Keychain item; missing item → log `keychain.missing`, account marked `needs_key`.
4. Load current price snapshot (DB) or bundled snapshot.
5. Start `IngestService` (scan folder for `active` files, resume offsets).
6. Start `PollCoordinator` (first tick immediately for all accounts).
7. Register daily activity.
8. Render menu bar glyph from `band_state` (previous state) until first polls complete.

## Definition of done
- `swift build` of `TokenBeCore` on macOS emits zero concurrency warnings.
- Invariants V1–V6 have tests that trigger each one and assert the log record.
- Overlap test: two concurrent `run(usage)` calls on one poller produce exactly one network call and one `sched.overlap_skipped` record.
- Clock-jump test with an injected clock produces `sched.clock_jump` and no catch-up burst.
