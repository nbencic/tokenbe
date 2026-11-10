# 14 — Development plan (phases → stages → steps)

Status: AUTHORITATIVE build order for V1. Revised 2026-11-09 after two review passes (§ 14). Postmortem rule (§ 0.6) added 2026-11-09.

## 0. How this plan is executed

**Executor:** Claude Code running on Nikola's Mac (macOS 15, Xcode ≥ 16.2, `swiftlint` installed via Homebrew — a dev tool, not an app dependency). The agent builds, tests and lints itself after every step. The only steps a human performs are the **H-gates** in § 0.4.

**Granularity:** Phase → Stage → Step. A **stage** is the unit of "done": it ends with a PR merged to `main`, and `main` is always a runnable app with every earlier stage's behavior intact. A **step** is one commit (or a few) inside the stage. Steps are only broken down where a wrong order would cost rework.

**Non-blocking rule:** stages are ordered so that each one needs only the stages before it. When a stage has a human gate, the gate has a "while waiting" path and the next stage does not depend on the gate being closed.

**Branching:** one branch per stage, named `s<phase>.<stage>-<slug>` (e.g. `s3.4-openai-adapter`); squash-merge with the PR title `Stage 3.4 — OpenAI adapter`; CI (10) must be green; the PR body contains the pasted summary lines of `scripts/verify-stage.sh <id>`.

**Every long-running command** (build, test, UI test, perf sampling) runs through `scripts/run.sh <task>` which backgrounds the process, writes `build/logs/<task>-<timestamp>.log`, enforces a timeout, and exits with the task's exit code after `scripts/wait.sh` polls it (bounded, 15 s interval). The agent never leaves a foreground `xcodebuild` holding the shell. Timeouts: `test` 900 s, `build-app` 900 s, `uitest` 1800 s, `perf` 1200 s, `load` 1800 s.

**Machine-checked DoD:** every stage adds `scripts/stages/<id>.sh` with its checks. `scripts/verify-stage.sh <id>` runs the checks of **all stages up to and including `<id>`** (regression), then prints `STAGE <id> OK` or the first failing check. A stage is not done until that line prints. After the stage scripts, `verify-stage.sh` runs one generic check (D13), so a run before the postmortem is written shows every stage check green and then fails only D13: for every stage up to and including `<id>`, and for every completed phase, the postmortem file from § 0.6 exists and contains all of its template's `##` headings.

### 0.1 Definition of done — template applied to every stage (D1–D12)

| # | Check |
|---|---|
| D1 | Every path in the stage's **Inventory** exists, is non-empty, and is referenced (compiled, run, or read) by something; nothing outside the inventory changed except `CHANGELOG.md`, `docs/QUESTIONS.md`, `docs/postmortems/`, tests, and docs that the stage says to update. |
| D2 | `scripts/verify-stage.sh <id>` prints `STAGE <id> OK` (all earlier stages included). |
| D3 | Every new `catch`/failure branch logs an event that exists in `07`'s table; `scripts/check-log-events.sh` passes in both directions (table ↔ `Evt` enum). |
| D4 | Every settings key in the inventory is registered with its default, clamped, covered by `SettingsTests`, and read by the consumer named in `09`; if `09` places it in a tab, the control exists and works. |
| D5 | Every DB object in the inventory exists in `001_initial.sql`, has a GRDB record type, a `Repository` method, and a test that writes and reads it. Seed rows listed in the inventory are inserted and asserted. |
| D6 | Every UI control added performs its complete action end-to-end. No disabled, inert or "coming soon" control, except the currency picker that `08`/`09` define as disabled by design. |
| D7 | `StartupSequenceTests` still asserts the log order of `04 § Startup sequence` for the steps that exist so far. |
| D8 | All user-visible copy is in `Strings.swift`; `swiftlint` custom rule `tokenbe_no_inline_text` (regex `Text\("[A-Za-z]`) passes. |
| D9 | Any contract touched (schema, event table, settings key, copy, endpoint) is updated in its doc in the same PR; every judgment call is in `docs/QUESTIONS.md` (`12 § R3`). |
| D10 | The app launches clean **and** on top of the previous run's data directory, with zero `error`/`fault` log records in either case. Verification launches a Debug build with `TOKENBE_TEST_ROOT=<temp dir>` (Q-014) and never deletes or touches the owner's real `~/Library/Application Support/TokenBe`, `~/Library/Logs/TokenBe` or settings domain. |
| D11 | `CHANGELOG.md § [Unreleased]` has one line for the stage. |
| D12 | PR merged; `main` CI green. |
| D13 | `docs/postmortems/stage-<id>.md` exists with every heading of the § 0.6 stage template; if the stage is the last of its phase (§ 0.5), `docs/postmortems/phase-<n>.md` exists with every heading of the phase template. D13 applies to **every** stage, even where its Stage DoD line does not list it. |

### 0.2 Stage anatomy (what every stage section below contains)

**Goal · Depends on · Adds (what the user sees) · Steps · Inventory** (Files / DB / Settings / Events / UI / Scripts & resources / Fixtures) **· Tests · Verify (`scripts/stages/<id>.sh`) · Stage-specific DoD · Human gate** (only where one exists).

### 0.3 Seams (abstraction layers)

Exactly these protocols exist. No other protocol is introduced "for testability"; concrete types are used everywhere else. Each seam has one production and one test implementation. Everything is assembled once in `AppEnvironment` (composition root, § 1.1) and in `TestEnvironment` (tests). No singletons, no service locator.

| Seam | Protocol (file) | Production | Test | Introduced |
|---|---|---|---|---|
| Logging sink | `LogSink` (`Logging/LogSink.swift`) | `NDJSONSink`, `OSLogSink` | `CapturingLogSink` | 0.2 |
| Settings storage | `SettingsStore` (`Settings/SettingsStore.swift`) | `UserDefaultsStore` | `InMemorySettingsStore` | 0.3 |
| Time | Swift `Clock` | `ContinuousClock` | `TestClock` | 0.2 (Log flush timer), 4.1 |
| Persistence | `Repository` (`Store/Repository.swift`) | `GRDBRepository` (over `DatabasePool`) | temp-file `GRDBRepository` (integration); `MemoryRepository` (view-model tests only) | 2.1 |
| HTTP | `HTTPTransport` (`Network/HTTPTransport.swift`) | `URLSessionTransport` | `StubTransport`, `FixtureTransport` (DEBUG fixture mode) | 3.1 |
| Secrets | `KeyStore` (`Keychain/KeyStore.swift`) | `KeychainKeyStore` | `InMemoryKeyStore` | 3.2 |
| Provider | `ProviderAdapter` (`Providers/ProviderAdapter.swift`) | 5 adapters | adapters over `StubTransport` | 3.3 |
| File watching | `FileWatcher` (`Ingest/FileWatcher.swift`) | `FSEventsWatcher`; `PollingWatcher` (fallback, also production) | `ManualWatcher` | 7.2 |
| Notifications | `Notifier` (`TokenBeApp/Notifications/Notifier.swift`) | `UNNotifier` | `RecordingNotifier` | 5.4 |
| Network reachability | `NetworkMonitor` (`Network/NetworkMonitor.swift`) | `NWPathMonitorAdapter` | `ManualNetworkMonitor` | 4.1 |

Boundary rule (04): `TokenBeApp` never imports GRDB or touches `URLSession`; it talks to Core through `AppModel` (`@Observable @MainActor`) which exposes value types only (`AccountSummary`, `AppRow`, `ModelRow`, `SourceStatus`, …).

### 0.4 Human gates (the only steps Nikola performs)

| Gate | What | Needed by | While waiting |
|---|---|---|---|
| H1 | **Retired 2026-11-09** (D-xcodeproj-agent): the agent writes `TokenBe.xcodeproj`. Was: create the project in the Xcode GUI | — | — |
| H2 | Run `scripts/record-fixtures.sh openai` with `OPENAI_ADMIN_KEY` | 3.6 (marks OpenAI verified) | Phases 4–5 proceed on synthetic fixtures |
| H3 | Run `scripts/record-fixtures.sh deepseek` and/or `xai` with keys | 6.1/6.2 verification | Phase 7 proceeds |
| H4 | Developer ID certificate + notarytool keychain profile `tokenbe-notary` on the Mac | 11.5 | Everything else |
| H5 | 14-day soak (SOAK-1) — app runs on Nikola's Mac with real keys | 11.5 | Starts at end of 9.5; 10.x and 11.1–11.4 run in parallel |

### 0.5 Phase map

| Phase | Stages | What exists at the end |
|---|---|---|
| 0 Toolchain & skeleton | 0.1 repo · 0.2 logging · 0.3 settings · 0.4 app project (H1) · 0.5 CI | A signed-less app that launches, shows a menu-bar glyph, logs `app.launch`/`app.terminate` to NDJSON |
| 1 App shell | 1.1 popover & glyph · 1.2 dashboard window · 1.3 settings window (General, Privacy, Advanced-logging) | Full window/menu chrome with real empty states; preferences work |
| 2 Storage | 2.1 database · 2.2 observation & maintenance buttons | DB created, migrated, observed; backup/integrity on demand |
| 3 Accounts (OpenAI) | 3.1 network · 3.2 keychain · 3.3 provider seam · 3.4 OpenAI adapter · 3.5 onboarding & Accounts tab · 3.6 verify OpenAI (H2) | User adds an OpenAI account; keys discovered; one-shot polls write buckets |
| 4 Scheduling | 4.1 scheduler & coordinator · 4.2 freshness, stale, account page shell · 4.3 daily activity | Polls run on their own; Sources tab; stale/offline/paused states |
| 5 Money | 5.1 price book · 5.2 cost estimation · 5.3 ledger, runway, bands · 5.4 notifications · 5.5 glyph completion | The product's core promise: remaining, runway, bands, alerts |
| 6 Direct balance | 6.1 DeepSeek · 6.2 xAI (H3) | Direct-balance accounts, CN¥ handling |
| 7 Apps | 7.1 apps by provider key · 7.2 harness ingest · 7.3 drilldown polish | Per-app attribution incl. harness drop folder |
| 8 Dashboard | 8.1 by-model & drift · 8.2 chart & cache tile · 8.3 CSV export · 8.4 accessibility | Dashboard complete per 08 |
| 9 Lifecycle | 9.1 retention · 9.2 export/import · 9.3 diagnostics · 9.4 update check · 9.5 reset & audits | Long-term durability features; startup sequence audited |
| 10 Gated adapters | 10.1 Anthropic · 10.2 OpenRouter · 10.3 contributor path | Compiled and tested on synthetic fixtures; hidden in Release until recorded |
| 11 Hardening & release | 11.1 perf · 11.2 security · 11.3 Paper/strings/accessibility · 11.4 docs · 11.5 release (H4, H5) | 1.0.0 notarized dmg + cask |

Mapping to `10 § Milestones`: M0 = 3.6/6.x gates; M1 = Phases 0–2; M2 = 3–4; M3 = 5; M4 = 1, 8; M5 = 7; M6 = 11.1–11.3; M7 = 11.5.

### 0.6 Postmortems (D-postmortems)

**When.** Each stage runs: steps → `verify-stage.sh <id>` passes the stage checks → **write the stage postmortem** → run `verify-stage.sh <id>` again (now D13 is green too) → PR → CI → merge. If the stage is the last one of its phase in § 0.5, also write the **phase postmortem** in the same PR. Never write a postmortem as a separate commit to `main` after the merge.

**Where.** `docs/postmortems/stage-<id>.md` (e.g. `stage-3.4.md`) and `docs/postmortems/phase-<n>.md` (e.g. `phase-3.md`). Commit message: `docs: postmortem stage <id>` / `docs: postmortem phase <n>`.

**Rules.**
1. Blameless and factual: symptom → root cause → fix. Cite commits, log events, check names, `Q-nnn`. No filler. "Nothing went wrong" is allowed only together with the evidence (verify output passed on the first run, zero `error` records).
2. A postmortem never changes a contract by itself. A lesson that needs a doc change is either made in the same PR (D9; the postmortem names the file and section) or logged as `Q-nnn` (`12 § R3`).
3. Carry-forward actions have an id `PM-<id>-<k>` (e.g. `PM-3.4-1`), an owner (`agent` or `Nikola`) and a target stage. At the start of every stage, the agent reads all open actions that target it. The stage postmortem marks each one `closed (<commit>)` or `re-targeted → <stage> (<reason>)`, and edits the status in the original file too.
4. Human gates: a stage merged while its H-gate is still open records that under *Outcome*. When the gate closes, append `## Addendum — H<n> closed <date>` to the same file in the PR that consumes the gate. The required headings are unchanged.
5. Phase 11 (release) gets a phase postmortem like every other phase. It also covers the H5 soak findings.

**Stage template** (all `##` headings required, in this order):
```
# Postmortem — Stage <id> <title>
Date: YYYY-MM-DD · Branch: s<id>-<slug> · PR: #<n> · Planned size: S|M|L · Commits: <n>

## Outcome
<one paragraph: what the user can now do; DoD lines met; open gate, if any>

## What went as planned

## What went wrong
<each item: symptom → root cause → fix → cost (commits/time); or "none" plus the evidence>

## Verify and CI failures
<every failing check of verify-stage.sh / CI on the way to green: check, cause, fix>

## Deviations from the docs
<every place the implementation differs from the docs or the docs were wrong: doc § → what changed in this PR, or Q-nnn>

## Judgment calls
<Q-nnn ids opened in this stage, one line each>

## Carry-forward actions
<PM-<id>-<k> · owner · target stage · action; plus the status of earlier actions that targeted this stage>
```

**Phase template** (all `##` headings required, in this order):
```
# Postmortem — Phase <n> <title>
Date: YYYY-MM-DD · Stages: <ids with PR numbers>

## Outcome vs. phase map
<the § 0.5 "What exists at the end" line, met item by item>

## Patterns across stages
<problems that recurred in two or more stage postmortems, with root cause>

## Plan and doc changes
<changes to 14 or 01–13 made during the phase, and any proposed for later phases (applied in this PR or Q-nnn)>

## Gates and risks
<status of H-gates; risks for the next phase>

## Open carry-forward actions
<every PM-* not yet closed, with its target>
```

