# QUESTIONS — judgment calls made during implementation

Append-only. Format is fixed by `12-agent-rules.md § R3`. Do not delete entries; mark them `Resolved: <decision id or commit>` when closed.

## Q-001 Local toolchain newer than the documented one            (2026-11-09)
Context: `14 § 0` executor line and `10 § CI` (macOS 15, Xcode 16.x, `macos-15` runner); the owner's Mac runs macOS 27.0.1 and Xcode 26.3 (Swift 6.2.4).
Options: A) keep the documented targets (deployment target 15.0, `SWIFT_VERSION = 6.0`, CI on `macos-15` with Xcode 16.x) and treat CI as the compatibility gate, so local-only Swift 6.2 features fail in CI rather than shipping B) move CI and the docs to Xcode 26.
Chosen for now: A — no doc change, and CI already blocks code that only compiles on the newer toolchain; revisit if the `macos-15` runner image or Xcode 16.x is unavailable when 0.5 runs.
Blocking: no

## Q-002 Environment variable names for H3 fixture recording            (2026-11-09)
Context: `14 § 0.4` H3 and `scripts/record-fixtures.sh`; only `OPENAI_ADMIN_KEY` is named in the docs.
Options: A) `DEEPSEEK_API_KEY` and `XAI_API_KEY` B) other names.
Chosen for now: A — follows the provider's own key type and the `OPENAI_ADMIN_KEY` pattern; `record-fixtures.sh --help` prints the names.
Blocking: no

## Q-003 Repo root is `~/tokenbe-app` and the docs sit at its top level            (2026-11-09)
Context: `CLAUDE.md` and `12`/`14` refer to `docs/…`; H1 step 1 says "repo root (`tokenbe/`)". Before 0.1 the doc set sits at the top level of `~/tokenbe-app` and there is no git repo yet.
Options: A) the repo root is `~/tokenbe-app`; Stage 0.1 step 2 moves the doc set (incl. `reporters/`) into `docs/` with `git mv` after `git init`; `CLAUDE.md` stays at the root B) a new `~/tokenbe` directory.
Chosen for now: A — no copy and no second tree; in H1, read `tokenbe/` as `tokenbe-app/`.
Blocking: no

## Q-004 Package.swift resource folders must exist before their content does            (2026-11-09)
Context: `Package.swift` (exact, `10`) declares `.copy("Store/Migrations")` and `.copy("../Fixtures")`; their content arrives in 2.1 and 3.4, and SwiftPM fails the build when a resource path is missing ("missing inputs"). Git does not track empty folders.
Options: A) a one-paragraph `README.md` in each folder pointing to `03`/`11` B) a `.gitkeep` C) drop the resource lines until the content exists.
Chosen for now: A — keeps `Package.swift` exactly as `10`, survives a fresh clone, and documents the folder; B may be skipped as a hidden file, C changes an "exact" file.
Blocking: no

## Q-005 Base commit and merging before CI exists (Stages 0.1–0.4)            (2026-11-09)
Context: `14 § 0` requires a stage branch, a PR and green CI (D12); the repo was empty and CI only lands in 0.5.
Options: A) an empty root commit on `main` as the PR base; merge 0.1–0.4 once `scripts/verify-stage.sh` prints `STAGE <id> OK`, with D12 read as "merged; no CI configured yet" B) skip PRs until 0.5.
Chosen for now: A — keeps the one-PR-per-stage history from the first stage; `verify-stage.sh` runs the same build/test/lint steps that CI will.
Blocking: no

## Q-006 Redaction patterns 3 and 4 leak the token after a scheme word            (2026-11-09)
Context: `07 § Redaction`, `Logging/Redactor.swift`. Pattern 3 (`…\s*[:=]\s*\S+`) consumes only `Bearer` in `Authorization: Bearer <token>`, so pattern 4 can no longer match and the token stays visible (reproduced: a JWT survives in full). Pattern 3 also misses JSON-quoted names (`"x-api-key": "…"`), and pattern 4 stops at `+ / =`. This contradicts 07's own test ("never more than the last 4 chars").
Options: A) widen 3 to consume an optional scheme word and JSON quotes, widen 4's token class, make pass 7 a substring match, redact before truncating; update 07 B) keep the patterns verbatim.
Chosen for now: A — strictly more redaction; every vector is pinned in `RedactorTests`. B would ship a known secret leak. Not blocking because the safe option is unambiguous.
Blocking: no