---

## 1. Phase 0 — Toolchain & skeleton

### Stage 0.1 — Repository skeleton & Core package
**Goal:** a buildable SwiftPM package, lint, scripts, docs in place. **Depends on:** nothing. **Adds:** nothing visible. **Size:** S.

**Steps**
1. `git init`; `LICENSE` (MIT, "Nikola Benčić"); `.gitignore` (Xcode, SwiftPM `.build/`, `build/`, `DerivedData/`, `*.xcuserstate`, `xcuserdata/`, `.DS_Store`, `*.dmg`); `.editorconfig` (2-space Swift, LF).
2. Copy `docs/` (this set) verbatim; `docs/QUESTIONS.md` present (empty); `docs/postmortems/` present (empty, `.gitkeep`).
3. `Package.swift` exactly as `10` (GRDB pinned to the latest 7.x; write the version into `13 § D-grdb-version`).
4. `Sources/TokenBeCore/TokenBeCore.swift`: `public enum TokenBeCoreInfo { public static let schemaVersion = 1 }` (used by 2.1 and export).
5. `Tests/TokenBeCoreTests/SmokeTests.swift`: asserts `TokenBeCoreInfo.schemaVersion == 1` (replaced by real tests later; never deleted).
6. `.swiftlint.yml` from `10` plus rule `tokenbe_no_inline_text` (regex `Text\("[A-Za-z]`, included `Sources/TokenBeApp`, excluded `Strings.swift`).
7. `scripts/run.sh` (background + log + timeout + pid file), `scripts/wait.sh` (poll pid, bounded, prints tail 40 lines and exit code), `scripts/bootstrap.sh` (asserts macOS ≥ 15, `xcodebuild -version` ≥ 16.2, `swiftlint` present, prints next steps), `scripts/verify-stage.sh` (including the generic D13 postmortem check, § 0.6), `scripts/stages/0.1.sh`.
8. `CHANGELOG.md` (Keep a Changelog; `[Unreleased]`), `README.md` (one paragraph + "pre-alpha, see docs/").

**Inventory** — Files: all above. Scripts: `run.sh`, `wait.sh`, `bootstrap.sh`, `verify-stage.sh`, `stages/0.1.sh`.
**Tests:** `SmokeTests`.
**Verify (`stages/0.1.sh`):** `swift build` exit 0; `swift test` exit 0; `swiftlint --strict` exit 0; `test -s` on every inventory file; `grep -c "exact:" Package.swift == 1`.
**Stage DoD:** D1–D3, D9, D11–D12.

### Stage 0.2 — Logging core
**Goal:** `07` implemented in Core before any feature code exists (R5). **Depends on:** 0.1. **Adds:** nothing visible. **Size:** M.

**Steps**
1. `Logging/Evt.swift`: `public enum Evt: String, CaseIterable` — one case per row of `07 § Mandatory events` (compound rows like `poll.circuit_open / poll.circuit_close` become two cases). Nothing else may construct an event name.
2. `Logging/LogRecord.swift`: struct with the exact key order of `07` (`ts, lvl, cat, evt, msg, acct, job, attempt, err, dur_ms, ctx, pid, thr, v`); custom `encode(to:)` to preserve order; `ctx` is `[String: LogValue]` where `LogValue` is `.string/.int/.double/.bool/.null` (no nesting). Strings truncated to 512 chars with `…`; `ctx` capped at 2 KiB after redaction.
3. `Logging/Redactor.swift`: the 7 patterns in order; `register(secret:)` / `unregister(secret:)` for the exact-match pass (held only while a secret is in flight).
4. `Logging/LogSink.swift` protocol: `func write(_ record: LogRecord) async`, `func flush() async`.
5. `Logging/NDJSONSink.swift` (actor): bounded `AsyncStream` (4096) with drop counter → `app.log_dropped` every 60 s; 1 s / 64 KiB flush; synchronous flush path for `error`/`fault`; rotation at local midnight and 50 MiB (`-N` suffix); retention by days and 300 MiB total cap; directory `~/Library/Logs/TokenBe/` created with `0700`.
6. `Logging/OSLogSink.swift`: `os.Logger(subsystem: "dev.bathyon.tokenbe", category:)` per `cat`.
7. `Logging/Breadcrumbs.swift`: ring buffer 500 records (any level).
8. `Logging/Log.swift`: the API (`Log.debug/info/notice/warn/error/fault(_ evt: Evt, cat: Cat, msg:, acct:, job:, attempt:, err:, dur:, ctx:)`), `Log.minimumLevel` (default `.info`), `Log.configure(sinks:clock:)`. `Cat` enum with the categories of `07`.
9. `Logging/CrashHandler.swift`: `NSSetUncaughtExceptionHandler` + signals `SIGABRT SIGBUS SIGSEGV SIGILL SIGTRAP SIGFPE`; pre-allocated 64 KiB buffer; writes one `crash.signal` line with last 50 breadcrumbs via `write(2)`; re-raises. `RunningSentinel` (`.running` file create/remove; `wasUnclean()` → caller logs `crash.previous_launch`).
10. `scripts/check-log-events.sh`: parses `07`'s table (every backticked `evt` in column 1) and `Evt.swift`; fails on any name present in one but not the other.

**Inventory** — Files: `Sources/TokenBeCore/Logging/{Evt,LogRecord,Redactor,LogSink,NDJSONSink,OSLogSink,Breadcrumbs,Log,CrashHandler}.swift`. Events: `app.log_dropped`, `crash.signal`, `crash.previous_launch` (API exists; emitted from 0.4). Scripts: `check-log-events.sh`, `stages/0.2.sh`.
**Tests:** `RedactorTests` (7 patterns, exact-match pass, never > last 4 chars), `LogSinkTests` (parseable NDJSON, key order, rotation with 50 KiB test override, retention deletion, total cap, overflow → `app.log_dropped`), `CrashHandlerTests` (dry-run writes a parseable line; sentinel semantics), `LogRecordTests` (ctx truncation and cap).
**Verify:** tests above; `check-log-events.sh`; `grep -R "print(" Sources/ | wc -l == 0`.
**Stage DoD:** D1–D3, D9, D11–D12; `07 § Definition of done` items 1–3.

### Stage 0.3 — Settings core
**Goal:** `09` as code. **Depends on:** 0.2. **Adds:** nothing visible. **Size:** S.

**Steps**
1. `Settings/SettingsStore.swift` protocol (`get/set/remove/registerDefaults`), `UserDefaultsStore` (suite `dev.bathyon.tokenbe`; the only file allowed to import `UserDefaults`), `InMemorySettingsStore`.
2. `Settings/SettingsKey.swift`: `enum SettingsKey: String, CaseIterable` with every key of `09` and a `Spec` (type, default, range/allowed values, tab). Per-provider templated keys (`tb.popover.expanded.<provider>`, `tb.alerts.snoozedUntil.<provider>`) via `static func expanded(_ p: ProviderID)` etc. (`ProviderID` is declared here as a plain enum; adapters come later).
3. `Settings/Settings.swift`: `@Observable @MainActor public final class Settings` — typed accessors generated from `SettingsKey` (one property per key), clamp-on-write with `app.settings_changed {key, old, new, clamped, source}`, `critical < low < watch` repair, `changes: AsyncStream<SettingsKey>`, `resetAll()` keeping `tb.ui.onboardingDone` and logging `app.settings_reset`. `Log.minimumLevel` is bound to `tb.log.level` here.
4. Defaults registered from the `Spec` table at init — the table is the single source.

**Inventory** — Files: `Settings/{SettingsStore,SettingsKey,Settings}.swift`. Settings: every key in `09`. Events: `app.settings_changed`, `app.settings_reset`.
**Tests:** `SettingsTests` (each key has a default; below/above range clamps and logs; threshold repair; reset keeps `onboardingDone`; templated keys round-trip).
**Verify:** tests; `grep -R "UserDefaults" Sources/ | grep -v Settings/UserDefaultsStore.swift | wc -l == 0`.
**Stage DoD:** D1–D4, D9, D11–D12.

### Stage 0.4 — App project, build configuration, first launch (H1)
**Goal:** an app target that builds from `xcodebuild`, launches to a menu-bar glyph, and runs startup steps 1 and the crash/sentinel path. **Depends on:** 0.3. **Adds:** menu-bar glyph with a popover containing the word `TokenBe` (replaced in 1.1). **Size:** M.