## Q-007 NDJSON serialization details 07 leaves open            (2026-11-09)
Context: `Logging/LogRecord.swift`, `Logging/Log.swift`.
Options: A) hand-written JSON writer; `acct/job/attempt/err/dur_ms` omitted when they do not apply; `ctx` always present with keys sorted; over the 2 KiB cap, the remaining keys are dropped and `ctx_truncated: true` is added; `thr` is `main` or `thread:<id>`, because the `Log` API in 14 has no thread/actor parameter B) `JSONEncoder` with `null` for absent fields.
Chosen for now: A — fixed key order on every toolchain (`JSONEncoder` does not guarantee order) and smaller lines; 07 updated.
Blocking: no

## Q-008 crash.signal breadcrumbs in a flat ctx            (2026-11-09)
Context: `07 § Crash handling` wants the last 50 breadcrumbs in `crash.signal`; `07 § Record shape` allows only flat primitives in a 2 KiB `ctx`.
Options: A) breadcrumbs as ONE string (the 50 NDJSON lines joined by `\n`), each cut to 1 200 bytes; `crash.signal` exempt from the 2 KiB cap B) a nested array.
Chosen for now: A — keeps ctx flat and the crash path allocation-free (64 KiB pre-allocated buffer); 07 updated. Consequence: records still in the NDJSON sink's buffer at crash time survive only as breadcrumbs.
Blocking: no

## Q-009 Where the bounded stream lives, and what "synchronous flush" means            (2026-11-09)
Context: 07 places the bounded `AsyncStream` in the NDJSON sink, but the `LogSink` seam (`14 § 0.3`) is async while `Log.*` must be synchronous (it is called from every `catch`).
Options: A) one bounded stream (4 096) in `LogPipeline` feeding all sinks in order from a single consumer; the consumer reports `app.log_dropped`; "synchronous flush after error/fault" = the NDJSON sink writes to disk as soon as it processes such a record B) a stream per sink.
Chosen for now: A — one ordering for all sinks, one drop counter, and the seam stays exactly as specified. Logging's own I/O failures get a new event, `app.log_sink_failed` (added to 07), routed to os.Logger and breadcrumbs only.
Blocking: no

## Q-010 Shape of the settings code generated from 09            (2026-11-09)
Context: `Settings/SettingsKey.swift`, `Settings/Settings+Accessors.swift`, `Settings/SettingSpec.swift`. 09 says the table is the registration list ("generate it"). 09 also asks for a `Settings.didChange` notification, while 14 asks for `changes: AsyncStream<SettingsKey>`.
Options: A) generate `SettingsKey` (53 keys with spec) and one typed property per key from 09; per-provider keys as a separate `TemplatedSettingsKey` (an enum case cannot carry a dynamic name); post `Settings.didChange` AND yield to `changes`, which returns a fresh stream per access so several subscribers work; `Settings(store:logPipeline:)` takes an optional pipeline for tests B) hand-written accessors and one shared stream.
Chosen for now: A — one source of truth (`0.3.sh` diffs 09 against the enum), both announcement paths as both docs say, and tests that never touch the global logger.
Blocking: no

## Q-011 What "clamp" means for settings without a numeric range            (2026-11-09)
Context: `SettingSpec.validate`; 09 gives ranges for numbers only.
Options: A) a value of the wrong type, a string outside its allowed list, or a malformed pattern → the default, logged `clamped=true`; `manualOrder` drops unknown and duplicate provider ids; `ingest.folderPath` always holds its fixed value. Patterns: shortcut = `ctrl alt shift cmd` modifiers, each at most once, plus key `a–z 0–9 f1–f12 space` (empty = none); `NSStringFromRect` text or empty; `HH:mm`; absolute `https` URL; semver or empty. Threshold bounds implied by `critical < low < watch ≤ 365`: critical 0–363, low 1–364, watch 2–365. A writer clamps only the key it writes; at launch, an order broken in storage resets all three to their defaults B) reject invalid writes without storing.
Chosen for now: A — 09 says "clamp + log" and never "reject"; resetting the three thresholds at launch is the least code.
Blocking: no

## Q-012 Settings suite equal to the app's bundle id            (2026-11-09)
Context: `Settings/UserDefaultsStore.swift`. The suite `dev.bathyon.tokenbe` (09) is also the bundle id (10), and Foundation does not accept the main bundle id as a suite name.
Options: A) when they are equal, use the app's standard domain, which is the same `dev.bathyon.tokenbe` domain (so `defaults delete dev.bathyon.tokenbe` in D10 still clears it) B) rename the suite.
Chosen for now: A — no behavior or name changes; tests use a throwaway suite.
Blocking: no

## Q-013 Build settings beyond the Stage 0.4 list            (2026-11-09)
Context: `Config/*.xcconfig`, `TokenBe.xcodeproj` (D-xcodeproj-agent). With no settings in the project file, a few Xcode defaults have to live somewhere, and the UI-test target needs its own identity.
Options: A) `Config/Project.xcconfig` (SDK, deployment target, Swift 6, Debug-only arch/testability/debug-info settings) for the project level; `Config/UITests.xcconfig` for the UI-test bundle (`dev.bathyon.tokenbe.uitests`); `Base.xcconfig` adds `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = -` (sign to run locally until H4), `COMBINE_HIDPI_IMAGES`, `LD_RUNPATH_SEARCH_PATHS`, `SWIFT_EMIT_LOC_STRINGS`; `ENABLE_PREVIEWS` is NOT set B) settings in the project file.
Chosen for now: A — D-xcconfig stays literally true. `ENABLE_PREVIEWS = YES` silently turns hardened runtime off for Debug, so it is left out (the app has no previews). Xcode still signs Debug builds without the runtime flag when signing to run locally; Release builds carry `flags=0x10002(adhoc,runtime)`.
Blocking: no

## Q-014 Keeping UI tests and verification away from the owner's data            (2026-11-09)
Context: `Sources/TokenBeApp/Startup.swift`, `Tests/TokenBeUITests`, `scripts/stages/0.4.sh`, 14 D10. `XCUIApplication.terminate()` kills the app (leaving `.running`, so the next real launch would log a false `crash.previous_launch`), and D10 told the agent to `rm -rf` the owner's real data folders.
Options: A) Debug builds only: the environment variable `TOKENBE_TEST_ROOT` moves logs, support folder and sentinel under that root and settings to the suite `dev.bathyon.tokenbe.uitests`; UI tests and `0.4.sh` (`open --env`) always set it; Release ignores it B) wipe the real folders before each check.
Chosen for now: A — no data loss, no hidden setting (it is not a `tb.*` key and does not exist in Release), and D10 is rewritten to use it.
Blocking: no

## Q-015 Startup and asset details 14/07/08 leave open            (2026-11-09)
Context: Stage 0.4.
Options: A) `app.launch` is logged once with the 07 context and once per startup step (`startup_step`, 14 step 6); a failing step logs `app.launch` at `error` with `err` and stops; a sentinel that cannot be removed logs `app.terminate` at `error`; `crash.previous_launch` reports `signal_or_exception: "unknown"` and `breadcrumbs_attached: false` (the crash line itself, with signal and breadcrumbs, is already in the previous log file); colour sets for every 08 token with an asset name (`secondary`/`tertiary` use the system styles, as 08 says); the menu-bar ring is a template `NSImage`, because menu-bar labels render images, not SwiftUI shapes B) new events for each case.
Chosen for now: A — no new events, every failure still logged.
Blocking: no