**H1 — retired 2026-11-09 (D-xcodeproj-agent).** The agent writes `TokenBe.xcodeproj` with empty `buildSettings`, both targets on synchronized folders, the local package and a shared scheme. The original GUI steps are kept below for reference only:
1. File → New → Project → macOS → **App**. Product Name `TokenBe`; Team: your Developer ID team; Organization Identifier `dev.bathyon`; Interface **SwiftUI**; Language **Swift**; Storage **None**; Testing System **XCTest**; untick "Create Git repository". Save **into the repo root** (`tokenbe/`).
2. In Finder: move `tokenbe/TokenBe/` (the generated source folder) to `tokenbe/Sources/TokenBeApp/`; delete `tokenbe/TokenBeTests/`; move `tokenbe/TokenBeUITests/` to `tokenbe/Tests/TokenBeUITests/`. In Xcode: select each red (missing) synchronized group → File Inspector → Location folder icon → choose the moved folder. Delete the `TokenBeTests` target (keep `TokenBeUITests`).
3. File → Add Package Dependencies… → **Add Local…** → choose the repo root (`Package.swift`) → add product **TokenBeCore** to target `TokenBe`.
4. Project → Info → Configurations: set **Debug** to `Config/Debug.xcconfig` and **Release** to `Config/Release.xcconfig` for both project and target rows (the files are created by the agent in step 1 below — do this after the agent's branch is pulled).
5. Target `TokenBe` → Signing & Capabilities: Team set; **Hardened Runtime** on; **do not** add App Sandbox.
6. Commit `TokenBe.xcodeproj/project.pbxproj` and `TokenBe.xcodeproj/xcshareddata/xcschemes/TokenBe.xcscheme` (Product → Scheme → Manage Schemes → tick **Shared**).

**Agent steps**
1. `Config/Base.xcconfig`: `PRODUCT_BUNDLE_IDENTIFIER = dev.bathyon.tokenbe`, `PRODUCT_NAME = TokenBe`, `MACOSX_DEPLOYMENT_TARGET = 15.0`, `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, `ENABLE_HARDENED_RUNTIME = YES`, `ENABLE_APP_SANDBOX = NO`, `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_LSUIElement = YES`, `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.developer-tools`, `INFOPLIST_KEY_CFBundleDisplayName = TokenBe`, `INFOPLIST_KEY_NSHumanReadableCopyright = © 2026 Nikola Benčić. MIT License.`, `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`, `CODE_SIGN_ENTITLEMENTS = Sources/TokenBeApp/TokenBe.entitlements`, `DEAD_CODE_STRIPPING = YES`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`. `Debug.xcconfig`: includes Base; `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`, `SWIFT_OPTIMIZATION_LEVEL = -Onone`. `Release.xcconfig`: includes Base; `SWIFT_OPTIMIZATION_LEVEL = -O`, `SWIFT_COMPILATION_MODE = wholemodule`.
2. `Sources/TokenBeApp/TokenBe.entitlements`: empty `<dict/>` (hardened runtime needs no keys; no sandbox).
3. `Sources/TokenBeApp/Resources/Assets.xcassets`: color sets for every row of `08 § Design tokens` (light + dark `Any Appearance`/`Dark`), `AccentColor`, `AppIcon` (PNGs produced by `scripts/make-icon.swift` — a Swift script rendering the ring glyph on a rounded rect with `CoreGraphics`, sizes 16…1024, run once and committed; D-icon-script).
4. `TokenBeApp.swift` (`@main`): `MenuBarExtra` with a code-drawn glyph (`Components/MenuBarGlyph.swift`, `Path`-based ring, template rendering) and `.menuBarExtraStyle(.window)`; `@NSApplicationDelegateAdaptor(AppDelegate.self)`.
5. `AppDelegate.swift`: `applicationDidFinishLaunching` → `Startup.run(step: .logging)` (step 1 of `04`: NDJSON sink first, then OSLog; `app.launch` with version/build/macOS/lowPower/launchAtLogin/locale/timezone; `RunningSentinel.wasUnclean()` → `crash.previous_launch`; `CrashHandler.install()`); `applicationWillTerminate` → `app.terminate {reason}` + `Log.flush()` + sentinel removed.
6. `Startup.swift`: an ordered list of named steps executed sequentially with one `info` log each (`app.launch` ctx `startup_step`); later stages append steps in `04`'s order. `StartupSequenceTests` asserts order from a `CapturingLogSink` run of `Startup` with test doubles.
7. `scripts/stages/0.4.sh`: `xcodebuild -showBuildSettings` assertions (bundle id, deployment target, strict concurrency, `LSUIElement`), `run.sh build-app`, launch via `open`, wait for `~/Library/Logs/TokenBe/tokenbe-*.ndjson` to contain `"evt":"app.launch"`, quit via `osascript -e 'quit app "TokenBe"'`, assert `"evt":"app.terminate"`, assert `.running` sentinel removed.

**Inventory** — Files: `Config/{Base,Debug,Release}.xcconfig`, `TokenBe.xcodeproj/` (human), `Sources/TokenBeApp/{TokenBeApp,AppDelegate,Startup}.swift`, `Sources/TokenBeApp/Components/MenuBarGlyph.swift`, `Sources/TokenBeApp/TokenBe.entitlements`, `Sources/TokenBeApp/Resources/Assets.xcassets/**`, `Tests/TokenBeUITests/` (target, empty smoke test launching the app), `scripts/make-icon.swift`. Events: `app.launch`, `app.terminate`, `crash.previous_launch`. Resources: all color sets, AccentColor, AppIcon.
**Tests:** `StartupSequenceTests` (Core, with `Startup` moved into Core as `StartupSequence` of closures — the app supplies closures); `TokenBeUITests/LaunchSmokeTests` (app launches; status item exists).
**Verify:** `stages/0.4.sh` above.
**Stage DoD:** D1–D3, D7, D9–D12; glyph visible in the menu bar on a clean account.

### Stage 0.5 — CI & secret/URL guards
**Goal:** `10 § CI` green on every PR. **Depends on:** 0.4. **Adds:** nothing visible. **Size:** S.

**Steps**
1. `.github/workflows/ci.yml` per `10`: `macos-15`, Xcode 16.x select, `swift build -c release -Xswiftc -warnings-as-errors`, `swift test --enable-code-coverage`, coverage gate ≥ 85 % lines in `TokenBeCore` (`xcrun llvm-cov report`, script `scripts/coverage-gate.sh`), `swiftlint --strict`, `check-log-events.sh`, `check-no-secrets.sh`, `xcodebuild -scheme TokenBe -configuration Release build CODE_SIGNING_ALLOWED=NO`.
2. `scripts/check-no-secrets.sh`: greps the tree and (when present) `build/` products for the 7 key patterns of `07` and for `URL(string:` / `https://` literals outside the allowlist `api.openai.com`, `api.anthropic.com`, `openrouter.ai`, `api.deepseek.com`, `api.x.ai`, `raw.githubusercontent.com/BerriAI/litellm`, `api.github.com/repos/nbencic/tokenbe`, `github.com/nbencic/tokenbe` (User-Agent). `Tests/Fixtures` are scanned too (they must be redacted).

**Inventory** — Files: `.github/workflows/ci.yml`, `scripts/{check-no-secrets,coverage-gate}.sh`, `scripts/stages/0.5.sh`.
**Verify:** scripts run locally with exit 0; a PR shows all CI steps green.
**Stage DoD:** D1–D3, D11–D12.

---

## 2. Phase 1 — App shell

### Stage 1.1 — Composition root, AppModel, popover empty state, glyph states
**Goal:** the popover of `08` with its **Empty** state and footer `Quit`; the glyph's three shapes exist (state wiring in 4.2/5.5). **Depends on:** 0.5. **Adds:** click glyph → popover with the Empty state text (`No accounts yet` / `Add a provider key to start tracking.`); footer `Quit` (⌘Q). The Empty state's `Add account…` button is added in 3.5 together with onboarding (rule: a control appears in the stage that implements its action). **Size:** M.

**Steps**
1. `AppEnvironment.swift`: struct holding `settings`, `clock`, `log sinks`; grows per stage (fields listed in each stage). Injected via `.environment(\.appEnvironment)`.
2. `AppModel.swift` (`@Observable @MainActor`): `accounts: [AccountSummary]` (empty), `isPaused`, `isOffline`, `lastRefreshAt`, `popoverIsOpen`. `Model/AccountSummary.swift` in Core: full value type with optionals (`id, provider, label, mode, currency, remainingCents?, estimateBandCents?, burn7dCents?, burnTodayCents?, runway7d?, runwayToday?, runwayMin?, band, bandSince, freshness: [Job: Date?], isStale, isPaused, needsKey, circuitOpenUntil?, todaySpendCents?, spend30dCents?, autoReload?, anchorAgeDays?, topApps: [AppSpend], unpricedCents`), filled progressively.
3. `Model/Formatters.swift` (Core): money (cents, hide/show cents, `CN¥`, `≈ … ±`, clamp negative), runway strings, token abbreviations, freshness, dates; locale-pinned tests.
4. `Strings.swift` (App): every string used so far; grows per stage; `StringsAuditTests` (11.3) checks the final list against `08`.
5. `Popover/PopoverView.swift` (header row with title; refresh button added in 4.1; banner slot; card list; footer), `Popover/EmptyStateView.swift`, `Popover/AccountCardView.swift` (renders `AccountSummary`; rows appear as data exists: 1.1 renders row 1 and the "No data yet" row).
6. `Components/MenuBarGlyph.swift`: three shapes (`solid`, `notched`, `dashed`) selectable by an enum; `AppModel.glyphState` computed (1.1: always `.solid`).
7. Popover open/close → `ui.popover_open` / `ui.popover_close {dur_ms}`; accessibility identifiers on every element (`popover.header.title`, `popover.empty`, `popover.footer.quit`, …) — identifiers are the hooks for all UI tests (D-no-pixel-snapshots).

**Inventory** — Files: `Sources/TokenBeApp/{AppEnvironment,AppModel,Strings}.swift`, `Popover/{PopoverView,EmptyStateView,AccountCardView}.swift`, `Core/Model/{AccountSummary,Formatters,Band,Money}.swift`. Settings used: `tb.ui.hideCents` (Formatters). Events: `ui.popover_open`, `ui.popover_close`.
**Tests:** `FormattersTests` (`en_US_POSIX` and `de_DE`), `TokenBeUITests/PopoverEmptyStateUITests` (open popover, assert identifiers/text, Quit terminates).
**Verify:** tests; `grep -c "accessibilityIdentifier" Sources/TokenBeApp/Popover/*.swift ≥ 6`.
**Stage DoD:** D1–D3, D6, D8–D12.

### Stage 1.2 — Dashboard window shell
**Goal:** the Dashboard window with sidebar `Overview`, range picker, frame persistence, and Overview empty state. **Depends on:** 1.1. **Adds:** popover footer `Open dashboard` (⌘D), ⌥-click on the glyph opens it. No right-click context menu (D-context-menu; Q-021). **Size:** S.

**Steps**
1. `Window("Dashboard", id: "dashboard")` scene, `min 920×600`, frame saved to `tb.ui.dashboardFrame` on move/resize (debounced 500 ms) and restored.
2. `Dashboard/DashboardView.swift` (`NavigationSplitView`), `Dashboard/SidebarView.swift` (section `Overview`; account rows and `Apps` are added in 3.5/7.1), `Dashboard/OverviewView.swift` with headline placeholder **not allowed** → shows the real empty state `No accounts yet` and a `Spend by day` card reading `No spend in this range`.
3. Toolbar: range picker `Today | 7 d | 30 d | 90 d` bound to `tb.ui.dashboardRange`; `Refresh` and `Export…` are added in 4.1/8.3.
4. ⌥-click on the menu-bar item opens the Dashboard (`NSEvent.modifierFlags` read at click; O-15 fallback pre-authorized). No right-click context menu (D-context-menu): the popover footer carries every action.

**Inventory** — Files: `Dashboard/{DashboardView,SidebarView,OverviewView}.swift`, `Components/RangePicker.swift`. Settings: `tb.ui.dashboardFrame`, `tb.ui.dashboardRange`. Events: none new.
**Tests:** `TokenBeUITests/DashboardShellUITests` (⌘D opens; range persists across relaunch).
**Verify:** UI test; `defaults read dev.bathyon.tokenbe.uitests tb.ui.dashboardRange` after test equals the selected value (the UI-test suite, Q-014/Q-020).
**Stage DoD:** D1–D4, D6, D8–D12.

### Stage 1.3 — Settings window: General, Privacy (static), Advanced (logging)
**Goal:** `Settings` scene with tabs that exist so far, every control working. **Depends on:** 1.2. **Adds:** popover footer `Settings…` (⌘,); General tab complete; Privacy tab text + `Open log folder`; Advanced tab: log level, log retention, `Open log folder`. **Size:** M.

**Steps**
1. `SettingsUI/SettingsView.swift` (`TabView`), `GeneralTab.swift`, `PrivacyTab.swift`, `AdvancedTab.swift` (sections grow later).
2. General: Launch at login (`SMAppService.mainApp`; mirror actual status at launch, log `app.settings_changed source=system` on mismatch; failure → `app.login_item_failed`), Menu bar metric picker (`tb.menubar.metric`; the text itself renders in 5.5 — until then the picker stores the value and the glyph shows no text; **this is the only control whose visible effect lands later**, allowed because the setting's consumer (5.5) is specified), Pinned metric, Sort, Currency display (disabled picker + caption), Hide cents, Appearance (`preferredColorScheme` on all scenes), Use system accent, Global shortcut (`Components/HotKeyRecorder.swift` + `Core/…`? no — `TokenBeApp/HotKey/HotKeyCenter.swift` with Carbon `RegisterEventHotKey`; failure → `ui.hotkey_failed`).
3. Privacy: static copy (keys in Keychain; no telemetry); `Open log folder` (`NSWorkspace.shared.open`). Update-check row arrives in 9.4.
4. Advanced: `Log level` picker (→ `Log.minimumLevel` live), `Log retention` stepper, `Open log folder`. Other rows arrive in 2.2/9.x.
5. Settings changes propagate through `Settings.changes` to `AppModel` (appearance, metric, sort) — subscription wired here.

**Inventory** — Files: `SettingsUI/{SettingsView,GeneralTab,PrivacyTab,AdvancedTab}.swift`, `HotKey/HotKeyCenter.swift`, `Components/HotKeyRecorder.swift`. Settings: `tb.general.launchAtLogin`, `tb.menubar.glyphStyle`, `tb.menubar.metric`, `tb.popover.pinnedMetric`, `tb.popover.sort`, `tb.popover.manualOrder` (read in 5.3 sort), `tb.ui.currencyDisplay`, `tb.ui.hideCents`, `tb.ui.appearance`, `tb.ui.useSystemAccent`, `tb.ui.shortcut`, `tb.log.level`, `tb.log.retentionDays`. Events: `app.login_item_failed`, `ui.hotkey_failed`, `app.settings_changed`.
**Tests:** `TokenBeUITests/SettingsGeneralUITests` (toggle each control → `defaults` value; appearance flips; shortcut toggles the Dashboard, Q-023).
**Verify:** UI test; `check-log-events.sh`.
**Stage DoD:** D1–D4, D6, D8–D12.

---

## 3. Phase 2 — Storage

### Stage 2.1 — Database, migration 001, Repository
**Goal:** `03` as code; startup step 2. **Depends on:** 1.3. **Adds:** fatal-error alert UI if the DB cannot open (names migration, error, backup path, then quits). **Size:** L.

**Steps**
1. `Store/Database.swift`: path `~/Library/Application Support/TokenBe/tokenbe.sqlite` (dir created `0700`), `DatabasePool` with configuration: `journal_mode=WAL`, `synchronous=NORMAL`, `foreign_keys=ON`, `auto_vacuum=INCREMENTAL`, `cache_size=-2000`, `mmap_size=0`, `busy_timeout=5000` (→ `db.busy` when waited > 100 ms), `temp_store=MEMORY`. `db.open {path,size_bytes,journal_mode,page_size}`.
2. `Store/Migrations/001_initial.sql`: the full DDL of `03` **plus seed rows**: `INSERT INTO schema_version(1, now)`; `INSERT INTO app(id='app_unassigned', name='unassigned', display_name='Unassigned', created_at=now, is_auto=1)` (sentinel for V4). `Store/Migrator.swift`: forward-only, one transaction per file, `db.migrate {from,to,dur_ms}` / `db.migrate_failed` (fault → fatal alert, DB untouched).
3. `Store/Integrity.swift`: `quickCheck()` at launch (`db.quick_check`), `integrityCheck()` (`db.integrity_check`), corrupt path: copy to `tokenbe.sqlite.corrupt-<ts>` (`db.corrupt`), restore from `tokenbe.sqlite.bak` if present (`db.restore`) else fresh DB; `backup()` via GRDB `backup(to:)` into temp + atomic rename (`db.backup` / `db.backup_failed`); `incrementalVacuum()` (`db.vacuum {pages_freed}`).
4. `Store/Records/*.swift`: one GRDB `Codable, FetchableRecord, PersistableRecord` type per table (`AccountRecord`, `ProviderKeyRecord`, `AppRecord`, `AppBindingRecord`, `UsageBucketRecord`, `CostBucketRecord`, `BalanceSnapshotRecord`, `HarnessEventRecord`, `IngestFileRecord`, `LedgerEventRecord`, `PriceSnapshotRecord`, `PriceOverrideRecord`, `PollStateRecord`, `BandStateRecord`).
5. `Store/Repository.swift` protocol — the complete method list for V1 is declared **now** (so later stages implement, never redesign): accounts (`insertAccount, updateAccount, deleteAccount, fetchAccounts`), providerKeys (`upsertProviderKeys, fetchProviderKeys`), usage (`upsertUsageBuckets, fetchUsage, repriceUsage`), cost (`upsertCostBuckets, fetchCost`), balance (`insertBalanceSnapshot, latestBalance`), ledger (`insertLedgerEvent, deleteUserLedgerEvent, fetchLedger`), prices (`insertPriceSnapshot, currentPriceSnapshot, setPriceOverride, deletePriceOverride, fetchPriceOverrides, prunePriceSnapshots`), poll (`loadPollState, savePollState`), band (`loadBandState, saveBandState`), apps (`upsertApp, fetchApps, bind, unbind, fetchBindings`), ingest (`loadIngestFiles, applyIngestBatch`), maintenance (`rollup, purgeHarnessEvents, thinBalanceSnapshots, backup, integrityCheck, quickCheck, incrementalVacuum, exportJSON, importJSON, exportCSV, stats`), observation (`observeSummaryInputs`). Methods not yet implemented **do not exist as stubs**: the protocol is split into extensions per aggregate, and each extension is added in the stage that implements it; this step declares only accounts and the maintenance methods 2.1 implements (`backup, integrityCheck, quickCheck, incrementalVacuum`); `observeSummaryInputs` is declared with its implementation in 2.2 (Q-024).
6. `GRDBRepository.swift` (actor-isolated writer; `ValueObservation` readers); `MemoryRepository` in the test target.
7. Startup step 2 wired; `FatalErrorAlert` (`NSAlert`) on failure then `NSApp.terminate`.
8. Fixture DB: `Tests/Fixtures/db/schema_v1.sqlite` generated by `Tests/TokenBeCoreTests/Support/FixtureDBBuilder.swift` (Q-024) (runs 001 + inserts representative rows) and committed; `corrupt.sqlite` = first 4 KiB of it.

**Inventory** — Files: `Store/{Database,Migrator,Integrity,Repository,GRDBRepository}.swift`, `Store/Migrations/001_initial.sql`, `Store/Records/*.swift` (14), `TokenBeApp/Components/FatalErrorAlert.swift`, `Tests/TokenBeCoreTests/Support/FixtureDBBuilder.swift`, `Tests/Fixtures/db/{schema_v1,corrupt}.sqlite`. DB: all 15 tables of `03`; seed rows `schema_version(1)`, `app('app_unassigned')`. Events: `db.open`, `db.migrate`, `db.migrate_failed`, `db.quick_check`, `db.integrity_check`, `db.integrity_failed`, `db.corrupt`, `db.restore`, `db.backup`, `db.backup_failed`, `db.vacuum`, `db.busy`. Settings: none.
**Tests:** `MigrationTests` (fresh → v1 with PRAGMA assertions; `schema_v1.sqlite` opens; seed rows present; corrupt → moved aside + fresh + `db.corrupt`; restore from `.bak`), `RepositoryAccountTests`.
**Verify:** tests; launch app → `tokenbe.sqlite` exists, WAL file exists, log has `db.open` and `db.migrate from=0 to=1`.
**Stage DoD:** D1–D3, D5, D7, D9–D12.

### Stage 2.2 — Observation plumbing & maintenance buttons
**Goal:** UI reads from the DB through `ValueObservation`; manual backup/integrity controls. **Depends on:** 2.1. **Adds:** Advanced → `Back up now`, `Run integrity check now` (with result sheet). **Size:** S.

**Steps**
1. `Store/Observation.swift`: `observeSummaryInputs() -> AsyncStream<SummaryInputs>` (accounts + poll_state + band_state + latest balance + ledger + recent buckets; the set grows per stage). `Ledger/AccountSummaryBuilder.swift` (Core) maps inputs → `[AccountSummary]` (in 2.2: only identity fields). `AppModel` subscribes.
2. Advanced tab: `Back up now` (→ `db.backup`, shows size and time; sets `tb.db.lastBackupAt`), `Run integrity check now` (→ `db.integrity_check`, sets `tb.db.lastIntegrityCheckAt`, shows `ok` or the first error line and the corrupt-copy path).

**Inventory** — Files: `Store/Observation.swift`, `Ledger/AccountSummaryBuilder.swift`, `SettingsUI/AdvancedTab.swift` (rows). Settings: `tb.db.lastBackupAt`, `tb.db.lastIntegrityCheckAt`. Events: reuse 2.1.
**Tests:** `ObservationTests` (insert account in temp DB → stream yields), `TokenBeUITests/AdvancedMaintenanceUITests` (click backup → `.bak` exists).
**Verify:** tests; after the UI test, `tokenbe.sqlite.bak` exists in the test's own `TOKENBE_TEST_ROOT` and both `tb.db.*` keys were written (both asserted by the test from its root and log); the owner's real support folder is unchanged (D10, Q-014, Q-025).
**Stage DoD:** D1–D6, D8–D12.

---

## 4. Phase 3 — Accounts (OpenAI end-to-end)

### Stage 3.1 — Network seam, error taxonomy, retry policy
**Goal:** all HTTP goes through one place; `PollError` and retry math exist and are tested without the network. **Depends on:** 2.2. **Adds:** nothing visible. **Size:** M.

**Steps**
1. `Network/HTTPTransport.swift`: `HTTPRequest {method, url, headers, body}`, `HTTPResponse {status, headers, body}`, protocol `send(_:) async throws(TransportError)`.
2. `Network/URLSessionTransport.swift`: ephemeral configuration, `timeoutIntervalForRequest 15`, `ForResource 30`, `waitsForConnectivity false`, `httpShouldSetCookies false`, `urlCache nil`, `User-Agent: TokenBe/<version> (+https://github.com/nbencic/tokenbe)`; response body capped at 20 MiB (`TransportError.tooLarge`).
3. `Network/PollError.swift` (04) + `PollError.from(_ response: HTTPResponse, now:)` and `PollError.from(_ error: TransportError)` mapping (401/403 → auth; 429 → rateLimited with `Retry-After` parsed as seconds or HTTP-date; 5xx → server; other non-2xx → providerRule, no retry; URLError → transport; Q-026).
4. `Network/RetryPolicy.swift`: pure `nextDelay(attempt:error:) -> Duration?` implementing `04 § Retry policy` with injected RNG (`SeededRNG` in tests), caps (`Retry-After` ≤ 300 s, backoff ≤ 15 min).
5. `Network/FixtureTransport.swift` (DEBUG only, used when the Bool `tb.debug.fixtureMode` of 09 is on): routes `(method, host+path)` → `Tests/Fixtures/providers/<p>/<endpoint>.<case>.{recorded,synthetic}.json`, case `ok` unless a per-endpoint case is given; each file is the envelope of 11 § Fixtures (Q-026); `StubTransport` in the test target records calls and asserts order.
6. `Network/NetworkMonitor.swift` protocol + `NWPathMonitorAdapter` (`Network.framework`); logs `app.network_changed {online}` on transition.

**Inventory** — Files: `Network/{HTTPTransport,URLSessionTransport,PollError,RetryPolicy,FixtureTransport,NetworkMonitor}.swift`, `Tests/TokenBeCoreTests/Support/{StubTransport,SeededRNG}.swift`. Settings: `tb.debug.fixtureMode` (DEBUG). Events: `app.network_changed`.
**Tests:** `PollErrorMappingTests`, `RetryPolicyTests` (table of attempt/error → delay incl. jitter bounds and caps), `URLSessionTransportTests` (headers via a local `URLProtocol` stub; size cap), `FixtureTransportTests` (envelope, routing, `StubTransport`), `NetworkMonitorTests` (transitions → `app.network_changed`).
**Verify:** tests; `check-no-secrets.sh` URL allowlist passes.
**Stage DoD:** D1–D3, D9, D11–D12.

### Stage 3.2 — Keychain seam
**Goal:** secrets stored and read per `04`/`11 § SEC-2`. **Depends on:** 3.1. **Adds:** nothing visible. **Size:** S.

**Steps**
1. `Keychain/KeyStore.swift` protocol: `get(ref) throws -> String?`, `set(ref, secret) throws`, `delete(ref) throws`.
2. `Keychain/KeychainKeyStore.swift`: `kSecClassGenericPassword`, service `dev.bathyon.tokenbe`, account = `keychain_ref`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`, on the login keychain (`kSecUseDataProtectionKeychain = false`: the data-protection keychain needs a provisioning-profile entitlement that ad-hoc-signed builds cannot have; owner's decision, Q-027); every `OSStatus ≠ errSecSuccess/errSecItemNotFound` → `keychain.read_failed` / `write_failed` / `delete_failed`; `errSecInteractionNotAllowed`/`errSecAuthFailed` → `keychain.access_denied` (fault).
3. Usage contract: callers `register` the secret with `Redactor` for the duration of the request and `unregister` after (`defer`).

**Inventory** — Files: `Keychain/{KeyStore,KeychainKeyStore}.swift`, `Tests/TokenBeCoreTests/Support/InMemoryKeyStore.swift`. Events: `keychain.read_failed`, `keychain.write_failed`, `keychain.delete_failed`, `keychain.access_denied`, `keychain.missing` (emitted by 3.5 startup step 3).
**Tests:** `KeyStoreTests` — unit tests on `InMemoryKeyStore`; one integration test `KeychainKeyStoreIntegrationTests` tagged `.keychainIntegration` using service `dev.bathyon.tokenbe.test` (write/read/overwrite/delete; attribute assertions via `SecItemCopyMatching` with `kSecReturnAttributes`: class, service, account, and no synchronizable copy, as far as the login keychain reports them, Q-027), skipped when the keychain cannot be written without interaction (locked or headless).
**Verify:** tests.
**Stage DoD:** D1–D3, D9, D11–D12.

### Stage 3.3 — Provider seam & registry
**Goal:** `ProviderAdapter`, `Capabilities`, probe result model, verified-provider gating. **Depends on:** 3.2. **Adds:** nothing visible. **Size:** M.

**Steps**
1. `Providers/ProviderID.swift` (moved from 0.3; 5 cases; display name, key prefixes from `02` — OpenAI and Anthropic only, 02 names none for the others; the glyph and the onboarding captions join the UI that draws them, 3.5/4.2; Q-028).
2. `Providers/Capabilities.swift` (`usage, cost, balance, perKeyUsage, keyNames, balanceModeDefault, usageLag: Duration, currencyHint`), `Codable` (stored as `account.capabilities` JSON).
3. `Providers/ProviderAdapter.swift`: `probe(key) async -> ProbeResult`, `pollUsage(ctx) async throws -> UsagePage…`, `pollCost`, `pollBalance`, `pollKeys`; `PollContext {accountID, key, cursor, window, transport, clock}`. `ProbeResult {capabilities, humanMessage?, discoveredKeys, orgID?, orgName?, currency, rawBodiesRedacted}`.
4. `Providers/ProviderRegistry.swift`: `adapters: [ProviderID: any ProviderAdapter]`, `verified: Set<ProviderID>` read from `Providers/Verified.swift` (`static let verified: Set<ProviderID> = []` initially), `availableForOnboarding` = `verified` in Release, all in DEBUG.
5. `VerifiedProvidersTests`: for every member of `verified`, `Tests/Fixtures/providers/<p>/RECORDED` must exist and contain a date; for every provider with a `RECORDED` marker, it must be in `verified` (both directions).
6. `scripts/record-fixtures.sh <provider>`: curls each endpoint of `02` for that provider with the env key (sent to curl on stdin, never argv), redacts as 11 § Fixtures says (keys → `sk-FIXTURE-<provider>-<last4>`, 07's header patterns, `org_fixture`/`proj_fixture`), writes `*.recorded.json` in 11's envelope keeping only `Content-Type` and `Retry-After`, writes `RECORDED` with the date (`YYYY-MM-DD`), and runs `--verify-redacted` (`check-no-secrets.sh --root`). Human-run only (Q-028).

**Inventory** — Files: `Providers/{ProviderID,Capabilities,ProviderAdapter,ProviderRegistry,Verified}.swift`, `scripts/record-fixtures.sh`. Events: none new.
**Tests:** `VerifiedProvidersTests`, `ProviderIDTests` (prefix validation table from `02`), `CapabilitiesTests` (pinned JSON shape), `ProviderRegistryTests` (onboarding availability).
**Verify:** tests; `scripts/record-fixtures.sh --self-test` (runs the redactor over a canned body with fake keys).
**Stage DoD:** D1–D3, D9, D11–D12.

### Stage 3.4 — OpenAI adapter (on synthetic fixtures)
**Goal:** every OpenAI endpoint of `02` decoded, normalized, written. **Depends on:** 3.3. **Adds:** nothing visible (no account UI yet). **Size:** L.

**Steps**
1. `Tests/Fixtures/providers/openai/*.synthetic.json`: `projects.ok`, `api_keys.ok`, `usage_completions.ok` + `usage_completions.page2` (2 pages), `usage_completions.empty`, `costs.ok`, `projects.401`, `costs.403`, `usage_completions.429` (with `Retry-After`), `usage_completions.500` — `<endpoint>.<status>` like the recorder (Q-029); field names strictly from `02`; synthetic files never satisfy `RECORDED` (D-synthetic-fixtures).
2. `Providers/OpenAI/DTOs.swift`: lenient `Decodable` with unknown-key collection (`poll.unknown_keys` once per day), required-field failures → `PollError.decode(field:path:)`.
3. `Providers/OpenAI/Normalizer.swift`: row 1 of `05 § Normalizers`; negative clamp → `normalize.negative`.
4. `Providers/OpenAI/Probe.swift`: 4-step sequence of `02`, per-step capability flags, human messages from `02 § Errors` (in `Strings` for Core → `CoreStrings.swift`).
5. `Providers/OpenAI/Client.swift`: `pollKeys` (projects → api_keys; upsert `provider_key` with `name`, `redacted`, `project_id`, status), `pollUsage` (1h buckets, last 48 h, `group_by[]` ×3, paging with `cursor` saved in `poll_state` after each page, `provisional` flag, V2 write-completeness assertion), `pollCost` (7 days, `group_by api_key_id,line_item` → `cost_bucket` rows + one `total` row per day computed as the sum). Every response body → `Redactor` → `poll_state.last_raw` (≤ 64 KiB).
6. `Scheduling/Poller.swift` (Core, not scheduled yet): `runOnce(account, job)` executes an adapter job with retry policy, updates `poll_state` (attempt/success/failure/consecutive/circuit), emits `poll.start/ok/retry/failed/rate_limited/auth_failed/circuit_open/schema_drift/provider_rule`.
7. `Repository` extensions: providerKeys, usage, cost, poll.

**Inventory** — Files: `Providers/OpenAI/{DTOs,Normalizer,Probe,Client}.swift`, `Normalize/TokenClasses.swift`, `Scheduling/Poller.swift`, `Store/Repository+{ProviderKeys,Usage,Cost,Poll}.swift`, `Core/CoreStrings.swift`, `Network/NoNetworkInTests.swift` (PM-3.1-1), fixtures above, `Fixtures/expected/normalize.csv` (openai rows). DB: `provider_key`, `usage_bucket`, `cost_bucket`, `poll_state` written. Events: `poll.start`, `poll.ok`, `poll.retry`, `poll.failed`, `poll.rate_limited`, `poll.auth_failed`, `poll.circuit_open`, `poll.circuit_close`, `poll.schema_drift`, `poll.unknown_keys`, `poll.provider_rule`, `poll.write_incomplete` (V2, Q-029), `normalize.negative`, `normalize.unknown_keys`.
**Tests:** `AdapterTests/OpenAITests` (each fixture case → exact rows; probe messages for 401/403/429/500; paging cursor persistence after injected failure between pages; last_raw redacted and ≤ 64 KiB), `NormalizerTests` (openai rows of `expected/normalize.csv`), `PollStateTests`, `PollerTests` (retry sequence with `TestClock` + `SeededRNG`; circuit after 3 auth failures; decode no retry).
**Verify:** tests; `check-no-secrets.sh` over fixtures.
**Stage DoD:** D1–D3, D5, D9, D11–D12.

### Stage 3.5 — Onboarding, Accounts tab, first account
**Goal:** a user adds an OpenAI account; startup step 3; popover shows the account card in its pre-data state; Keys & apps table lists discovered keys. **Depends on:** 3.4. **Adds:** `Add account…` in the empty state; onboarding sheet (3 steps); Accounts tab; sidebar account rows; account card (row 1 + "No data yet" + freshness `never`). **Size:** L.

**Steps**
1. `Onboarding/{OnboardingSheet,Step1Provider,Step2Key,Step3Result}.swift` per `08`: tiles from `registry.availableForOnboarding` (others absent, added ones disabled with `Added`); secure field + `Paste`; live prefix validation message; `Test & continue` runs `probe` with spinner (10 s timeout → transport error message); on success: Keychain write (`ref = provider.rawValue`), `account` insert (`id` UUID, `label`, `balance_mode` from capabilities, `currency`, `capabilities` JSON, `created_at`), `poll_state` rows seeded for the 4 jobs, discovered keys upserted, `tb.ui.onboardingDone = true`; Step 3 shows mode/key count/currency, `Launch at login` checkbox, and — for anchored accounts — the inline anchor amount field (saved as `ledger_event(kind=anchor)`; the ledger math lands in 5.3, the row is written now) or `Skip for now`. `Done` → immediate `Poller.runOnce` for `keys` and `usage` (fire-and-forget, logged).
2. Accounts tab (`SettingsUI/AccountsTab.swift`): list (184 pt) + detail: label (editable → `updateAccount`), key status line (`Valid · tested <freshness>` from `poll_state`), `Replace key…` (sheet reusing Step 2; resets circuit), `Test` (probe; resets circuit; shows message), `Remove account…` (confirm; `deleteAccount` cascade, Keychain delete, `tb.popover.expanded.<p>` and `tb.alerts.snoozedUntil.<p>` removed), `Paused` toggle (writes `account.paused`; consumer arrives in 4.1 — allowed as in 1.3 rule), **Keys & apps** table (name, hint, created, last used; bound-app picker arrives in 7.1).
3. Startup step 3: load accounts; read each Keychain item; missing → `keychain.missing` and `AccountSummary.needsKey = true` → card row 2 reads `Key missing · Fix…` (opens Accounts tab).
4. Sidebar: one row per account (glyph, label, band dot `unknown`).
5. Popover: cards sorted by `tb.popover.sort` (name order works now; runway/remaining fall back to name until 5.3).

**Inventory** — Files: `Onboarding/*.swift`, `SettingsUI/AccountsTab.swift`, `Dashboard/SidebarView.swift` (rows), `Popover/AccountCardView.swift` (rows), `Store/Repository+Ledger.swift` (insert only). DB: `account` rows; `poll_state` ×4 seeded per account; `provider_key` rows; `ledger_event(kind=anchor)` optional. Settings: `tb.ui.onboardingDone`, `account.label`, `account.paused`. Events: `keychain.missing`, `ledger.anchor_set`, `ui.error`.
**Tests:** `TokenBeUITests/OnboardingUITests` (fixture mode: happy path creates account, DB has 1 account + 4 poll_state rows + N provider_key rows; wrong-prefix message; 401 message; Remove account deletes Keychain item — checked via the test's own `KeychainKeyStore` read), `AccountLifecycleTests` (Core: create/remove cleanup).
**Verify:** UI tests; `sqlite3 tokenbe.sqlite "select count(*) from poll_state"` == 4 after onboarding.
**Stage DoD:** D1–D12 (first stage where all apply).

### Stage 3.6 — Verify OpenAI against the live API (H2)
**Goal:** replace synthetic with recorded fixtures; resolve every OpenAI `[expected]` in `02`; mark OpenAI verified. **Depends on:** 3.5 + H2. **Adds:** OpenAI tile visible in Release onboarding. **Size:** S (agent) + H2.

**Steps**
1. H2: `OPENAI_ADMIN_KEY=… scripts/record-fixtures.sh openai` on Nikola's Mac; commit `Tests/Fixtures/providers/openai/*.recorded.json` + `RECORDED`.
2. Agent: diff recorded vs synthetic field-by-field; update DTOs/tests; edit `02` (remove `[expected]` on confirmed fields, correct any wrong one in the same PR); `Verified.verified.insert(.openai)`; delete the now-redundant synthetic files that have a recorded counterpart (keep error cases that cannot be recorded: 429/500 stay synthetic and are labeled so in `11`).
3. Run the app in Debug against the live key once (manual, Nikola present): first poll writes buckets; log reviewed for `error` records → each one fixed or logged in `QUESTIONS.md`.

**Inventory** — Fixtures: `openai/*.recorded.json`, `openai/RECORDED`. Files: `Verified.swift`, `02-provider-apis.md`.
**Tests:** existing adapter tests now run on recorded fixtures.
**Verify:** `VerifiedProvidersTests`; `grep -c "\[expected\]" docs/02-provider-apis.md` decreased for the openai section to 0.
**Stage DoD:** D1–D3, D9, D11–D12. **While waiting for H2:** proceed to 4.1.

---

## 5. Phase 4 — Scheduling

### Stage 4.1 — Scheduler, coordinator, pollers; Sources tab; Refresh/Pause
**Goal:** polls run on their own per `04`. **Depends on:** 3.5. **Adds:** popover header `Refreshed … ago` + refresh button; footer `Pause polling for 1 h` / `Resume`; Sources tab (intervals, Low Power multiplier); Accounts `Paused` toggle takes effect. **Size:** L.

**Steps**
1. `Scheduling/Job.swift` (`usage, cost, balance, keys`; which jobs apply = from `Capabilities`), `Scheduling/SchedulerLoop.swift` (04 pseudo-code; `ContinuousClock`; tolerance 5 s; `sched.tick` debug; `sched.skip {reason}`), `Scheduling/AccountPoller.swift` (actor; `inFlight`; phase recording; `sched.overlap_skipped`; overrun cancel at 2× interval → `sched.overrun`), `Scheduling/PollCoordinator.swift` (actor; owns pollers; add/remove on account changes; `refreshNow(account?)`; pause/resume; reacts to `Settings.changes` for intervals; Low Power ×4 on `NSProcessInfoPowerStateDidChange` → `sched.low_power`; `NSWorkspace.didWakeNotification` and wall-vs-monotonic drift > 30 s → `sched.clock_jump` and `nextDue` recomputed from now; `NetworkMonitor` offline → `sched.skip reason=offline`).
2. Startup step 6 (coordinator start, first tick immediately).
3. Sources tab (`SettingsUI/SourcesTab.swift`): `Balance every`, `Anthropic usage every`, `OpenAI usage every`, `Keys every`, `Low Power multiplier`, `Run daily tasks now` (button appears in 4.3).
4. Popover header: freshness = min over accounts' `last_success_at`; refresh button → `refreshNow()`; spins while any job in flight. Footer: `Pause polling for 1 h` → `tb.poll.pausedUntil = now+3600`; header shows `Paused · resumes HH:mm` + `Resume`.
5. `AppModel` gets `isPaused`, `inFlightCount` from the coordinator via an `AsyncStream<CoordinatorState>`.

**Inventory** — Files: `Scheduling/{Job,SchedulerLoop,AccountPoller,PollCoordinator}.swift`, `SettingsUI/SourcesTab.swift`, popover header/footer edits. Settings: `tb.poll.balanceIntervalS`, `tb.poll.usageIntervalAnthropicS`, `tb.poll.usageIntervalOpenAIS`, `tb.poll.keysIntervalS`, `tb.poll.lowPowerMultiplier`, `tb.poll.pausedUntil`, `account.paused`, `account.interval_override_json` (read; UI for overrides is an Accounts-tab disclosure added here). Events: `sched.tick`, `sched.skip`, `sched.overlap_skipped`, `sched.overrun`, `sched.clock_jump`, `sched.low_power`, `app.network_changed`.
**Tests:** `SchedulerTests` (all cases of `11`), `CoordinatorTests` (overlap → one network call + one `sched.overlap_skipped`; pause/resume; account add/remove), `TokenBeUITests/RefreshPauseUITests`.
**Verify:** tests; run app 3 min in fixture mode → log shows `poll.ok` for `usage` at the configured cadence ±5 s (script parses timestamps).
**Stage DoD:** D1–D12; `04 § Definition of done` overlap and clock-jump items.

### Stage 4.2 — Freshness, stale, offline; account page shell
**Goal:** every freshness/stale/offline state of `08`; account detail page header, badges row, sources strip. **Depends on:** 4.1. **Adds:** sidebar account row click → account page (header, badges with help popovers, sources strip); card stale overlay; offline banner; glyph `dashed` state. **Size:** M.

**Steps**
1. `Ledger/Freshness.swift` (Core): `isStale = now − last_success > staleMultiplier × interval` per job → account stale if its primary job (usage for anchored, balance for direct) is stale.
2. `Dashboard/AccountDetailView.swift`: header (`AM-0`, `AR-0`), badges row (`B1-0`: Balance/Usage/Cost/Lag from `Capabilities`, each with a one-sentence help popover from `02`), sources strip (`HP-0`: per job `ok/failed/n/a`, last success, next due, human error from `poll_state.last_error_message`). Numbers strip and tables come in 5.3/7.1/8.1.
3. Popover: stale overlay (opacity 0.6, freshness in `HealthLow`), `Offline — showing last known values` banner (secondary tone), glyph `.dashed` when any account stale or offline.
4. Sidebar account rows reflect `needsKey` (`Key missing`).

**Inventory** — Files: `Ledger/Freshness.swift`, `Dashboard/AccountDetailView.swift`, `Dashboard/{BadgesRow,SourcesStrip}.swift`. Settings: `tb.alerts.staleMultiplier` (read; Alerts tab UI in 5.3). Events: none new.
**Tests:** `FreshnessTests`, `TokenBeUITests/StaleOfflineUITests` (fixture transport set to fail → after 3× interval card dims and glyph identifier `glyph.dashed`).
**Verify:** tests; E2E-5 of `11`.
**Stage DoD:** D1–D12.

### Stage 4.3 — Daily activity
**Goal:** `NSBackgroundActivityScheduler` runner with a step registry; cost polls, backup, weekly integrity, vacuum registered. **Depends on:** 4.2. **Adds:** Sources → `Run daily tasks now`; Advanced shows `Last daily run`. **Size:** S.

**Steps**
1. `Scheduling/DailyActivity.swift` (Core): ordered registry of `DailyStep {name, run}`; runs all steps even if one throws; `sched.daily_start/end {dur_ms, steps_ok, steps_failed}`; each step's duration logged in `ctx`. App registers the scheduler (`dev.bathyon.tokenbe.daily`, 86400/3600, `.utility`, repeats) in startup step 7.
2. Steps registered now, in `04`'s order: `cost polls` (all accounts with `capabilities.cost`), `db backup` (`db.backup`), `weekly integrity_check` (every 7th run, counter in `tb.daily.runCount`), `incremental_vacuum`. (Roll-ups → 9.1, price refresh → 5.1, update check → 9.4 insert themselves at their `04` position.)
3. `tb.daily.lastRunAt`, `tb.daily.runCount` written after each run; `09` updated (replaces `tb.poll.costDailyLocalTime`, which `NSBackgroundActivityScheduler` cannot honor — D-daily-no-fixed-time).

**Inventory** — Files: `Scheduling/DailyActivity.swift`, `TokenBeApp/DailyActivityRegistration.swift`, Sources/Advanced rows. Settings: `tb.daily.lastRunAt`, `tb.daily.runCount`, `tb.db.lastBackupAt`, `tb.db.lastIntegrityCheckAt`. Events: `sched.daily_start`, `sched.daily_end`, `db.backup`, `db.integrity_check`, `db.vacuum`.
**Tests:** `DailyActivityTests` (step failure does not stop later steps; order; weekly gate), `TokenBeUITests/DailyRunNowUITests`.
**Verify:** tests; `Run daily tasks now` → log sequence `sched.daily_start … db.backup … db.vacuum … sched.daily_end`.
**Stage DoD:** D1–D12.

---

## 6. Phase 5 — Money

### Stage 5.1 — Price book
**Goal:** `05 § Price lookup` with bundled snapshot, daily feed, overrides, UI. **Depends on:** 4.3. **Adds:** Sources → **Price book** group (feed toggle, last refresh, `Refresh now`, overrides table with `+`/`−`, `Reset to feed`); account page numbers strip shows `Unpriced` later (5.2). **Size:** M.

**Steps**
1. `scripts/update-bundled-prices.sh`: downloads the LiteLLM JSON, strips entries with `mode != chat`, writes `Sources/TokenBeApp/Resources/prices.bundled.json` + `prices.bundled.sha256`; run at every release (10) and now once.
2. Startup step 4: if no `price_snapshot.is_current`, insert the bundled file as version `bundled-<appversion>` with `is_current=1` (`price.feed_ok {source=bundled}`).
3. `Pricing/PriceFeedFetcher.swift`: `GET` feed with `If-None-Match`, 10 s timeout, 20 MB cap, sha256 dedupe (same hash → no new row), `price.feed_ok` / `price.feed_failed {reason}` / `price.parse_failed`; shape check (O-6); `prunePriceSnapshots(keep: 4)`.
4. `Pricing/PriceBook.swift` (actor): parsed map cached; `lookup(provider, model) -> PriceEntry?` implementing the 6 steps and V5; override CRUD (`price.override_set`); `price.stale` when the current snapshot is older than `tb.price.staleAfterDays` (checked daily and at launch).
5. Daily step `price refresh` registered after `roll-ups` position (roll-ups themselves arrive in 9.1).
6. Sources tab Price book UI; Sources strip gets a `Prices · <date> · ok/stale` chip.

**Inventory** — Files: `Pricing/{PriceFeedFetcher,PriceBook,PriceEntry,Lookup}.swift`, `Resources/prices.bundled.json`, `Resources/prices.bundled.sha256`, `scripts/update-bundled-prices.sh`, `Store/Repository+Prices.swift`, Sources tab group. DB: `price_snapshot` (seed row `bundled-<v>` at first launch), `price_override`. Settings: `tb.price.feedEnabled`, `tb.price.feedURL`, `tb.price.staleAfterDays`. Events: `price.feed_ok`, `price.feed_failed`, `price.parse_failed`, `price.stale`, `price.override_set`.
**Tests:** `PriceLookupTests` (6 steps, V5, override precedence, date-suffix, `-latest`), `PriceFeedTests` (ETag 304 path, size cap, parse failure keeps previous, shape-change O-6, prune to 4), `TokenBeUITests/PriceBookUITests` (add override → DB row; reset).
**Verify:** tests; first launch log has `price.feed_ok source=bundled`; `sqlite3 … "select count(*) from price_snapshot"` == 1.
**Stage DoD:** D1–D12.

### Stage 5.2 — Cost estimation & unpriced surfacing
**Goal:** `usage_bucket.est_cost_cents/unpriced` always populated; re-pricing on snapshot change. **Depends on:** 5.1. **Adds:** account page **numbers strip** (`Spend today`, `Spend in range`, `Unpriced in range` when > 0) — remaining/runway cells arrive in 5.3; Overview `Total spend` subline. **Size:** M.

**Steps**
1. `Pricing/CostEstimator.swift`: `05 § Cost formula` (cents, round half-up once; fallback multipliers → `price.fallback_multiplier`; tier priced as standard logged `tier_priced_as_standard` in ctx); `_above_200k` not applied (05).
2. Applied in `upsertUsageBuckets` (every write) and by `repriceUsage(accountID, since: now−90 d)` when the current price snapshot changes (`price.repriced {rows}`) — one transaction per account.
3. `price.unpriced {provider, model}` once per model per UTC day (dedupe table in memory keyed by day).
4. Numbers strip (`Dashboard/NumbersStrip.swift`) with the cells above; Overview subline `Total spend <range> $X`.

**Inventory** — Files: `Pricing/CostEstimator.swift`, `Dashboard/NumbersStrip.swift`, `Store/Repository+Usage.swift` (`repriceUsage`). Events: `price.fallback_multiplier`, `price.unpriced`, `price.repriced`.
**Tests:** `CostFormulaTests` (`expected/pricing.csv`), `RepriceTests` (snapshot change updates rows, unpriced flips when a price appears).
**Verify:** tests; after a usage poll in fixture mode, `select count(*) from usage_bucket where est_cost_cents is null and unpriced=0` == 0.
**Stage DoD:** D1–D12.

### Stage 5.3 — Ledger, runway, bands; Alerts tab; cards and Overview complete
**Goal:** the product's core numbers per `05`; `08` popover cards, alert banner, Overview headline and runway board; account page ledger list and anchor/top-up sheets. **Depends on:** 5.2. **Adds:** all of the above; Alerts tab thresholds group; Accounts auto-reload controls; Day-1 collecting state; `Set anchor…` link in `unknown` rows. **Size:** L.

**Steps**
1. `Ledger/{Spend,Burn,Remaining,EstimateBand,Runway,BandEvaluator}.swift` implementing every formula of `05` (UTC days; `burn_7d` needs ≥ 2 closed days; `burn_today` gates; `M`; band order; auto-reload override; V1 invariant → `unknown` + nudge).
2. `AccountSummaryBuilder` fills every optional; `band_state` written with `inputs_json` in the same transaction as the summary's band change (V6) and `ui.band_change {from,to,inputs}` logged only on change.
3. Sheets: `Dashboard/SetAnchorSheet.swift`, `AddTopUpSheet.swift` (fields/validation per `08`; `ledger.anchor_set`, `ledger.topup`); account page `Ledger` list (`08 §7`; user rows deletable → `deleteUserLedgerEvent`; system rows not); header buttons `Set anchor…`, `Add top-up…`, `Refresh`.
4. Popover cards complete: row 2 pinned metric with `±`, row 3 two paces / spend-only text, Day-1 `Collecting… runway after 2 days of data`, sort by runway/remaining/name/manual (`unknown` last), alert banner (one line, band tint 12 %, tap → account page), ↑/↓/⏎ keyboard navigation.
5. Overview: headline (`Q1-0/Q2-0`: shortest runway in band color; subline total remaining USD-only + `+ N non-USD`), runway board (`QD-0…`; columns per `08`; `Set anchor…` link for `unknown`).
6. Alerts tab (`SettingsUI/AlertsTab.swift`): `watchDays`, `lowDays`, `criticalDays` (repair rule), `dollarFloorCents`, `staleMultiplier`, `driftThresholdPct` (consumer 8.1 — allowed), `anchorAgeDays`. Notification toggles arrive in 5.4.
7. Accounts tab: auto-reload toggle + `below` + `to` amounts (anchored accounts only).

**Inventory** — Files: `Ledger/*.swift` (6), `Dashboard/{SetAnchorSheet,AddTopUpSheet,LedgerList,RunwayBoard,OverviewHeadline}.swift`, `Popover/{AlertBanner,AccountCardView}.swift`, `SettingsUI/AlertsTab.swift`, `Store/Repository+{Ledger,Band}.swift`, `scripts/check-traceability.sh`. DB: `ledger_event` (anchor/topup/note/reconcile), `band_state` rows (one per account after first evaluation). Settings: `tb.alerts.watchDays`, `tb.alerts.lowDays`, `tb.alerts.criticalDays`, `tb.alerts.dollarFloorCents`, `tb.alerts.anchorAgeDays`, `tb.alerts.driftThresholdPct`, `tb.popover.pinnedMetric` (consumed), `tb.popover.sort`/`manualOrder` (consumed), `tb.popover.expanded.<p>` (row 4 toggle — rendered with top apps in 7.1; the chevron appears in 7.1), `account.auto_reload_*`. Events: `ledger.anchor_set`, `ledger.topup`, `ledger.reconcile`, `ui.band_change`.
**Tests:** `LedgerTests` (`expected/ledger.csv` + every nil combination + auto-reload + negative clamp + `M ≥ remaining`), `BandTransitionTests` (row + log only on change; V6 same transaction via injected failure), `BurnTests` (gates), `TokenBeUITests/AnchorRunwayUITests` (set anchor → card shows `≈ $… ± …`; Day-1 text; banner when fixture drives critical).
**Verify:** tests; E2E-2 of `11`; E2E-9 via `scripts/check-traceability.sh` (joins each `ui.band_change` to a preceding `poll.ok`/`ledger.*` record for the same `acct` within 2 s).
**Stage DoD:** D1–D12; `05 § Definition of done`.

### Stage 5.4 — Notifications
**Goal:** `08 § Notifications` + `09 § Alerts` notification keys. **Depends on:** 5.3. **Adds:** Alerts tab notification toggles, quiet hours, `Send test notification`; macOS notifications on band transitions with `Open`/`Snooze 24 h`. **Size:** M.

**Steps**
1. `Notifications/Notifier.swift` protocol, `UNNotifier` (category `band`, actions `open`, `snooze`; authorization requested at the **first** band alert, not at launch; denied → `ui.notification_denied` and Alerts tab banner with `Open System Settings` button — O-11).
2. `Notifications/AlertPolicy.swift` (Core): transitions INTO `low`/`critical`/`unknown>24h`/`stale>6h`; max one per account per band per 24 h; quiet hours queue (flush at end); snooze via `tb.alerts.snoozedUntil.<p>`; body copy per `08`; `ui.notification_sent {suppressed_by_quiet_hours}`.
3. Alerts tab controls; `Send test notification`.

**Inventory** — Files: `TokenBeApp/Notifications/{Notifier,UNNotifier}.swift`, `Core/Ledger/AlertPolicy.swift`, `Tests/Support/RecordingNotifier.swift`, Alerts tab rows. Settings: `tb.alerts.notify.low`, `tb.alerts.notify.critical`, `tb.alerts.notify.unknown`, `tb.alerts.notify.stale`, `tb.alerts.quietHoursEnabled`, `tb.alerts.quietStart`, `tb.alerts.quietEnd`, `tb.alerts.snoozedUntil.<p>`. Events: `ui.notification_sent`, `ui.notification_denied`.
**Tests:** `AlertPolicyTests` (every rule incl. quiet-hours wrap past midnight and 24 h dedupe), `TokenBeUITests/NotificationsSettingsUITests`.
**Verify:** tests; E2E-4 of `11` (fixture drives critical → exactly one notification recorded by `RecordingNotifier` in a Core test; UI test checks the settings).
**Stage DoD:** D1–D12.

### Stage 5.5 — Menu bar glyph completion & metric
**Goal:** glyph `notched` state and the optional metric text; startup step 8. **Depends on:** 5.4. **Adds:** menu bar text (`12d`, `$42`, `$3.10`) per `tb.menubar.metric`; notch on any low/critical. **Size:** S.

**Steps**
1. `AppModel.glyphState`: `.dashed` if any stale/offline, else `.notched` if any `low`/`critical`, else `.solid`. Text from `AccountSummary` per metric, width ≤ 64 pt.
2. Startup step 8: render from persisted `band_state` before the first poll.

**Inventory** — Files: `Components/MenuBarGlyph.swift`, `AppModel.swift`. Settings: `tb.menubar.metric` (consumed). Events: none new.
**Tests:** `GlyphStateTests` (Core logic extracted to `Model/GlyphState.swift`), `TokenBeUITests/GlyphMetricUITests`.
**Verify:** tests.
**Stage DoD:** D1–D12.

---

## 7. Phase 6 — Direct-balance providers

### Stage 6.1 — DeepSeek adapter (+H3)
**Goal:** direct balance, CNY/USD, `balance` job live. **Depends on:** 5.5. **Adds:** DeepSeek tile (Release only after `RECORDED`), direct cards without `≈`, `CN¥` formatting, Overview `+ N non-USD`. **Size:** M.

**Steps**
1. Synthetic fixtures `deepseek/balance.{ok,cny,unavailable}.synthetic.json`, `auth.401`.
2. `Providers/DeepSeek/{DTOs,Probe,Client}.swift`: `GET /user/balance`; strings → cents via `Decimal`; one `balance_snapshot` per currency entry; account currency = first entry; `is_available == false` → remaining shown, band forced `critical`, header chip `Provider reports account unavailable` (D-deepseek-unavailable).
3. `balance` job scheduled (60 s); direct mode in `Remaining` (band `±` = 0); Formatters `CN¥`.
4. H3 (deepseek): record, reconcile `02`, `Verified += .deepseek`.

**Inventory** — Files: `Providers/DeepSeek/*.swift`, `Store/Repository+Balance.swift`, fixtures. DB: `balance_snapshot`. Events: `poll.*` for `deepseek`. Settings: `tb.poll.balanceIntervalS` (consumed).
**Tests:** `AdapterTests/DeepSeekTests` (string parsing incl. `"110.00"`, two currencies, unavailable), `FormattersTests` (CN¥), `OverviewTotalsTests` (USD-only sum + suffix).
**Verify:** tests; `VerifiedProvidersTests` after H3.
**Stage DoD:** D1–D12.

### Stage 6.2 — xAI adapter (+H3)
**Goal:** D-xai-balance resolved by fixture. **Depends on:** 6.1. **Adds:** xAI tile (Release only after `RECORDED`). **Size:** S.

**Steps**
1. Synthetic fixtures `xai/api_key.{ok,no_balance}.synthetic.json`.
2. `Providers/XAI/*.swift`: probe `GET /v1/api-key`; if `remaining_balance` numeric → `direct` else `anchored` (`poll.provider_rule rule=xai_no_balance_field`).
3. H3 (xai) if a key exists: record; update `13 § D-xai-balance` with the recorded shape; `Verified += .xai`. If no key: xAI stays unverified (gated) and this is written to `QUESTIONS.md` as resolved-by-scope.

**Inventory** — Files: `Providers/XAI/*.swift`, fixtures. Events: `poll.provider_rule`.
**Tests:** `AdapterTests/XAITests` (both shapes → mode).
**Verify:** tests.
**Stage DoD:** D1–D12.

---

## 8. Phase 7 — Apps & attribution

### Stage 7.1 — Apps bound to provider keys
**Goal:** `app`/`app_binding` CRUD; By-app table via provider key ids; Keys & apps binding UI; Apps sidebar. **Depends on:** 6.2. **Adds:** account page **By app** table (`20N-0`), Keys & apps `Bound app` picker + `New app…`, `(unnamed key …a9f2)` rows with `Name…`, Overview `Apps this period` (badge `key`), sidebar `Apps` section with display-name editing, popover card row 4 (top 3 apps, chevron, `tb.popover.expanded.<p>`). **Size:** L.

**Steps**
1. `Store/Repository+Apps.swift`; `Ledger/Attribution.swift` (Core): per account/range, per provider key: spend from `cost_bucket(group_kind=api_key_id)` where available else `usage_bucket.est_cost_cents` grouped by `provider_key_id`; map keys → apps via `app_binding(kind=provider_key)`; unbound keys → `(unnamed key …hint)` rows; `Σ apps == provider total` with remainder to largest; badge `key`. The split/substitute/inferred paths are added in 7.2 in the same file.
2. UI: `Dashboard/ByAppTable.swift`, Keys & apps picker (`New app…` → `upsertApp` with `name` slug derived from display name per `06` regex; collision → suffix `-2`), Overview `AppsThisPeriod.swift`, `Dashboard/AppsPage.swift` (flat list; `display_name` editable; `name` immutable per O-13), popover row 4.

**Inventory** — Files: `Store/Repository+Apps.swift`, `Ledger/Attribution.swift`, `Dashboard/{ByAppTable,AppsThisPeriod,AppsPage}.swift`, Accounts tab picker, popover row 4. DB: `app`, `app_binding`. Settings: `tb.popover.expanded.<p>` (consumed). Events: none new (`ui.error` on failures).
**Tests:** `AttributionTests` (key path: totals equal, remainder rule, unbound rows), `TokenBeUITests/AppsBindingUITests` (bind key → By-app row renamed; Total equals provider total).
**Verify:** tests; A2 check in fixture mode.
**Stage DoD:** D1–D12.

### Stage 7.2 — Harness ingest
**Goal:** `06` complete. **Depends on:** 7.1. **Adds:** Sources → **Harness reports** group (folder path, `Reveal in Finder`, watch toggle, move-when-done toggle, status line, counters, `Copy reporter snippet` Python/Node); By-app rows with badges `harness` / `≈ split` / `inferred`; empty By-app table shows `Report apps from your harness →` (opens Sources). **Size:** L.

**Steps**
1. Startup step 5 creates `~/Library/Application Support/TokenBe/ingest/{,ingested,rejected}` (`ingest.folder_recreated` if missing after first launch; unwritable → `ingest.folder_unwritable` + red status).
2. `Ingest/FileWatcher.swift` protocol; `FSEventsWatcher` (flags/latency per `06`); `PollingWatcher` (30 s) used when FSEvents fails (`ingest.fsevents_failed`); `ingest.start {files, mode}` / `ingest.stop`.
3. `Ingest/LineParser.swift` (v1 validation table → typed `HarnessLine` or a rejection reason), `Ingest/Tailer.swift` (offsets, 64 KiB chunks, partial-line rule, inode/truncation detection), `Ingest/IngestService.swift` (actor; `fileChanged`; quiescence 2 s; lock-attempt move rule; rejected-file rule; burst batching 1 000 lines/transaction; counters; `applyIngestBatch` as ONE transaction (V7)).
4. `processLine` exactly per `06`: `INSERT OR IGNORE harness_event` (dedup), app resolve/create (`is_auto=1`, `ingest.app_created`), binding `harness_tag`, key-hint resolution (ambiguous → `ingest.key_hint_ambiguous`), normalize (05 rows for openai/anthropic/deepseek/xai per-response; openrouter `cost_cents`), price, `usage_bucket(source=harness)` upsert; unknown provider account → stored, counted (O-12).
5. `Attribution.swift` gains: split (proportional by harness `est_cost_cents`, fallback tokens; badge `≈ split`), substitute (no provider usage: harness is the only spend; badge `harness`), inferred (D-deepseek-single-app; badge `inferred`), reconciliation `ledger.harness_drift` on closed days.
6. Sources tab group + `Copy reporter snippet` (copies `docs/reporters/*` content bundled as resources); README section with the snippets.

**Inventory** — Files: `Ingest/{FileWatcher,FSEventsWatcher,PollingWatcher,LineParser,Tailer,IngestService}.swift`, `Store/Repository+Ingest.swift`, `Resources/reporters/{tokenbe_report.py,tokenbe_report.js}`, Sources tab group, `README.md` section. DB: `harness_event`, `ingest_file`, `usage_bucket(source=harness)`, `app(is_auto=1)`, `app_binding(kind=harness_tag)`. Settings: `tb.ingest.enabled`, `tb.ingest.moveWhenDone`, `tb.ingest.folderPath`. Events: every `ingest.*` in `07`, `normalize.failed`, `ledger.harness_drift`.
**Tests:** `LineParserTests` (every rejection reason), `IngestTailerTests` (all cases of `11`), `AttributionTests` (split/substitute/inferred), `TokenBeUITests/HarnessIngestUITests` = E2E-3 (bursts; `app.terminate()` mid-burst; relaunch; counts), `TokenBeUITests/HarnessRejectedUITests`.
**Verify:** tests; A3 timing: file lands → row within 5 s (script with `fswatch`-free loop reading sqlite).
**Stage DoD:** D1–D12; `06 § Definition of done`.

### Stage 7.3 — Drilldown polish
**Goal:** every path from Overview to an app's spend works without a console. **Depends on:** 7.2. **Adds:** Overview app row click → account page filtered by app (filter chip with ✕); harness drift chip on account page; `unassigned` sentinel surfaced as `Unassigned` row when any event lacks an app. **Size:** S.

**Inventory** — Files: `Dashboard/{AccountDetailView,ByAppTable}.swift` (filter), `Dashboard/DriftChip.swift`. Events: none new.
**Tests:** `TokenBeUITests/DrilldownUITests`.
**Verify:** UI test.
**Stage DoD:** D1–D12.

---

## 9. Phase 8 — Dashboard completeness

### Stage 8.1 — By-model table & drift
**Goal:** `08 § Account detail 5` and `05 § Drift`. **Depends on:** 7.3. **Adds:** By-model table (`G7-0`) with class columns, est. vs provider cost, drift cell flagged > threshold, unpriced models flagged (A6). **Size:** M.
**Inventory** — Files: `Ledger/Drift.swift`, `Dashboard/ByModelTable.swift`. Settings: `tb.alerts.driftThresholdPct` (consumed). Events: `ledger.drift`.
**Tests:** `DriftTests` (line_item mapping, closed days only, `—` when no cost row), UI test for the unpriced flag (E2E-8).
**Stage DoD:** D1–D12.

### Stage 8.2 — Spend-by-day chart & cache savings
**Goal:** Swift Charts stacked bars; cache tile. **Depends on:** 8.1. **Adds:** Overview chart with tooltip; `Saved $X via cache (net of writes)` tile (`—` for OpenAI with the documented reason). **Size:** M.
**Steps:** `Dashboard/SpendByDayChart.swift` (renders only while visible via `onAppear/onDisappear` flag; palette O-3 by sidebar order), `Ledger/CacheSavings.swift` (05 formula; per-provider computability), `Dashboard/CacheTile.swift`.
**Tests:** `CacheSavingsTests`, `ChartDataTests` (daily stacks sum to totals).
**Stage DoD:** D1–D12.

### Stage 8.3 — CSV export of the current view
**Goal:** toolbar `Export…` (O-4). **Depends on:** 8.2. **Adds:** `NSSavePanel` → RFC 4180 CSV of the visible table/board. **Size:** S.
**Inventory** — Files: `Export/ViewCSVExporter.swift`, toolbar button. Events: `db.export {kind=csv_view}`.
**Tests:** `CSVExporterTests` (quoting, header, UTF-8 no BOM).
**Stage DoD:** D1–D12.

### Stage 8.4 — Accessibility & input
**Goal:** `08 § Accessibility`. **Depends on:** 8.3. **Adds:** VoiceOver labels on every band element and number (`Remaining, approximately 42 dollars, plus or minus 3`), Dynamic Type to `xxLarge` in popover, Reduce Motion (opacity pulse), full keyboard navigation of tables. **Size:** M.
**Tests:** `TokenBeUITests/AccessibilityUITests` (labels present), Accessibility Inspector audit script (`xcrun accessibility-inspector` not scriptable → manual checklist in `docs/QUESTIONS.md` marked done).
**Stage DoD:** D1–D12.

---

## 10. Phase 9 — Data lifecycle & maintenance

### Stage 9.1 — Retention roll-ups
**Goal:** `03 § Retention tiers` in the daily activity. **Depends on:** 8.4. **Adds:** Advanced → retention controls (`Hourly detail kept for N days`, `Raw harness events kept for N days`). **Size:** M.
**Steps:** `Store/Rollup.swift` (hourly→daily with `source='rollup'`; daily→monthly after 400 d; `harness_event` purge after roll-up; `balance_snapshot` thinning; idempotent on PKs; `db.rollup {tier, rows_in, rows_out}`), registered at the `roll-ups` position of the daily order.
**Inventory** — Settings: `tb.retention.hourlyDays`, `tb.retention.rawHarnessDays`. Events: `db.rollup`.
**Tests:** `RetentionTests` (Σ cents and Σ tokens preserved exactly; idempotence; purge after roll-up only).
**Stage DoD:** D1–D12.

### Stage 9.2 — JSON export/import & CSV (all tables)
**Goal:** `03 § Durability` export/import. **Depends on:** 9.1. **Adds:** Advanced → `Export data (JSON)…`, `Import…` (only into an empty DB; otherwise a sheet explains), `Export CSV (all tables)…`. **Size:** M.
**Inventory** — Files: `Export/{JSONExporter,JSONImporter,TablesCSVExporter}.swift`. Events: `db.export`, `db.import`, `db.import_failed`.
**Tests:** `ExportImportTests` (round-trip row counts; no `sk-` in output), E2E-7.
**Stage DoD:** D1–D12.

### Stage 9.3 — Diagnostics bundle
**Goal:** `07 § Diagnostics bundle`. **Depends on:** 9.2. **Adds:** Advanced → `Export diagnostics…` (zip via `/usr/bin/ditto -c -k --sequesterRsrc`, D-ditto-zip). **Size:** S.
**Inventory** — Files: `Export/DiagnosticsBundle.swift`. Events: `app.diagnostics_exported`.
**Tests:** `DiagnosticsBundleTests` (contents list exact; `poll_state.last_raw` redacted; no DB file; SEC-1 grep).
**Stage DoD:** D1–D12.

### Stage 9.4 — Update check
**Goal:** `02 § Update check`. **Depends on:** 9.3. **Adds:** Privacy row `Check for updates daily` + caption; `Update available` badge in Privacy, Overview, popover footer with `html_url` button and `Skip this version`. **Size:** S.
**Inventory** — Files: `Update/UpdateChecker.swift`, daily step at the `update check` position. Settings: `tb.update.checkEnabled`, `tb.update.lastCheckedAt`, `tb.update.latestSeen`, `tb.update.ignoredVersion`. Events: `update.check_ok`, `update.check_failed`.
**Tests:** `UpdateCheckerTests` (semver compare, `v` prefix, ignored version).
**Stage DoD:** D1–D12.

### Stage 9.5 — Reset, cleanups, environment audits
**Goal:** every remaining `09` behavior and `04` startup step verified end-to-end. **Depends on:** 9.4. **Adds:** Advanced → `Reset all settings…`; time-zone change handling (O-14); sleep/wake handling verified. **Size:** S.
**Steps:** `Settings.resetAll` wired to UI; `NSSystemTimeZoneDidChange` → recompute day boundaries + `sched.clock_jump tz=true`; `StartupSequenceTests` asserts all 8 steps in order; `scripts/stages/9.5.sh` launches the app clean and asserts the 8 `startup_step` log lines in order.
**Inventory** — Events: `app.settings_reset`, `sched.clock_jump`.
**Stage DoD:** D1–D12; `04 § Startup sequence` fully audited. **Start H5 (soak) here.**

---

## 11. Phase 10 — Gated adapters (compiled, synthetic-tested, hidden in Release)

### Stage 10.1 — Anthropic adapter
**Depends on:** 9.5. **Steps:** synthetic fixtures per `02 § anthropic` (probe 5 steps incl. `no_org.403`/`401`, usage 1h×48, cost_report with cents-as-string, api_keys, workspaces); `Providers/Anthropic/*.swift`; normalizer rows (05); per-key `≈ $` (D-anthropic-per-key-est); `Priority Tier` note in badges; `credit_low.400` → `poll.provider_rule rule=anthropic_credit_low`. **Tests:** `AdapterTests/AnthropicTests`, `NormalizerTests` rows. **Not** in `Verified`. **Stage DoD:** D1–D3, D5, D9, D11–D12 (no UI change in Release).

### Stage 10.2 — OpenRouter adapter
**Depends on:** 10.1. **Steps:** fixtures `key.ok`, `key.not_management`, `credits.ok`, `keys.ok` (2 pages); `Providers/OpenRouter/*.swift`; `/credits` → `balance_snapshot`; `/keys` → `cost_bucket(group_kind=api_key_id, model='*')` with `usage_daily`; per-key names → `provider_key`. **Tests:** `AdapterTests/OpenRouterTests`. **Not** in `Verified`. **Stage DoD:** as 10.1.

### Stage 10.3 — Contributor verification path
**Depends on:** 10.2. **Steps:** `docs/CONTRIBUTING-fixtures.md` (how to run `record-fixtures.sh <provider>`, redaction check, PR checklist that flips `Verified`); CI job that runs adapter tests for all five providers on whatever fixtures exist. **Stage DoD:** D1–D3, D9, D11–D12.

---

## 12. Phase 11 — Hardening & release

### Stage 11.1 — Performance
**Depends on:** 9.5 (parallel to 10.x). **Steps:** `scripts/perf-idle.sh` (PERF-1/2/3 of `11`), `Tests/Load/LoadGenerator.swift` + `scripts/load-5y.sh` (LOAD-1), fixes until targets of `04` hold; windows release on close verified with `leaks`/`footprint`. **Stage DoD:** PERF-1..3 and LOAD-1 outputs committed to `docs/perf/<date>.md`.

### Stage 11.2 — Security
**Steps:** SEC-1 harness (`scripts/check-no-secrets.sh --runtime` runs E2E-2 and E2E-7 with `sk-FIXTURE-…` keys, then greps DB, logs, diagnostics zip, export, bundle), SEC-2 attribute test, redaction review of every `ctx` site (script lists all `Log.` calls with string interpolation for manual review; findings fixed). **Stage DoD:** SEC-1, SEC-2 green in CI.

### Stage 11.3 — Paper, strings, accessibility reconciliation
**Steps:** walk every node id in `08` against the running app (checklist file `docs/reconciliation.md`, one row per node id: `matches | docs updated | Paper updated`); `StringsAuditTests` (every quoted copy string in `08` exists in `Strings.swift`); Dynamic Type/VoiceOver pass. **Stage DoD:** checklist has no open row.

### Stage 11.4 — Docs & README
**Steps:** README (install via Homebrew/dmg; provider key how-to per provider from `02`; harness reporter snippets; FAQ on `≈`/`±`; privacy statement); `CHANGELOG.md § 1.0.0`; `13` has no `OPEN` row (every `O-n` either applied-as-default and marked, or converted to a `D-`); `QUESTIONS.md` entries all `Resolved`; every `PM-*` carry-forward action in `docs/postmortems/` closed, or re-targeted to `post-1.0` with a one-line reason in its postmortem. **Stage DoD:** `01 § Definition of done for V1` non-build items satisfied.

### Stage 11.5 — Release 1.0.0 (H4, H5)
**Steps:** H5 soak report (zero `fault`; every `error` explained); `scripts/release.sh` per `10` (archive → export → dmg via `hdiutil` → codesign → notarytool → stapler → sha256 → `gh release create` → cask bump in `nbencic/homebrew-tap`); `scripts/stages/11.5.sh` verifies `spctl --assess --type open --context context:primary-signature` passes on the dmg and the cask installs on a clean user account. **Stage DoD:** A1–A10 of `01` all pass on a clean macOS 15 machine; tag `v1.0.0`.

---

## 13. Coverage matrices (produced by the review passes; see § 14)

### 13.1 `03` tables → stage that creates / first writes / reads
| Table | Created | First written | Read by |
|---|---|---|---|
| schema_version | 2.1 (seed) | 2.1 | 2.1 |
| account | 2.1 | 3.5 | 3.5+ |
| provider_key | 2.1 | 3.4 (tests), 3.5 (app) | 3.5, 7.1 |
| app | 2.1 (seed `unassigned`) | 7.1 / 7.2 | 7.1+ |
| app_binding | 2.1 | 7.1 | 7.1, 7.2 |
| usage_bucket | 2.1 | 3.4 | 5.2+ |
| cost_bucket | 2.1 | 3.4 | 5.3, 7.1, 8.1 |
| balance_snapshot | 2.1 | 6.1 | 5.3 (direct), 9.1 |
| harness_event | 2.1 | 7.2 | 7.2, 9.1 |
| ingest_file | 2.1 | 7.2 | 7.2 |
| ledger_event | 2.1 | 3.5 (anchor) | 5.3 |
| price_snapshot | 2.1 | 5.1 (bundled seed) | 5.1, 5.2 |
| price_override | 2.1 | 5.1 | 5.1 |
| poll_state | 2.1 | 3.5 (seed ×4), 3.4 (updates) | 4.1, 4.2 |
| band_state | 2.1 | 5.3 | 5.3, 5.5 (startup step 8) |

### 13.2 `09` settings keys → stage (registered in 0.3; UI/consumer stage shown)
General: `launchAtLogin` 1.3 · `menubar.glyphStyle` 1.3 · `menubar.metric` 1.3/5.5 · `popover.pinnedMetric` 1.3/5.3 · `popover.sort` 1.3/5.3 · `popover.manualOrder` 5.3 · `popover.expanded.<p>` 7.1 · `ui.currencyDisplay` 1.3 · `ui.hideCents` 1.1/1.3 · `ui.appearance` 1.3 · `ui.useSystemAccent` 1.3 · `ui.shortcut` 1.3 · `ui.dashboardFrame` 1.2 · `ui.dashboardRange` 1.2 · `ui.onboardingDone` 3.5.
Accounts (DB columns): `label` 3.5 · `paused` 3.5/4.1 · `auto_reload_*` 5.3 · `interval_override_json` 4.1.
Sources: `poll.balanceIntervalS` 4.1/6.1 · `poll.usageIntervalAnthropicS` 4.1 · `poll.usageIntervalOpenAIS` 4.1 · `poll.keysIntervalS` 4.1 · `poll.lowPowerMultiplier` 4.1 · `poll.pausedUntil` 4.1 · `daily.lastRunAt` 4.3 · `daily.runCount` 4.3 · `ingest.enabled` 7.2 · `ingest.moveWhenDone` 7.2 · `ingest.folderPath` 7.2 · `price.feedEnabled` 5.1 · `price.feedURL` 5.1 · `price.staleAfterDays` 5.1.
Alerts: `watchDays/lowDays/criticalDays/dollarFloorCents/anchorAgeDays` 5.3 · `staleMultiplier` 4.2/5.3 · `driftThresholdPct` 5.3/8.1 · `notify.*`, `quiet*`, `snoozedUntil.<p>` 5.4.
Privacy: `update.*` 9.4.
Advanced: `log.level` 1.3 · `log.retentionDays` 1.3 · `retention.hourlyDays` 9.1 · `retention.rawHarnessDays` 9.1 · `db.lastBackupAt` 2.2 · `db.lastIntegrityCheckAt` 2.2 · `debug.fixtureMode` 3.1.

### 13.3 `07` events → first emitting stage
`app.launch/terminate/log_dropped` 0.2–0.4 · `app.settings_changed/settings_reset` 0.3 (UI 1.3/9.5) · `app.login_item_failed` 1.3 · `app.network_changed` 3.1/4.1 · `app.diagnostics_exported` 9.3 · `sched.*` 4.1 (`daily_*` 4.3) · `poll.*` 3.4 · `normalize.*` 3.4 (`failed` 7.2) · `price.feed_ok/feed_failed/parse_failed/stale/override_set` 5.1 · `price.fallback_multiplier/unpriced/repriced` 5.2 · `ledger.anchor_set` 3.5 · `ledger.topup/reconcile` 5.3 · `ledger.drift` 8.1 · `ledger.harness_drift` 7.2 · `ledger.auto_zero` — no producer in V1 (O-18) · `ingest.*` 7.2 · `keychain.*` 3.2 (`missing` 3.5) · `db.open/migrate/migrate_failed/quick_check/integrity_check/integrity_failed/corrupt/restore/backup/backup_failed/vacuum/busy` 2.1 · `db.rollup` 9.1 · `db.export/import/import_failed` 8.3/9.2 · `ui.popover_open/close` 1.1 · `ui.hotkey_failed` 1.3 · `ui.band_change` 5.3 · `ui.notification_sent/denied` 5.4 · `ui.error` 3.5 · `update.*` 9.4 · `crash.*` 0.2/0.4.

### 13.4 `08` screens/elements → stage
Menu bar glyph shapes 1.1, state wiring 4.2 (dashed) / 5.5 (notch, metric) · Popover header 1.1 (+ refresh 4.1) · Alert banner 5.3 · Account cards: row 1 + "No data yet" 3.5, rows 2–3 5.3, row 4 7.1, stale overlay 4.2 · Empty state 1.1 (+ button 3.5) · Day-1 5.3 · Offline/Paused 4.2/4.1 · Footer: Quit 1.1, Open dashboard 1.2, Settings 1.3, Pause 4.1 · Dashboard window/sidebar/range 1.2, account rows 3.5, Apps section 7.1 · Overview headline/runway board 5.3, chart 8.2, Apps this period 7.1, cache tile 8.2, Export 8.3 · Account detail header/badges/sources strip 4.2, numbers strip 5.2/5.3, By app 7.1/7.2, By model 8.1, Ledger 5.3, sheets 5.3 · Onboarding 3.5 · Settings: General 1.3, Accounts 3.5 (+ auto-reload 5.3, binding 7.1, overrides 4.1), Sources 4.1 (+ daily 4.3, price book 5.1, harness 7.2), Alerts 5.3/5.4, Privacy 1.3 (+ update 9.4), Advanced 1.3 (+ 2.2, 9.1, 9.2, 9.3, 9.5) · Notifications 5.4 · Accessibility 8.4.

### 13.5 `01` scope and acceptance → stage
S1 3.5/3.6/6.x (gated: 10.x) · S2 5.3/6.1 · S3 5.3 · S4 7.1/7.2 · S5 5.3 · S6 1.1/3.5/5.3 · S7 1.2/4.2/5.3/7.1/8.x · S8 1.3/3.5/4.1/5.3/5.4/9.x · S9 3.5 · S10 5.1/5.2 · S11 5.4 · S12 0.2/9.3 · S13 2.1/9.1/9.2.
A1 3.5+4.1+5.3 (verified 11.5) · A2 7.1 · A3 7.2 · A4 4.2+11.2 · A5 5.3 (traceability script) · A6 5.2/8.1 · A7 11.1 · A8 11.1 · A9 11.2 · A10 0.5.

### 13.6 `11` tests → stage
Smoke 0.1 · Redactor/LogSink/CrashHandler/LogRecord 0.2 · Settings 0.3 · StartupSequence 0.4 (grows) · Formatters 1.1 · Migration/RepositoryAccount 2.1 · Observation 2.2 · PollErrorMapping/RetryPolicy/URLSessionTransport 3.1 · KeyStore(+Integration) 3.2 · VerifiedProviders/ProviderID 3.3 · OpenAI/Normalizer/PollState/Poller 3.4 · AccountLifecycle 3.5 · Scheduler/Coordinator 4.1 · Freshness 4.2 · DailyActivity 4.3 · PriceLookup/PriceFeed 5.1 · CostFormula/Reprice 5.2 · Ledger/BandTransition/Burn 5.3 · AlertPolicy 5.4 · GlyphState 5.5 · DeepSeek/OverviewTotals 6.1 · XAI 6.2 · Attribution 7.1/7.2 · LineParser/IngestTailer 7.2 · Drift 8.1 · CacheSavings/ChartData 8.2 · CSVExporter 8.3 · Retention 9.1 · ExportImport 9.2 · DiagnosticsBundle 9.3 · UpdateChecker 9.4 · Anthropic 10.1 · OpenRouter 10.2 · UI tests: LaunchSmoke 0.4, PopoverEmptyState 1.1, DashboardShell 1.2, SettingsGeneral 1.3, AdvancedMaintenance 2.2, Onboarding 3.5, RefreshPause 4.1, StaleOffline 4.2, DailyRunNow 4.3, PriceBook 5.1, AnchorRunway 5.3, NotificationsSettings 5.4, GlyphMetric 5.5, AppsBinding 7.1, HarnessIngest/HarnessRejected 7.2, Drilldown 7.3, Accessibility 8.4 · E2E-1 1.1/3.5, E2E-2 5.3, E2E-3 7.2, E2E-4 5.4, E2E-5 4.2, E2E-6 9.5, E2E-7 9.2, E2E-8 8.1, E2E-9 5.3 · LOAD/PERF 11.1 · SEC 11.2 · SOAK 9.5→11.5.

---

## 14. Review log

### Pass 1 — gaps found and fixed in this plan and the docs
1. **Right-click context menu** on `MenuBarExtra` is not implementable within `04`'s AppKit restriction → removed from `08`; footer carries the actions (D-context-menu).
2. **`tb.poll.costDailyLocalTime`** cannot be honored by `NSBackgroundActivityScheduler` → removed from `09`; `tb.daily.lastRunAt`/`runCount` added (D-daily-no-fixed-time).
3. **Seed rows** were unspecified: `schema_version(1)`, `app('app_unassigned')` (V4 sentinel), `price_snapshot(bundled-<v>)`, `poll_state ×4` per account → added to 2.1/3.5/5.1 and `03`.
4. **Bundled price snapshot** (`01 § S10`, `04` startup step 4) had no artifact → `Resources/prices.bundled.json` + `scripts/update-bundled-prices.sh` (5.1, 10).
5. **App icon** missing from every doc → `scripts/make-icon.swift` + `AppIcon` set (0.4, O-15/D-icon-script).
6. **Pixel snapshot tests** need a dependency → replaced by XCUITest state tests on accessibility identifiers (D-no-pixel-snapshots; `11` updated).
7. **Keychain unit testing** via temp keychain is not possible on modern macOS → `InMemoryKeyStore` + one tagged integration test (3.2; `11` updated).
8. **Events referenced but absent from `07`:** `keychain.missing` (04), `price.repriced`, `app.network_changed`, `app.login_item_failed`, `ui.hotkey_failed`, `ui.notification_denied`, `db.export`, `db.import`, `db.import_failed`, `app.diagnostics_exported`, `ingest.start`, `ingest.stop`, `ingest.moved`, `ingest.key_hint_ambiguous`, `app.settings_reset`, `sched.overlap_skipped`, `sched.overrun` → added to `07`.
9. **`01 § S7`** listed dashboard pages (Models, Cache, Pricing) that `08` folds into the account page / Settings → `01` aligned to `08`; `01` A-row verification ids aligned to `11` (E2E-8/9 added).
10. **Export schema** differed between `03` and `13 § O-5` → O-5 now points to `03`; CSV of all tables added to Advanced in `08`.
11. **Verified-provider gating** (Nikola has OpenAI + DeepSeek/xAI keys; no Anthropic org, no OpenRouter management key) → `Verified.swift`, `RECORDED` markers, Release-only hiding, Phase 10 (D-verified-providers, D-synthetic-fixtures; `12 § R2/R13` adjusted).
12. **Xcode project creation** → human GUI step H1 + xcconfig; agent never edits pbxproj (D-xcodeproj, D-xcconfig; `10` updated).
13. **DeepSeek `is_available=false`** had no defined behavior → band `critical` + chip (D-deepseek-unavailable).
14. **Repository protocol** would otherwise be redesigned per stage → full method list fixed in 2.1, implemented by extension per stage (no stubs).
15. **Controls whose consumer lands later** (`tb.menubar.metric` 1.3→5.5, `account.paused` 3.5→4.1, `driftThresholdPct` 5.3→8.1, `popover.expanded` chevron) → each explicitly allowed and listed; everything else follows "control appears with its action".

### Pass 2 — consistency check after pass 1 (no further changes needed except as noted)
- Every table in `03` appears in § 13.1 with a creating and a first-writing stage. ✔
- Every key in `09` (after the pass-1 edits) appears in § 13.2. ✔
- Every event in `07` (after the pass-1 edits) appears in § 13.3; `ledger.auto_zero` is the only one without a producer and is recorded as O-18 (schema value kept, no code path). ✔
- Every `08` screen/element and every `01` S/A row maps to a stage (§ 13.4, § 13.5). ✔
- Every test file in `11` maps to a stage (§ 13.6). ✔
- Startup steps 1–8 of `04`: 1 → 0.4, 2 → 2.1, 3 → 3.5, 4 → 5.1, 5 → 7.2, 6 → 4.1, 7 → 4.3, 8 → 5.5; final order audit 9.5. ✔
- Human gates are all non-blocking: H1 blocks only 0.4 (0.1–0.3 proceed); H2/H3 block only the `Verified` flip; H4/H5 block only 11.5. ✔
- One residual risk, not a plan gap: `MenuBarExtra(.window)` ⌥-click detection (1.2) depends on `NSEvent.modifierFlags` at click time; if it proves unreliable, the fallback is to drop ⌥-click and keep `Open dashboard` in the footer — pre-authorized here, to be logged in `QUESTIONS.md` if taken.

### Pass 3 — owner instructions, 2026-11-09
- **Postmortems** after every stage and phase → § 0.6, D13, `12 § R11/R12`, `00` map, `CLAUDE.md` (D-postmortems).
- **Branching conflict:** `12 § R11` said one branch per milestone; § 0 says one branch per stage → `12` aligned to § 0 (D-stage-branches).
- Stale references "§ 6" for the review log → "§ 14".
- **H1 retired** (owner request): the agent writes the Xcode project (D-xcodeproj-agent).
- **D10 no longer deletes the owner's data:** clean-launch checks run under `TOKENBE_TEST_ROOT` (Q-014).
