# QUESTIONS — judgment calls made during implementation

Append-only. Format is fixed by `12-agent-rules.md § R3`. Do not delete entries; mark them `Resolved: <decision id or commit>` when closed.

## Q-001 Local toolchain newer than the documented one            (2026-11-09)
Context: `14 § 0` executor line and `10 § CI` (macOS 15, Xcode 16.x, `macos-15` runner); the owner's Mac runs macOS 27.0.1 and Xcode 26.3 (Swift 6.2.4).
Options: A) keep the documented targets (deployment target 15.0, `SWIFT_VERSION = 6.0`, CI on `macos-15` with Xcode 16.x) and treat CI as the compatibility gate, so local-only Swift 6.2 features fail in CI rather than shipping B) move CI and the docs to Xcode 26.
Chosen for now: A — no doc change, and CI already blocks code that only compiles on the newer toolchain; revisit if the `macos-15` runner image or Xcode 16.x is unavailable when 0.5 runs.
Blocking: no
Resolved: Stage 0.5 — CI runs Xcode 16.4 / Swift 6.1.2 on `macos-15` and caught one Swift 6.2-only construct on its first run.

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
Resolved: Stage 0.5 — CI exists; from Stage 0.5 on, every PR merges only with CI green (D12).

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

## Q-016 What the secret guard tolerates, and where URLs are checked            (2026-11-09)
Context: `scripts/check-no-secrets.sh`. 11 prescribes the fixture placeholder `sk-FIXTURE-<provider>-<last4>`, which matches 07 pattern 1; 02 documents key formats as prefixes (`sk-ant-admin01-…`); docs, license and `Package.swift` contain URLs that are not app traffic.
Options: A) match strings one by one and exempt exactly the placeholder and bare prefixes ending in `-`/`_`; apply the URL allowlist to Swift sources only, where outbound requests are written (R4); also fail on a tracked `.env`; prove the guard with a planted-secret self-test B) exclude whole directories (docs, tests, fixtures).
Chosen for now: A — fixtures and tests stay scanned, as 14 asks, and nothing broader than two literal forms is exempt.
Blocking: no

## Q-017 Formatting details 08 and 05 leave open            (2026-11-09)
Context: `Model/Formatters.swift`.
Options: A)
- **Money:** whole units rounded half up when cents are hidden; the locale's grouping and decimal separators apply to money too (`$1.234,56` in `de_DE`); negative amounts `-$5`, except remaining, which clamps to `$0`.
- **Estimate band:** the same rounding, with no currency symbol (`≈ $42 ± 3`).
- **Runway:** hours and days floored; when only the today pace exists, `5 h today`.
- **Tokens:** three significant digits, rounded half up, `k/M/B/T` (`999 500` → `1.00M`, never `1000k`).
- **Freshness:** older than yesterday shows `MMM d`.
- **Dates:** English month abbreviations (O-9), computed in the calendar's time zone, without Foundation date styles (their output differs between macOS versions).
- **Arithmetic:** integer only, overflow-safe.

B) Foundation currency, number and date styles.
Chosen for now: A — exact 08 strings on every macOS version (CI runs macOS 15, the owner's Mac macOS 27), and no `Double` for money or tokens (R7).
Blocking: no

## Q-018 Popover shell details            (2026-11-09)
Context: Stage 1.1 app code.
Options: A)
- `ui.popover_open/close` come from the popover view's appear/disappear, through a Core `PopoverTracker` (unit-tested; repeat calls ignored; `dur_ms` from `ContinuousClock`). The UI test proves two opens and a close.
- The `Formatters` texts (`just now`, `never`, …) live in Core next to the rules; view copy lives in `Strings.swift`.
- `AppModel` lives in the app delegate and receives the environment after startup step 1, so `Settings` is never created before logging (04).
- The provider glyph on cards is left out until artwork exists: cards are not rendered before Phase 3, and 08 names no asset for it.
- `AppEnvironment.settings` is spelled `TokenBeCore.Settings`, because SwiftUI has its own `Settings` scene type.

B) Open/close from window notifications (AppKit).
Chosen for now: A — no AppKit window hooks (04), testable in Core.
Blocking: no

## Q-019 UI tests on a crowded menu bar            (2026-11-09)
Context: `PopoverEmptyStateUITests` on the owner's Mac. With about 20 status items and the notch, macOS keeps TokenBe's item behind the menu-bar overflow chevron (`«`). The item's accessibility frame is the chevron's, so the first click only reveals the item.
Options: A) The test clicks the status item up to twice until the popover's element appears, and reads static-text strings from the accessibility value (macOS leaves the label empty). Settings reach the app as launch arguments (`-tb.log.level debug`, the arguments domain): the UI-test runner is sandboxed, so its own `UserDefaults` writes land in its container, never in the app's suite. B) Ask the owner to move TokenBe's item (⌘-drag) or edit the system's menu-bar layout (`com.apple.MenuBar`). C) A Debug-only hook that opens the popover without a click.
Chosen for now: A. The test still proves that a click on the glyph opens the popover, works on any menu bar, and doesn't touch the owner's system settings. C would skip the click the test exists to check.
Blocking: no

## Q-020 Dashboard window details 14/08 leave open            (2026-11-09)
Context: Stage 1.2 app code and `DashboardShellUITests`.
Options: A)
- **Frame:** `tb.ui.dashboardFrame` is the only frame memory. The `Window` scene uses `.restorationBehavior(.disabled)` and `.defaultLaunchBehavior(.suppressed)`, so SwiftUI neither restores the frame nor reopens the window at launch. A small `NSViewRepresentable` (`WindowFrameKeeper`) reads and sets the frame of the window SwiftUI created. 04 forbids AppKit *windows*; none is created.
- **Frame rules** (Core `WindowFrame`, unit-tested): `NSStringFromRect`'s format with integral points; the saved frame is grown to 920×600 and restored only if at least 40 pt of it each way lies on a connected screen. Otherwise the system places the window.
- **Saving:** on move or resize, debounced 500 ms (Core `Debouncer`, clock injected); also on close, so a quick move-then-close isn't lost.
- **Window title:** the scene is named `Dashboard`; the title bar shows the sidebar selection (`Overview`), as `NavigationSplitView` does. Tests find the window by its scene id `dashboard`.
- **Opening:** the popover's `Open dashboard` button (⌘D) and ⌥-click both call `openWindow(id: "dashboard")`, activate the app and dismiss the popover. ⌥-click reads `NSEvent.modifierFlags` as the popover appears (O-15). It works on macOS 27, so the O-15 fallback isn't needed.
- **UI-test settings reset:** Debug-only `TOKENBE_TEST_RESET_SETTINGS=1`, honoured only with `TOKENBE_TEST_ROOT`, clears the UI-test suite before `Settings` loads. `SettingsSuite.resetUITests` refuses every suite except `dev.bathyon.tokenbe.uitests`, so the owner's settings can never be cleared this way.
- **AppKit's own window state:** `NavigationSplitView` autosaves its split widths (`NSSplitView Subview Frames dashboard, …`) into the app's standard defaults domain, which is the owner's real `dev.bathyon.tokenbe`, even under `TOKENBE_TEST_ROOT`. It is AppKit UI state, not a TokenBe setting. Verification therefore guards the real domain's `tb.*` keys (unchanged from start to end) rather than the file. The one key written on 2026-11-09 was left in place (the real domain is never modified by the agent).
- **14's Verify** reads `dev.bathyon.tokenbe tb.ui.dashboardRange`. Under Q-014 the test writes the UI-test suite, so the check reads `dev.bathyon.tokenbe.uitests`, and also checks that the real settings plist wasn't modified during verification.

B) Let SwiftUI's own window restoration keep the frame (no `tb.ui.dashboardFrame`).
Chosen for now: A. 09 defines the setting and 14 asks for it, and a single source of truth keeps `Reset all settings…` (9.5) meaningful for the window too.
Blocking: no

## Q-021 Stage 1.2 "Adds" lists a right-click context menu            (2026-11-09)
Context: `14 § Stage 1.2` "Adds" says "right-click context menu with `Open dashboard` and `Quit TokenBe`"; step 4 of the same stage, `08` and D-context-menu say there is none.
Options: A) No context menu (13 overrides everything, 12 R1). B) Build it.
Chosen for now: A. The "Adds" line is a leftover from before D-context-menu. It is corrected in 14 so the next reader doesn't trip on it.
Blocking: no

## Q-022 Stage checks read the test result file, not console text            (2026-11-09)
Context: about once in 100–150 full `swift test` runs, SwiftPM's console relay loses the tail of Swift Testing's output while the run exits 0. On such a run the xunit result (`--xunit-output`) still lists all tests passed. The stage checks grepped the console text for `Suite X passed`, so they could fail spuriously.
Options:
- A) `run.sh test` writes `build/results/test-swift-testing.xml`. A `suite_passed` helper in `verify-stage.sh` requires that file to be newer than the run's start, to contain the suite, and to report `failures="0"`.
- B) Retry verify on a missing summary.
Chosen for now: A. The structured result is authoritative, and a retry would hide real problems. The `swift test` exit code still gates as before; CI is unaffected, because it relies on the exit code only.
Blocking: no

## Q-023 Settings window: what the global shortcut can open, login item and appearance            (2026-11-10)
Context: Stage 1.3. `09 tb.ui.shortcut` says the global hotkey "toggles the popover". `04` and `08` require `MenuBarExtra(.window)`, and `08` says "`NSStatusItem` fallback is NOT allowed". 13 D-hotkey-carbon fixes the shortcut itself.
Evidence (macOS 27.0.1, Xcode 26.3; the hotkey fired every time, logged in-process):
- `NSStatusBarButton.performClick` does nothing: SwiftUI's status button has no action and no target.
- A synthetic mouse-down/up pair sent to the status window (`sendEvent` + `postEvent`) is ignored.
- The button has no gesture recognizers, and `accessibilityPerformPress()` returns false.
- Ordering SwiftUI's own popover window (`MenuBarExtraWindow`) to the front shows it, but SwiftUI still treats the popover as closed: `onAppear` doesn't fire (no `ui.popover_open`), Escape doesn't close it, and `dismiss()` does nothing.
- Only a real click, routed by the system, opens a `MenuBarExtra` on macOS 26+.

Options:
- A) The shortcut toggles the Dashboard. It opens and activates the Dashboard; pressed again while the Dashboard is the front window, it closes it. `openWindow` is captured from the menu-bar label, the only SwiftUI view alive from launch.
- B) Drive SwiftUI's private popover window and patch the open/close events, Escape and dismissal by hand.
- C) Replace `MenuBarExtra` with `NSStatusItem` + `NSPopover`. Forbidden by 04, 08 and 13 D-context-menu's rationale (12 R1: lower doc number and 13 win over 09).
- D) Drop the shortcut. Contradicts 13 D-hotkey-carbon.

Chosen for now: A. It is the only option inside 04/08 that keeps the 13 decision and uses public API only. It follows the precedent of O-15 and D-context-menu, where a `MenuBarExtra` limit downgraded a feature. 09's row and 14's Stage 1.3 test line are corrected in the same PR (12 R1.2).

Also decided in this stage:
- **Login item in tests:** `SMAppService` sits behind a Core `LoginItemService` protocol. Under Debug `TOKENBE_TEST_ROOT`, the app uses a marker file in the test root instead, so UI tests never register or unregister the owner's real login item. The launch mirror and the failure path (`app.login_item_failed`, toggle back to the actual status) are unit-tested in Core.
- **Appearance:** applied app-wide through `NSApp.appearance` (`nil`/`aqua`/`darkAqua`), which every scene, the popover included, inherits. 09 names `preferredColorScheme` per scene, but `.preferredColorScheme(nil)` is widely reported not to revert a window to the system appearance on macOS, and a single app-wide switch can't miss a scene.
- **Accent:** `.tint(nil)` (system accent) or `.tint(Color(.accent))` (the asset's fixed #0A66FF / dark #3B82F6) on every scene.
- **Sort:** the 09 rule for `tb.popover.sort`, including `manual` with `tb.popover.manualOrder`, is implemented now in Core `AccountOrder` (14 says the manual order is "read in 5.3"). It's small and fully specified in 09, so 5.3 reuses it.
- **Pinned metric:** card row 2 shows the pinned metric (`runwayPair`, remaining, or today's spend) or `No data yet`.
- **Copy 08 doesn't fix:** option labels (`Shortest runway`, `Lowest remaining`, `Today’s spend`, `Warning`), Privacy statements, and the recorder's `Type shortcut…` hint, all in `Strings.swift`.
Blocking: no

## Q-024 Database: PRAGMA order, Repository scope, corruption handling, copy            (2026-11-10)
Context: Stage 2.1 turns 03 into code on GRDB 7.12. Several details are left open by 03 and 14, or are not possible exactly as written.
Decisions:
- **`auto_vacuum`.** 03 says "migration 001 runs it first". `DatabasePool` turns on WAL before any migration can run, and GRDB's WAL setup creates and drops a scratch table. After that `auto_vacuum` can no longer change, and a 001 statement would be a silent no-op. Instead, `AppDatabase.configuration().prepareDatabase` runs `PRAGMA auto_vacuum = INCREMENTAL` as the writer's first statement, before GRDB's WAL setup. Tests assert `auto_vacuum = 2` on a fresh file. 03's comment is corrected.
- **PRAGMAs per connection.** `synchronous`, `cache_size`, `mmap_size`, `temp_store` and `busy_timeout = 5000` run on every connection, readers included. GRDB gives readers a 10 s timeout, which 03 overrides. `journal_mode = WAL` and `foreign_keys = ON` are GRDB's own.
- **`db.busy`.** SQLite's busy handler cannot report how long it waited without replacing `busy_timeout`. A `.callback` busy mode makes `PRAGMA busy_timeout` read 0. So every write goes through `AppDatabase.write(op)`, which measures the wait for the writer, including the `BEGIN IMMEDIATE` lock, and logs `db.busy {op, waited_ms}` above 100 ms.
- **Migrator.** Hand-written, not GRDB's `DatabaseMigrator`, which would add a 16th table, `grdb_migrations`. The version is `MAX(schema_version.version)`. Each `NNN_slug.sql` runs in one transaction, and the migrator appends `schema_version` only if the file did not (001 seeds its own). `db.migrate` is logged once per file, with `dur_ms` as the record's top-level duration, like every other timed event.
- **Repository scope.** Protocol extensions cannot add requirements, so "one extension per aggregate" is one protocol per aggregate composed by `typealias Repository = AccountRepository & MaintenanceRepository`. 2.1 declares only what it implements:
  - the four account methods;
  - `backup`, `integrityCheck`, `quickCheck` and `incrementalVacuum`.
  `observeSummaryInputs` is 2.2's step 1, so it is declared there with its `SummaryInputs` type. A declaration now would be a stub, which step 5 forbids. The rest of maintenance (`rollup`, `purge…`, `thin…`, export, import, `stats`) arrives with those features. 14 step 5 is reworded. D5's "a Repository method per DB object" is met per aggregate as each lands; for now, every record type is written and read by `RecordRoundTripTests`.
- **Corruption.** Only `SQLITE_CORRUPT`, `SQLITE_NOTADB` or a `quick_check` other than `ok` count as corruption. The file is *moved*, not copied, to `tokenbe.sqlite.corrupt-<yyyyMMddTHHmmssZ>`, together with its `-wal` and `-shm`: a stale WAL next to a restored file would corrupt it. Then `.bak` is copied in (`db.restore`), or a fresh file is created. A second failure after the repair is fatal. Permissions, I/O errors and failed migrations are never treated as corruption. They raise the fatal alert and leave every file as it was.
- **Runtime integrity failure** (`integrityCheck()` from the weekly job or 2.2's button). The running file is *copied* to `corrupt-<ts>` and `db.integrity_failed` is logged. Restoring a live database needs every reader closed, so the restore happens through the next launch's check. The weekly job (9.x) decides whether to force that.
- **Account creation** seeds the four `poll_state` rows in the same transaction (03 "runtime seeds").
- **Timestamps.** `DBTime.string` rounds to the millisecond and formats the milliseconds from an integer. `ISO8601FormatStyle` truncates the binary fraction (`.123` printed as `.122`), which would drift a value on every read-then-write.
- **Paths.** `FixtureDBBuilder` lives in `Tests/TokenBeCoreTests/Support/`, because `Tests/Support/` is outside the SwiftPM test target. 14's inventory is corrected. Regenerate with `TOKENBE_WRITE_FIXTURES=1 swift test --filter FixtureDBTests`; `FixtureDBTests` fails if the committed file drifts from what the builder produces.
- **Support folder.** It is set to `0700` with `setAttributes` even when it already exists: Stage 0.4's sentinel created it first, with default permissions.
- **Copy 08 does not fix.** The fatal alert says "TokenBe can't open its database", "Migration <name> failed." or "The database could not be opened.", then the error, "Your data has not been changed." and both paths, with a `Quit` button. The repair alert says "TokenBe repaired its database", then the damaged-copy path and the backup used, or "no backup was found", with `OK`.
Blocking: no

## Q-025 Observation scope, its failure event, maintenance sheets, Verify location            (2026-11-10)
Context: Stage 2.2 (`Store/Observation.swift`, `Ledger/AccountSummaryBuilder.swift`, `SettingsUI/AdvancedTab.swift`, `scripts/stages/2.2.sh`).
Decisions:
- **What is observed.** 14 lists "accounts + poll_state + band_state + latest balance + ledger + recent buckets; the set grows per stage" and says 2.2 fills only identity fields. `SummaryInputs` therefore holds `account` rows only. Each later stage adds the inputs its fields need. Observing tables nothing reads yet would add code with no consumer.
- **`AccountSummaryBuilder`** fills id, provider, label, balance mode and currency. `paused` stays for 4.1, which owns Pause. A row whose `provider`, `balance_mode` or `currency` has no model case is left out of the list, not shown with a guessed value. `AppModel` logs it as `ui.error {view: "accounts", err}`. 03's CHECKs rule this out for provider and mode; `currency` has no CHECK.
- **Observation failure.** 07 has no event for a failed `ValueObservation`, and 14 says 2.2 reuses existing events. The failure is logged as `ui.error {view: "summary", err}` (cat `db`), since what fails is the UI's read path, and the stream ends. Cancelling the stream logs nothing. 07 is unchanged.
- **Sheet copy.** 08 names the two buttons but not their results. Integrity check: title "Integrity check", then "Result: <ok or first line>", then on failure "A copy of the database was saved to <path>". If the check could not run: "Integrity check could not run" and the error. Backup: "Backup saved", "<size>, <date> <time>", then the path. The date uses 08's `MMM d` (`Formatters.date`). 08 has no rule for a time of day or a file size, so these use the system's short time and file byte-count styles. If it fails: "Backup failed" and the error. Every sheet has an `OK` button.
- **No confirm dialog.** Phase 1's postmortem called these "the first destructive controls". Neither one destroys user data: the backup replaces only the previous `.bak` through an atomic rename, and the integrity check only reads, plus a copy on failure. 08 lists a destructive confirm only for `Reset all settings…`, so none is added (R9). Both buttons are disabled while one is running.
- **Verify location.** 14's Verify line tested `~/Library/Application Support/TokenBe/tokenbe.sqlite.bak`, the owner's real folder. That contradicts D10 and Q-014, and would fail `real_support_unchanged`. The UI test asserts `.bak` inside its own `TOKENBE_TEST_ROOT`. It also asserts the app's `app.settings_changed` records for both `tb.db.*` keys. The runner cannot read the app's settings suite (Q-019), and `DashboardShellUITests` resets that suite later in the same run (Q-020). `2.2.sh` checks that the test passed and makes those assertions, and that the owner's real folder is unchanged. 14 is reworded.
- **Remembered Settings tab.** The Settings window reopens on the tab last used in the UI-test suite. 2.2's test leaves General selected, and `SettingsGeneralUITests` selects General itself instead of assuming it.
Blocking: no

## Q-026 Network seam: fixture envelope, unclassified statuses, catches, wiring, interface names            (2026-11-10)
Context: Stage 3.1 (`Sources/TokenBeCore/Network/*`).
Decisions:
- **Fixture file shape.** 11 names fixture files but does not say what is in them. A `rate_limit.429` case needs a status and a `Retry-After` header as well as a body. Options: A) an envelope `{status, headers, body}`; B) body only, with the status read from the case name and headers in a sidecar file. Chosen: A. It is one file per response, and `record-fixtures.sh` (3.6) can write it as easily as a bare body. 11 § Fixtures and `Tests/Fixtures/README.md` now describe it. 3.4's "field names strictly from 02" applies to `body`. `FixtureTransport` and `StubTransport` share one loader. No fixture file is committed in 3.1: R11 requires `record-fixtures.sh --verify-redacted` first, so the tests write their files into a temp folder.
- **`tb.debug.fixtureMode`.** 09 makes it a Bool; 14 said "scenario name". 09 wins (R1). The case for each endpoint is `ok` unless `FixtureTransport(cases:)` names another, so UI tests can choose cases when 3.4/3.5 wire them. The DEBUG fixture root is the source tree's `Tests/Fixtures/providers`, found from `#filePath` inside the function (PM-2.1-1). This works for Debug builds on the machine that built them, which is the only place fixture mode runs. 14 is reworded.
- **`PollError.from`.** 14 wrote `from(status:body:urlError:)`, but parsing `Retry-After` needs the headers. It is now `from(_ response:now:)` plus `from(_ transportError:)`. 04 classifies only 401/403, 429 and 5xx. Every other non-2xx status (3xx after redirects, 400, 404, 409, 422) becomes `providerRule("http <status>")`, which never retries: retrying a 4xx cannot succeed. Adapters map provider-specific statuses, such as Anthropic's 400 for low credit, before the generic mapping. A body over 20 MiB becomes `decode(field: "body", …)`, not `transport`, because retrying cannot shrink it. `Retry-After` is parsed uncapped, and `RetryPolicy` applies 04's 300 s cap once.
- **Catches in the transport.** `URLSessionTransport.send` catches only to translate into `TransportError` and rethrows. It does not log, following `DatabaseOpener`'s translation catches. The poller (3.4) logs the outcome as `poll.retry`, `poll.failed` and the others, so each failure is logged exactly once with its `acct` and `job`.
- **Wiring.** 3.1's DoD has no D7 or D10, and nothing consumes a transport or a reachability monitor yet. So neither joins `AppEnvironment` or `Startup` here: `Transports.make(fixtureMode:version:)` joins when the first adapter does (3.3/3.4), and `NWPathMonitorAdapter` with the scheduler (4.1, as 14 § 0.3 lists). `FixtureTransport.knownRoutes` is empty until the first adapter adds its routes. The reachability test double (`ManualNetworkMonitor`) comes with its consumer in 4.1.
- **`NWPathMonitor` without a queue.** It is consumed as an `AsyncSequence` (macOS 14+), created inside the stream's task, so R6's no-`DispatchQueue` rule holds and the non-Sendable monitor never crosses isolation.
- **`app.network_changed` values.** `online` is `path.status == .satisfied`. `interface` is the first available interface: `wifi`, `wired`, `cellular`, `loopback` or `other`, and `none` when no interface is available. The first status after start is a baseline, not a transition, so it is not logged. A change of interface while staying online is logged.
- **11's suite-wide guard** ("a URLProtocol stub asserts zero real requests"). In 3.1 every test sends through `StubURLProtocol` or `StubTransport`. The one production `URLSessionTransport` built in a test sends nothing. A suite-wide guard that would catch a future mistake is carried forward to 3.4, where adapters first send (PM-3.1-1).
Blocking: no

## Q-027 Keychain: login keychain instead of the data-protection keychain            (2026-11-10)
Context: Stage 3.2, `Keychain/KeychainKeyStore.swift`. 14 step 2 required `kSecUseDataProtectionKeychain = true`.
Finding: a spike showed that an ad-hoc-signed binary (`CODE_SIGN_IDENTITY = -`, no team) gets `-34018` (`errSecMissingEntitlement`) from `SecItemAdd` and `SecItemDelete` on the data-protection keychain. The same calls on the login keychain succeed. Every TokenBe build before H4 (Debug, CI, unsigned Release) is ad-hoc signed, so as written no build could store a key until 11.5. The data-protection keychain needs a `keychain-access-groups` / application-identifier entitlement backed by a provisioning profile.
Options: A) the login keychain; B) keep the data-protection keychain and sign with a team and a provisioning profile now (PM-0.1-3 pulled forward); C) a hybrid, using the data-protection keychain when entitled and the login keychain otherwise.
Chosen: A, by the owner (asked as `Blocking: yes`, because it changes how keys are protected).
Consequences:
- Items are still written `WhenUnlockedThisDeviceOnly` and not synchronizable, under service `dev.bathyon.tokenbe`. The login keychain never syncs to iCloud. It does not enforce "this device only", though: a Migration Assistant transfer can carry the item over.
- Access is controlled by the item's ACL, bound to the app's code signature. An ad-hoc Debug build may ask for the login password. A Developer ID build has a stable designated requirement across updates.
- The login keychain does not return `kSecAttrAccessible`. SEC-2 asserts class, service, account, and that no synchronizable copy exists. 11 SEC-2, 13 D-keychain-only and 14 step 2 are updated.
- Tests use `dev.bathyon.tokenbe.test` only. `3.2.sh` checks that no test builds a store on the production service, and that no test item is left behind.
Also decided in 3.2, not blocking:
- `KeyStore` methods are `async throws(KeyStoreError)` with `failed(op, status)` and `accessDenied(op, status)`.
- An item that is not UTF-8 is a read failure with `errSecDecode`.
- `errSecUserCanceled` (the user refused a prompt) is an ordinary failure at `error`, not `access_denied` at `fault`.
- `set` updates the item, or adds it when it is missing. `delete` of a missing item succeeds.
- `keychain.*` records carry `acct` = the keychain ref (the provider, per SEC-2) and `osstatus`, never the secret.
- `InMemoryKeyStore` lives in `Tests/TokenBeCoreTests/Support/`, the SwiftPM test target, like Q-024's path fix.
Blocking: yes (answered by the owner 2026-11-10: A)

## Q-028 Provider seam: key prefixes, glyphs, Capabilities JSON, onboarding set, the recorder            (2026-11-10)
Context: Stage 3.3 (`Sources/TokenBeCore/Providers/*`, `scripts/record-fixtures.sh`).
Decisions:
- **Key prefixes.** 02 names a key prefix for OpenAI (`sk-admin-`) and Anthropic (`sk-ant-admin01-`) only. OpenRouter's Management key, DeepSeek's and xAI's standard keys have none in 02. 07's redaction patterns are not a validation spec (R2), so for these the probe is the only check. `checkKey` trims whitespace and newlines from the paste, then returns `plausible`, `empty` or `wrongPrefix(expected:)`. The UI turns these into 08's copy in 3.5.
- **Prefixes joined at run time.** As literals, Swift stores these short strings inline in the instructions, side by side, and the build-product scan of `check-no-secrets.sh` then reads `sk-admin…sk-ant-a…` as one key-shaped run. The prefixes are built with `joined(separator: "-")` instead of weakening the guard.
- **Glyph and captions.** 14 step 1 listed a "glyph name" and "onboarding caption strings keys". 08 names no glyph assets, and Paper owns the visuals. The glyph is added with the first view that draws it (3.5/4.2), from Paper, and the captions with onboarding (3.5). Nothing inert is added now. 14 is reworded.
- **`Capabilities` JSON** (stored in `account.capabilities`, 03): `CodingKeys` pin snake_case names (`per_key_usage`, `key_names`, `balance_mode_default`, `usage_lag_s`, `currency_hint`). `usageLag` is stored as whole seconds; `Duration`'s own `Codable` writes an opaque two-integer array. Keys are sorted, so equal values store equal text. Decoding is strict: a missing field or an unknown mode fails. The 2.1 fixture DB stored a placeholder `{"usage",…,"keys"}` shape. It was regenerated with the real one (OpenAI's 02 row), and `corrupt.sqlite` is still its first 4 KiB.
- **Onboarding availability.** `available(isDebug:verified:adapters:)` keeps only providers with a registered adapter in both configurations. DEBUG's "all" would otherwise offer inert tiles (D6). Release keeps only `verified` (R13), in 08's tile order.
- **Unsupported polls.** `ProviderAdapter` gives default `pollUsage`/`pollCost`/`pollBalance`/`pollKeys` that throw `providerRule("<provider>_no_<job>_api")`, matching 07's `poll.provider_rule` examples (`deepseek_no_usage_api`). The scheduler runs only the jobs `Capabilities` allows. Result types wrap 2.1's record types, plus `DiscoveredKey`, because a probe has no `account_id` yet.
- **The recorder.**
  - Redaction follows 11 (`sk-FIXTURE-<provider>-<last4>`, `org_fixture`, `proj_fixture`). 14 said "the 7 patterns", but `check-no-secrets.sh` accepts exactly 11's form. 07's header patterns and the exact live key are applied too.
  - Only `Content-Type` and `Retry-After` are kept from the response headers. Raw headers carry cookies and org ids.
  - The key is read from the environment only, never from `.env`, and goes to curl on stdin (`--config -`), so it never shows in `ps`.
  - Each call writes `<endpoint>.ok.recorded.json` for 2xx, else `<endpoint>.<status>.recorded.json`. Only the first page is recorded.
  - Endpoint names follow 11 where 11 names them. Anthropic's `/v1/organizations/me` is `organization`, and its workspaces call is `workspaces`.
  - Key variables: `OPENAI_ADMIN_KEY`, `ANTHROPIC_ADMIN_KEY`, `OPENROUTER_MANAGEMENT_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY` (extends Q-002's names).
  - `--verify-redacted` delegates to `check-no-secrets.sh --root`, so there is one regex source. `--self-test` is offline. It redacts a canned body with random fake keys, checks the envelope, and checks that the guard still catches the unredacted body.
- **3.1's fixture check.** `3.1.sh` asserted that no `Tests/Fixtures/providers` file is committed, a rule premised on the recorder not existing. Now the recorder exists, so the check is `record-fixtures.sh --verify-redacted` over `Tests/Fixtures`. 3.4's synthetic fixtures need this.
Blocking: no

## Q-029 OpenAI adapter: fixture names, paging, cost rows, probe outcome and copy, poll_state, V2, test guard            (2026-11-10)
Context: Stage 3.4 (`Providers/OpenAI/*`, `Scheduling/Poller.swift`, `Store/Repository+{ProviderKeys,Usage,Cost,Poll}.swift`, `Network/NoNetworkInTests.swift`, `Tests/Fixtures/providers/openai/`).
Decisions:
- **Error fixture names.** 14 and 11 named them `auth.401`, `forbidden.403`, `rate_limit.429`, `server.500`. `FixtureTransport` picks `<endpoint>.<case>`, and the recorder writes `<endpoint>.<status>` (Q-028), so those names could never be served. They are `projects.401`, `costs.403`, `usage_completions.429` (with `Retry-After: 12`) and `usage_completions.500`. Their bodies are JSON strings: 02 gives no error-body shape, and the adapter treats error bodies as opaque text. 11 and 14 are reworded.
- **Two-page fixture.** `usage_completions.ok` is page 1 (`has_more: true`, `next_page: "page2"`) and `usage_completions.page2` is page 2. `FixtureTransport` maps a `page=<cursor>` query to that case (only `[A-Za-z0-9_]` cursors), so DEBUG fixture mode pages once and stops.
- **Page wrappers 02 leaves implicit.** Projects and api_keys decode only `data[]`, and costs reuse 02's usage page shape (`object`, `data[]` buckets, `has_more`, `next_page`). Projects and api_keys are not paged (`limit=100`, and 02 names no cursor for them). Costs are paged until `has_more` is false: `now − 7 d` floored to UTC midnight spans 8 daily buckets, and the default `limit` is 7.
- **Required fields.** Usage results require `input_tokens`, `input_cached_tokens` and `output_tokens` (05 uses them without a default). Everything else is optional: `num_model_requests` absent → 0, a null `model` → `'*'`, and a null `api_key_id` or `service_tier` → `''` (03's "not grouped"). Cost results require `amount.value` and `amount.currency`. Keys 02 does not list are logged, never fatal: inside a usage result as `normalize.unknown_keys`, elsewhere as `poll.unknown_keys`, each once per UTC day per key path.
- **Usage rows.** Results that land on one primary key are summed before writing. `provisional = bucket_end + usageLag ≥ fetched_at`, with usageLag 3600 s (02). `est_cost_cents` is NULL and `unpriced` is 0 until pricing exists (4.x); pricing fills them.
- **Usage cursor.** `poll_state.cursor` holds `<start_time> <next_page>`. OpenAI's page token belongs to the query it came from, so a resumed sequence repeats that `start_time`. Each page's rows and the cursor commit in one transaction. A failure keeps the cursor, and success clears it. A cursor that repeats, or more than 50 pages, fails as `providerRule`.
- **Cost rows.** Per UTC day: one `api_key_id` row per key, one `line_item` row per line item and one `total` row. A null key or line item is `''`. Each row is summed in `Decimal` from the JSON text and rounded half up to cents once. `total` is Σ of the day's results, not of the rounded group rows. A day with no results writes `total = 0`. Currency is the results' `currency`, uppercased (`usd` → `USD`). `provisional = day_end + usageLag ≥ fetched_at`. A re-fetch deletes and rewrites every day it returns, in one transaction.
- **Keys.** Upsert sets `status = 'active'` and refreshes `name`, `redacted`, `project_id` and `last_seen_at`. `first_seen_at` is kept. A key missing from a later list is left as it is: 02 has no status field, and 03 lists no other status value. `created_at` and `last_used_at` are decoded but not stored, because 03 has no column for them (3.5's Keys & apps table needs a Q there). The `api_keys` route in fixture mode is `proj_fixture`'s.
- **Probe outcome.** Step 1 failing (401 → 02's admin-key sentence, 403 → missing-scope copy) ends the probe without steps 2–4. A 401/403 on step 2 turns `keyNames` off; on step 3, `usage` and `perKeyUsage`; on step 4, `cost`. The probe still passes, with the redacted body in `rawBodiesRedacted`. Offline, 429, 5xx or an unreadable body ends the probe with a message. The probe never retries. Onboarding (3.5) treats `humanMessage == nil` as success.
- **Probe copy.** Only the 401 sentence comes from 02. The 403, 429, 5xx, offline, unreadable-body and other-status messages are authored in `CoreStrings`, pending Paper/08. 02 § openai Errors stays as written.
- **Poller.** The lookbacks are usage 48 h and cost 7 d. `acct` in `poll.*` records is the provider name, as in 07's example. `last_error_class` is `auth`, `transport`, `server`, `rate_limited`, `decode`, `provider_rule`, `keychain` or `store`, and `last_error_message` is redacted and ≤ 512 chars. Rules for the other outcomes:
  - **Retries.** Per request, so each page gets 04's budget. `poll.rate_limited` is logged for every 429; `poll.retry` only when a retry follows.
  - **Decode failure.** Logs `poll.schema_drift {missing_keys, path, sample}` and stores the failing body, redacted, as `last_raw` (04). 02's "last successful" body is kept otherwise.
  - **Failure streaks.** `consecutive_failures` counts failures of ONE class in a row: a failure whose class differs from `last_error_class` restarts it at 1. 04's circuit needs "3 consecutive auth failures", so `500, 500, 401` must not open it. The backoff and 04's "3 consecutive decode failures" badge read the same per-class streak.
  - **Circuit.** `poll.circuit_open` is logged when an auth failure sets `circuit_open_until`. `poll.circuit_close` is logged on the first success after it.
  - **Not run.** A job the capabilities do not allow is skipped with `poll.provider_rule`, as is an account without an adapter. A cancelled job records nothing.
  - **Missing key.** Logs `keychain.missing` and records a `keychain` failure.
  - **`keys` job.** `last_raw` is the last `api_keys` body.
  - **`balance` jobs.** No provider has one yet. The DeepSeek stage adds `Repository+Balance` and the write. Until then, a balance-capable account fails as `providerRule`.
- **V2.** Checked in every build, not with a DEBUG `assert`: 04's DoD wants a test that triggers it. A mismatch rolls back the page (rows and cursor), throws `StoreError.writeIncomplete`, and logs a new event, `poll.write_incomplete {expected, written}` (error), added to 07. The poller then logs `poll.failed`. The sum compares all token classes and requests after the negative clamp, on both sides.
- **No real network in tests (PM-3.1-1).** A globally registered `URLProtocol` does not reach the ephemeral session `URLSessionTransport` builds (spike). In a DEBUG test process, a transport built without stub protocols gets `NoNetworkInTests` instead of the HTTP stack. A test process is one whose main bundle is not an `.app`. The first version keyed on XCTest being loaded, which CI's Swift Testing runner does not do, and two unauthenticated requests reached `api.openai.com` from CI (PM-3.4-9). Every request fails at once with `notConnectedToInternet` and is counted. A test proves it on the production initializer and on `Transports.make(fixtureMode: false)`.
- **Wiring (PM-3.3-2).** `AppEnvironment` holds `transport` (`Transports.make(fixtureMode: settings.debugFixtureMode, …)`) and `registry` (`ProviderRegistry(adapters: [OpenAIAdapter()])`), both built at launch, so a fixture-mode change takes effect at the next launch. Release onboarding still offers nothing, because `Verified.providers` is empty.
- **Outside the inventory.** `Logging/EventLog.swift` (an `EventLog` for Core types that log under several categories, plus `DailyOnce`), `Providers/RawBody.swift` (redact-then-truncate and `ResponseTrace`), `PollContext.trace`, `UsagePage.expected` and `StoreError.writeIncomplete`.
Blocking: no

## Q-030 Onboarding and Accounts: window, copy, test key store, fixture cases, startup step 3, Keys & apps            (2026-11-10)
Context: Stage 3.5 (`Onboarding/*`, `SettingsUI/AccountsTab.swift`, `Accounts/AccountLifecycle.swift`, `Startup.swift`, UI tests).
Decisions:
- **A window, not a sheet.** 08 says "sheet 520×440". A menu-bar app has no window to carry one: the popover closes when focus moves, and Settings may not be open. Onboarding is its own fixed-size `Window` scene (520×440, never restored). `openWindow` is captured from the menu-bar label, as for the Dashboard (Q-023). `Replace key…` is a real sheet on the Settings window, reusing step 2.
- **Launch.** 09: onboarding opens at launch when `tb.ui.onboardingDone` is false and there is no account. `onboardingDone` becomes true when step 2 creates the account (14 step 1), so closing at step 3 still counts as done. Every UI test launches with `-tb.ui.onboardingDone <true/>` unless it tests onboarding. Booleans go as plist literals, so the argument domain yields a Bool.
- **Copy.** 08 gives the tile captions, `Added`, `Cancel`, `Continue`, `Paste`, the OpenAI wrong-prefix message, `Test & continue`, `Set anchor…`, `Skip for now`, `Launch at login`, `Done`, `Add account…`, `Key missing · Fix…`, `Replace key…`, `Test`, `Remove account…`, `Keys & apps` and `Valid · tested <freshness>`.
  - **Taken from Paper** where 08 is silent: the step header `Provider — Key — Balance`, `Which provider?`, `<Provider> admin key`, `Admin API key`, `Stored in the macOS Keychain, this device only.`.
  - **Authored**, all in `Strings.swift`, `CoreStrings.keyMissing` excepted:
    - step 3's `First numbers` labels (`Mode`, `Keys found`, `Currency`), `Balance shown by the provider` and `Anchor: $N`;
    - the generic wrong-prefix line for providers without 08 copy;
    - the create, replace and anchor failure lines;
    - the remove confirmation text;
    - `Key missing`, `Select an account.`, `No keys found yet.` and `(unnamed key)`;
    - `CoreStrings.keyMissing`, the result of `Test` without a key.
  - Paper's step-3 auto-reload toggle and step-2 capability list are not in 08, so they are not built (R9).
- **Glyph (PM-3.3-1).** 08 names no glyph asset, so the provider glyph is Paper's filled circle with a letter (`O`, `A`, `R`, `D`, `X`), drawn in code. Anthropic's wrong-prefix copy is not in 08, and only OpenAI has an adapter, so DEBUG offers no Anthropic tile. The generic line covers it until the Anthropic stage (10.1) brings 08's copy or a Q.
- **Keys in UI tests (PM-3.2-1).** Under a DEBUG `TOKENBE_TEST_ROOT` the app keeps keys in `test-keychain.json` inside the root (`FileKeyStore`, DEBUG only), never in a keychain. Ad-hoc builds change their signature on every build, so a keychain item one build wrote makes the next one prompt for the login password. The sandboxed runner cannot read the app's items either. 14's "Remove account deletes Keychain item — checked via the test's own `KeychainKeyStore` read" is covered in two places:
  - `AccountLifecycleTests` checks that `remove` deletes the item, in process (with `InMemoryKeyStore`; `KeychainKeyStore.delete` itself is covered by the 3.2 integration test on the `.test` service);
  - the UI test reads the root's key file.
- **Fixture cases (PM-3.4-1).** DEBUG, test root only: `TOKENBE_TEST_FIXTURE_CASES=openai/projects=401` reaches `FixtureTransport`'s `cases` through `Transports.make(cases:)`.
- **Probe and writes.** The probe passes when `humanMessage` is nil (Q-029). It times out after 10 s on the injected `Clock` and returns the unreachable message. On success, `AccountLifecycle.create` writes:
  - the Keychain item (ref = provider);
  - the account: UUIDv7 id, label (blank → provider name), `balance_mode` from the capabilities, currency, `capabilities` JSON, `created_at`;
  - its four `poll_state` rows;
  - the discovered keys.

  If the database refuses any of it, the item and the row are removed again. A wrong prefix disables `Test & continue`: the button validates and is not inert (D6), and fixture mode would otherwise accept any key.
- **Startup step 3 (PM-3.2-2).** It checks each account's Keychain item for existence only (`KeyStore.contains`, attributes, no secret: R8, and no ACL prompt). A missing item logs `keychain.missing` (error) and sets `needsKey`. A keychain that cannot be read (locked, denied) is not "missing". `Replace key…` and a new account clear `needsKey`. `Test` and `Replace key…` reset the circuit (04) and log `poll.circuit_close` for each job that was open.
- **Summary inputs (PM-2.2-3).** `SummaryInputs` gains each job's `last_success_at` and `circuit_open_until` (never `last_raw`), so cards show `never` before the first poll. `needsKey` comes from startup step 3's set.
- **Accounts tab.**
  - Paper's 720 pt master-detail, with the form tabs at 520 pt; the selected tab lives on `AppModel`, so `Fix…` can open Accounts.
  - The label saves on Return or when the detail closes.
  - `Valid · tested <freshness>` uses the latest of creation (a passed probe), the last successful poll and the last `Test`.
  - Keys & apps shows 08's name and hint (`…a1b2`, the last 4 characters of `redacted`). 14 also listed "created, last used"; 08 does not, and 03 has no columns for them, so 08 wins (R1). The bound-app picker arrives in 7.1, as 14 says.
  - The anchor amount is parsed in `Formatters.cents(fromInput:locale:)`, since `Decimal` lives only in `Formatters` (R7).
- **Sidebar rows.** Account rows show the glyph, label and an `unknown` band dot. They cannot be selected until the account detail exists (5.x), so no row leads nowhere (D6).
- **Crowded menu bar (PM-1.1-3).** First-run guidance would add copy and a screen that 08 does not list (R9). Re-targeted to the release review (11.2), with Q-019's overflow handling unchanged.
Blocking: no

## Q-031 UI tests: run at stage end only when the stage touches the app, always at phase end            (2026-11-10)
Context: `scripts/verify-stage.sh`, the UI-test checks of `scripts/stages/{0.4,1.1,1.2,1.3,2.2,3.5}.sh`. The owner chose the "middle ground" on 2026-11-10.
Problem: every stage's verify ran the full XCUITest suite: about 10–12 minutes, an unlocked screen, and an occasional flake. Core-only stages such as 3.4 paid that for code the UI cannot reach.
Options: A) UI tests at every stage end (the old rule); B) only at phase end; C) at phase end, and at stage end when the branch changes app or UI-test code.
Chosen: C, by the owner.
- `verify-stage.sh <id>` turns UI tests on when `<id>` is the last stage of its phase (§ 0.5), or when the branch's diff from `origin/main` (committed, uncommitted or untracked) touches `Sources/TokenBeApp/`, `Tests/TokenBeUITests/`, `TokenBe.xcodeproj/` or `Config/`. Otherwise they are off. `TB_UI_TESTS=1|0` overrides. The first line of a run states the mode and why.
- Off, each UI-dependent check (`ui_check`) prints `skip <stage> <name>`. These are the UI suite run and every check that reads its log or the UI-test settings suite. Everything else still runs: unit tests, lint, the guards, D10's launches and D13.
- CI is unchanged; it never ran UI tests.
- Consequence: a UI regression from a Core-only stage surfaces at the next app-touching stage or at phase end, and is fixed there. The postmortem names the stage that introduced it.
Blocking: no (decided by the owner)

## Q-032 OpenAI verification: the first recording held no rows; recorder pages, anonymizes and records the 401   (2026-11-12)
Context: 14 § Stage 3.6, H2. The owner's first `record-fixtures.sh openai` run (2026-11-12) succeeded, but the org had no activity: no project keys, and empty `results[]` in every usage and cost bucket.
Problem: an empty recording confirms the envelopes only. 02's row fields (api_keys, usage and cost results) stay unconfirmed, so OpenAI cannot be marked verified (D-verified-providers). The recorder also had two defects that a row-bearing re-record would hit:
- it fetched only page 1, and both endpoints page (24 hourly / 7 daily buckets per page), so today's activity would be on a page never fetched;
- the real `next_page` token (`page_AAAA…=`) is not a valid fixture case (`[A-Za-z0-9_]`), so a recorded page 1 with `has_more` would make `FixtureTransport` serve page 1 again.

Personal data matters too, since the repository is public: real API-key rows carry the owner's name and email.
Options: A) mark verified on the envelopes; B) keep `[expected]` on row fields, fix the recorder, re-record after real usage; C) hand-edit the recorded files.
Chosen: B.
- **Pages.** `fetch_pages` follows `next_page` until `has_more` is false (at most 8 pages). Page 1 is case `ok`, page n is `page<n>`, and each written page's `next_page` is rewritten to the next case (Q-029's mapping). The live token is percent-encoded in the next request.
- **Anonymizing.**
  - `key_…` ids become `key_fixture_<last4>`, consistent across the api_keys and usage files;
  - `user-…` ids become `user_fixture`;
  - emails become `owner@example.invalid`;
  - the `name` of any object with an `email` becomes `Fixture Owner`.

  Key names are free text, so the owner names the fixture key `tokenbe-fixture`.
- **The 401 body (PM-3.4-2).** The recorder repeats the projects call with a key that cannot exist (the `sk-admin-` prefix followed by `TOKENBEFIXTUREINVALID0000`, split in the script so no key-shaped literal is committed) and writes `projects.401.recorded.json`.
- **Confirmed now.** The list envelope (`object`, `first_id`, `last_id`, `has_more`), the project fields, and the bucket `start_time_iso` and `end_time_iso` are in 02 and declared as known DTO keys, so they never log `poll.unknown_keys`. The empty recordings are kept outside the repo. The re-record replaces them.
- **Archived projects** (`status`, `archived_at`) are declared but not filtered: probe step 2 still lists every project's keys. Revisit if a recording shows an archived project.
Blocking: no

## Q-033 Stage 3.6 merges with H2 open; its gate checks wait for the RECORDED marker            (2026-11-12)
Context: 14 § Stage 3.6, `scripts/stages/3.6.sh`. The re-record (Q-032) is waiting on the owner, and the owner asked to move on to 4.1 meanwhile (2026-11-12). `verify-stage.sh 4.1` re-runs every earlier stage, so 3.6 needs a stage script and postmortems before 4.1 can pass.
Options: A) merge 3.6 now with H2 open (14 § 0.6 rule 4); its script asserts what holds today, and the gate checks run once `openai/RECORDED` exists; B) add a "pending gate" skip list to `verify-stage.sh`; C) hold 4.1 until the owner records.
Chosen: A. 14 § 0.4 says H2 blocks only the Verified flip, and § 0.6 rule 4 lets a stage merge with its gate open, with an addendum later.
- **Asserted now:**
  - the recorder pages, anonymizes and records the 401;
  - the confirmed envelope keys are in 02 and the DTOs;
  - `--verify-redacted` and `check-no-secrets.sh` pass;
  - `VerifiedProvidersTests` and `OpenAITests` pass;
  - openai is still out of `Verified`.
- **Gate checks:**
  - the recorded fixtures exist;
  - `.openai` is in `Verified`;
  - zero `[expected]` in 02 § openai.

  Without the marker, they print one visible `skip` line, never a silent pass.
- **The PR that consumes H2** makes the gate checks unconditional. It also updates `3.4.sh`, whose "no RECORDED marker" and "empty Verified" checks fail once the owner records (PM-3.6-2).
- The invalid-key literal of Q-032 is split in the recorder, so `check-no-secrets.sh` (run by 3.4 and 3.6) stays clean.
Blocking: no

## Q-034 Stage 4.1: scheduling rules the docs leave open            (2026-11-12)
Context: 14 § Stage 4.1; `Scheduling/{Job,SchedulerLoop,AccountPoller,PollCoordinator,PollCoordinator+Inputs}.swift`, `SettingsUI/{SourcesTab,AccountsTab}.swift`, `Popover/PopoverView.swift`, `scripts/stages/4.1.sh`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Next run.** A) completion + interval; B) dispatch + interval. Chosen A: 04's backoff is "interval × 2ⁿ after a failed attempt", which counts from the attempt's end. An overrun-cancelled job runs at the next tick (04).
- **Coalescing.** A job runs in a wake when it is due within the 5 s tolerance of that wake (04: "tolerance lets the OS coalesce"). This makes 11's "two jobs due within 5 s run in one wake" deterministic on `TestClock`.
- **Skipped jobs** (`sched.skip` paused / circuit_open / offline) wait one interval and log once per due time. These transitions run every job of the account at once: the end of the global pause (the loop wakes at `tb.poll.pausedUntil`), `Resume`, unpausing an account, a reset circuit (`Test` / `Replace key…`) and a reconnect (for jobs skipped as offline). 07's `low_power` reason is not used: Low Power stretches intervals ×multiplier (04) instead of skipping.
- **Interval changes** pull a pending run in (`min(nextDue, now + new interval)`); a longer interval applies from the next run.
- **Clock jumps and wake.** Both log `sched.clock_jump` with `reason` (`drift`, `wake`; 07 updated) and clamp every next run into `now … now + interval`, so a job that missed several periods runs once.
- **`refreshNow`** (header button) obeys the skip rules: an open circuit stays shut (04: polls stop until the key is re-tested) and a paused account stays paused. A job in flight is not started twice: `sched.overlap_skipped` (I1). The button is hidden while globally paused (the header shows `Resume`) and while there is no account (D6: no inert control).
- **Accounts come from the store's observation** (`observeSummaryInputs`, the UI's own stream). A new account is polled at once, so onboarding's `Done` sends nothing (PM-3.6-3). `Remove account…` first awaits `coordinator.stop(account)`, which cancels its running jobs and ignores the row until the store drops it. Otherwise a poll could read a key that is being deleted.
- **A missing key** (`needsKey`) is not a skip reason in 07. The account is polled; each attempt logs `keychain.missing` and backs off to 15 min. `Fix…` is the remedy.
- **`account.interval_override_json`:** each value is clamped to the range of the global key it overrides. An out-of-range value or an unreadable document is logged once as `app.settings_changed {key: account.interval_override_json, clamped: true, source: system}` (09's clamp rule; 09 updated). `cost` overrides are kept but not read, since `cost` is a daily-activity job (04 § Daily activity, 4.3). The Accounts-tab disclosure is `Refresh intervals`, with one toggle per minute-cadence job (`Usage every`, `Balance every`, `Keys every`) and the Sources setting shown when off.
- **Sources tab steppers:** 30 s steps for balance, 1 min for usage, 10 min for keys, each within its 09 range. Values read `30 s`, `5 min`, `1 h 30 min` (`Formatters.interval`). The multiplier reads `×4`. Paper Desktop was not running, so `YP-0`'s control style could not be checked; the Advanced tab's Stepper pattern is used, to reconcile in 11.3.
- **Popover footer:** 08's four actions (`Open dashboard`, `Settings…`, `Pause polling for 1 h` / `Resume`, `Quit`) need about 430 pt in one row, more than the 360 pt popover, so they wrap to two rows. The cards' scroll height goes from 460 to 430 pt to stay within 560 pt. Check against Paper `1-0` in 11.3.
- **Header freshness** is the oldest of the accounts' last successes (`AccountSummary.refreshedAt`). Never-polled accounts are left out; with none polled yet, the header shows no freshness. It re-renders every 30 s through `TimelineView` (no Timer, R6).
- **Verify's 3-minute cadence run** (14) launches the app with settings as launch arguments (the argument domain, never stored). It seeds the account with `sqlite3` and the test key file, and requires `poll.ok usage` gaps of 60 s ± 5 s with zero error/fault records. It launches the app, so it runs when UI tests run (Q-031).
Blocking: no

## Q-035 Coverage gate raised to 97 %            (2026-11-12)
Context: PM-0.5-2 (stage-0.5.md). The owner asked what 100 % line coverage of `TokenBeCore` takes. True 100 % needs a fake filesystem seam, which 14 § 0.3 forbids; about 97–98 % is cheap. On 2026-11-12 the owner chose 97 %.
Options: A) 97 % now, in its own process PR; B) the cheap part in 11.2 (the old default); C) stay at 85 %.
Chosen: A, the owner's decision. Coverage went from 93.31 % to 97.08 % (5019/5170 lines) with tests only, plus one code change: `FileKeyStore` takes a `logPipeline:` (PM-2.1-2).
- **Added:**
  - `FileKeyStoreTests`;
  - `PollerFailurePathTests`;
  - `OpenAIEdgeTests`;
  - `IntegrityFailureTests`, on two new `sqlite3`-built fixtures, `db/index_mismatch.sqlite` and `db/shared_root.sqlite`. GRDB's connections are defensive, so `writable_schema` cannot be used from a test;
  - `LogSinkFailureTests` (folder permissions);
  - `UserDefaultsStoreEdgeTests`;
  - `AccountLifecycleEdgeTests`;
  - coordinator, loop and facade cases.
- **Left uncovered on purpose:**
  - `CrashHandler.install` and the live signal path (needs a crash-probe executable);
  - Redactor patterns 2 and 6 (pattern 1 already removes those keys, so their closures cannot run);
  - the token formatter's overflow branch (unreachable for `Int64`);
  - a few defensive `??` fallbacks.
- **A bug the loop found:** a job cancelled during a store write (account removed, quit, overrun) reached `Poller`'s store-failure path and logged `poll.failed` at error. `Poller` now returns `skipped("cancelled")` for `CancellationError`, as it already did for a cancelled request (`PollerFailurePathTests.cancelledDuringWrite`).
- **The gate is 97 %** in `ci.yml`, `coverage-gate.sh` (default), `0.5.sh`, 10, 11 and 14 § Stage 0.5. Every later stage keeps it: a stage that adds Core code adds the tests that cover it.
Blocking: no

## Q-036 Stage 4.2: freshness, offline and account-page rules the docs leave open            (2026-11-12)
Context: 14 § Stage 4.2; `Ledger/Freshness.swift`, `AppModel`, `Popover/{PopoverView,AccountCardView}.swift`, `Dashboard/{AccountDetailView,BadgesRow,SourcesStrip,SidebarView,DashboardView}.swift`, `Scheduling/Poller.swift`, `Network/NetworkMonitor.swift`, `scripts/stages/{1.2,4.1,4.2}.sh`.
Options and choices (each the least code; none adds a dependency, screen, setting or event):
- **Never polled.** A) not stale, reads `never`; B) stale after multiplier × interval from `created_at`. Chosen A: 05's rule is about `last_success_at`, and `never` already says there is no data.
- **Paused accounts** follow 05 literally: their data goes stale like any other. The header's `Paused · resumes …` explains why.
- **Primary job without a minute cadence** (an anchored account whose provider has no usage endpoint, e.g. 02's xAI fallback) or unreadable capabilities: never stale. There is nothing to be stale against.
- **The threshold's interval** is the scheduler's own (`Job.interval`: the account's override or the 09 setting, × the Low Power multiplier while Low Power Mode is on). Otherwise Low Power would mark every account stale. `CoordinatorState` gains `isLowPower`.
- **Stale with no database write.** Offline skips write nothing, so `AppModel` sleeps on `ContinuousClock` until the next account's stale instant (`Freshness.apply` returns it) and rebuilds then. It also rebuilds when an interval, the multiplier or Low Power changes. No Timer (R6).
- **Offline overlay.** 08 says "all cards stale overlay": every card dims, and its freshness reads `stale · …` in `HealthLow`, so the state is in the text and not only in the opacity (08 § Accessibility). The UI test asserts the text.
- **Offline in UI tests.** Under a DEBUG test root, `TOKENBE_TEST_OFFLINE=1` makes Startup follow `FixedNetworkMonitor(online: false)` instead of `NWPathMonitorAdapter` (14 § 0.3 seam table updated). Release builds do not contain it.
- **`poll_state.last_error_message`** now stores the human message: 02's probe messages and `CoreStrings`, via `PollError.humanMessage(provider:)`, which the probe shares. Keychain failures store `CoreStrings.keyMissing`; store failures store the new `CoreStrings.storeFailed`. The raw cause (`HTTP 500: <body>`, `URLError -1009`) moves to `poll.failed`'s `ctx.detail`, redacted by the record (07 and 03 updated). Before, the strip would have had to parse raw text.
- **Sources strip.** One entry per job in `Job.allCases` order. Keys is included, because 14 says "per job". Paper `HP-0`'s layout: a `Window` panel of 200 pt columns, a caption title over one line. The copy is 08's: `ok · 2 min ago · next 3 min`, `failed · …` plus the message in `HealthLow`, and `n/a`. A job never attempted reads `never`. The daily `cost` job shows the clock time of its last success (`ok · 02:10`, 08) and no next run until 4.3. The accessibility label is the whole 08 chip (`Usage · ok · …`). `next …` comes from `CoordinatorState.nextDue`: the scheduler's slot (backoff included) moved to the wall clock and rounded to the second. `Formatters.untilNextRun` gives `42 s`, whole minutes rounded up (`3 min`), and `now`.
- **Badges.** The words are 08's, styled as Paper `B1-0` (a capsule with a check where the provider reports it, an outlined cross where TokenBe estimates). Balance follows the account's mode (`spend_only` → `none`); usage, cost and lag follow the capabilities. Each help sentence paraphrases 02 in one sentence (`Strings.help*`); lag has one per provider from 02's matrix.
- **Header.** Glyph, label, mode chip, band pill (the band word on a tinted capsule), freshness, and `Refresh`, which runs that account's jobs. `Set anchor…` and `Add top-up…` arrive with their sheets in 5.3 (D6). Paper's `Open console ↗` and `Copy diagnostics` are not in 08 and are left out.
- **Dashboard toolbar `Refresh`** (08) arrives here: the account shown, or every account on the Overview. 1.2.sh's "no Refresh yet" guard is retired.
- **A card click** opens the Dashboard on that account's page (08). `AppModel.dashboardSelection` replaces the view's own state. A removed account falls back to the Overview.
- **Accessibility identifiers.** `popover.cards` is removed, because SwiftUI moved it onto a lone card and hid `popover.card.<provider>`. The glyph exposes `glyph.solid|notched|dashed` on the status item.
- **PM-4.1-5 (`needsKey` accounts keep polling):** kept. Each attempt logs `keychain.missing` and backs off to 15 min, so an account left without its key logs about 4 errors an hour. For SOAK-1 that is an explained error, and the card, the sidebar (`Key missing`) and the strip (`failed` with `CoreStrings.keyMissing`) all show the cause. A new skip reason would change 07's `sched.skip` contract for no user benefit.
- **PM-3.4-8:** the write of `tb.ui.dashboardRange = 7d` could not be reproduced, and the logs of that run were in a deleted test root. `1.2.sh` no longer reads the shared UI-test suite. It requires `DashboardShellUITests.testCommandDOpensDashboardAndRangePersists` to pass, and that test asserts the range and the frame after its own relaunch.
- **`run.sh uitest`** takes `TB_UI_ONLY=<Suite>[/<test>]` for single-suite reruns.
Blocking: no

## Q-037 Stage 4.3: daily-activity rules the docs leave open            (2026-11-12)
Context: 14 § Stage 4.3; `Scheduling/DailyActivity.swift`, `TokenBeApp/DailyActivityRegistration.swift`, `SettingsUI/{SourcesTab,AdvancedTab}.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **A failing step** logs the new `sched.daily_step_failed {step, err}` at error (R5: every catch logs a 07 event; 07 had none for this). `sched.daily_end` adds `run` and `<step>_ms` per step (14: "each step's duration logged in ctx"), and is `warn` when a step failed.
- **Retry at the next activity** (04). An ungated step runs every day anyway. A gated step (the weekly `integrity_check`) that failed runs again at the next run, whatever its gate. The retry set is kept in memory, so after a relaunch the gate decides.
- **Run numbers:** a run is `tb.daily.runCount + 1`. `tb.daily.lastRunAt` and `tb.daily.runCount` are written after each completed run (09), whether or not a step failed.
- **Overlap:** a run requested while one is running is skipped. That happens with `Run daily tasks now` during a scheduled run. It is logged `sched.overlap_skipped {job: daily}` (07's existing event) and writes nothing.
- **Cost polls** run for every account whose stored capabilities include `cost`, through the same `Poller` as the scheduler. The global pause, a paused account and an open cost circuit are skipped with `sched.skip {reason}`, as the scheduler skips them. Offline is not checked: the poll fails, the step fails, and the next activity retries it. Any account's failed cost poll fails the step (`CostPolls.Failed`).
- **The weekly integrity step** writes `tb.db.lastIntegrityCheckAt`, as Advanced's button does. It fails the step when the result is not `ok`; the check itself has logged `db.integrity_failed` and copied the database. The backup step writes `tb.db.lastBackupAt`.
- **`Run daily tasks now`** is disabled while a run is in progress and shows a small spinner. This is transient, not an inert control (D6).
- **`Last daily run`** reads `never`, or `MMM d` plus the time of day, as the backup sheet does (Q-025).
- **PM-4.2-2:** the account page's cost source shows `ok · HH:mm` and no `next …`. `NSBackgroundActivityScheduler` does not expose its next run time.
- **First run:** the system chooses when the first scheduled run happens (D-daily-no-fixed-time). Nothing runs at launch.
Blocking: no

## Q-038 Stage 5.1: price-book rules the docs leave open            (2026-11-13)
Context: 14 § Stage 5.1; `Pricing/{PriceEntry,Lookup,PriceFeedFetcher,PriceBook}.swift`, `Store/Repository+Prices.swift`, `TokenBeApp/{PriceBookModel,Startup}.swift`, `SettingsUI/{PriceBookSection,AdvancedTab}.swift`, `Dashboard/SourcesStrip.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Rate unit:** the feed's USD-per-token numbers become `Int64` picodollars per token (10^-12 USD; 2.5e-06 → 2_500_000) once, at decode. That is the only floating-point step on money (R7 forbids `Double` arithmetic and allows `Decimal` only in `Formatters`). `PriceLookupTests` checks that no positive rate in the bundled snapshot rounds to 0, which V5 would otherwise silently turn into "unpriced". 5.2 sums costs in a wider integer and rounds to cents once.
- **Override JSON** uses the feed keys (03), each rate written as `<picodollars>e-12`, which reads back to the same integer. The UI enters and shows rates in **USD per 1M tokens** (the parsing lives in `Formatters`). The table shows model, input, output, cache read and cache write; `cache_creation_input_token_cost_above_1hr` is not editable (the feed's value or the 2× fallback applies). The DB fixture's legacy `{"input":…}` override is left as is (it is committed binary); its rates read as missing, so V5 makes it unpriced.
- **Lookup with V5:** a hit whose input or output rate is missing or ≤ 0 stops the search and is unpriced ("first hit wins"); a later step is not tried. `-latest` is appended to the model as reported, not to the date-stripped name. `PriceBook.lookup` returns the hit with its step.
- **Snapshots:** `version` is the UTC day of the fetch. A second new document on the same day (`Refresh now` plus the daily run) replaces that day's row. The feed body is stored as fetched; only `chat` entries are parsed. A 304 or a body with the current sha256 adds no row, but moves `fetched_at` (and a new ETag) to the check, so staleness measures the **last successful check**, not the last change. `prunePriceSnapshots(keep: 4)` never deletes the current row. The bundled row's `fetched_at` is when it was installed.
- **Failures:** a non-2xx, non-304 status is `price.feed_failed {reason: transport}`. A body over 20 MB is `reason: size`, whether the transport or the fetcher caught it. A body that is not a JSON object is `price.parse_failed`. O-6's shape check counts **chat** entries: none left, or fewer than half with `input_cost_per_token`, is `reason: shape`. The 10 s timeout is `URLRequest.timeoutInterval` (the idle timeout; the session's 30 s resource timeout still caps the whole fetch), through a new optional `HTTPRequest.timeout`.
- **Startup step 4** (`prices`, after `accounts`) never stops launch. A missing or unreadable bundle, or a current snapshot that does not parse, logs `price.parse_failed`. A current snapshot that does not parse falls back to the bundled table in memory; nothing at all means every model is unpriced. A store failure logs `ui.error {view: startup}`.
- **Daily step `price refresh`** runs after `cost polls` and before `db backup` (04; roll-ups and the update check insert themselves later). With `tb.price.feedEnabled = false` it only checks staleness. A feed failure is a warn and the step succeeds; only a store failure fails the step. `price.stale` is checked at launch and after every refresh, both scheduled and `Refresh now`.
- **07 ctx additions:** `price.feed_ok` adds `source` (`bundled`, `feed`), `changed` and `version`; `price.override_set` adds `action` (`set`, `removed`, `reset`); `price.parse_failed` and `price.stale` may add `version` or `model`.
- **UI (Paper `10V-0`):** Paper's row 1 copy is used: the title, then the line `Snapshot v<day> · N models · N overrides · refreshed <freshness> · the only other network call`, then `Refresh now` and the feed switch. The line serves as 08's "last refresh". The `N unpriced` part arrives with unpriced surfacing in 5.2. Paper's row 2 points at a "Dashboard → Pricing" page, which 01 and 08 do not have; the overrides table sits in Sources as 08 says, under Paper's title `Your overrides win over the feed`. `Stale after` (09 `tb.price.staleAfterDays`) is a stepper in this group. `Reset to feed` removes every override after a confirmation; `−` removes the selected one. `tb.price.feedURL` is a text field in Advanced (09: "editable in Advanced only"), committed on Return; its `SettingSpec.tab` moves to `.advanced`.
- **Sources strip chip:** `Prices · <MMM d of the last successful check> · ok|stale`, `stale` in `HealthWatch`, after the job columns on every account page.
Blocking: no

## Q-039 Process: UI runs killed by macOS's low-disk cache purge            (2026-11-13)
Context: Stage 5.1 verify runs 2–4 and 8, and a full UI run on `main`, failed with `Test crashed with signal kill` at random clicks, with no crash report (`docs/postmortems/stage-5.1.md`, item 6). The session log archive inside each failed `.xcresult` names the cause: launchd logs the runner's exit as `OS_REASON_RUNNINGBOARD code:0xBADDD15C explanation:CacheDeleteAppContainerCaches`. The disk had 6.3 GiB free, so macOS's `deleted` daemon terminated the runner to purge its container caches. It was not the app, the tests, or the crowded menu bar (an earlier guess).
Options and choices:
- **Preflight:** `scripts/run.sh uitest` refuses to start below `TB_UI_MIN_FREE_GB` free (default 20) and exits 4 with the reason, because a UI run on a nearly full disk wastes ~35 min.
- **Diagnosis:** `scripts/ui-kill-reason.sh [<xcresult>]` prints each system termination of the runner, with its time, code and explanation, and calls out `CacheDelete` as low disk. `scripts/wait.sh` runs it after a failed `uitest` whose log has `Test crashed with signal kill`.
- Not chosen: turning off XCTest's screen recording to save disk. The recordings are what showed the overlapping windows, and the purge is driven by total free space, not by this run alone.
Blocking: no

## Q-040 Stage 5.2: cost-estimation and spend rules the docs leave open            (2026-11-15)
Context: 14 § Stage 5.2; `Pricing/{CostEstimator,PriceBook}.swift`, `Scheduling/Poller.swift`, `Ledger/Spend.swift`, `Store/{Observation,Repository+Usage}.swift`, `Dashboard/{NumbersStrip,OverviewView}.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Where rows are priced:** in the `Poller`, just before `writeUsagePage`, through `PriceBook.price` (the GRDB write closure is synchronous and cannot await the actor). 14's `upsertUsageBuckets` is the existing `writeUsagePage`. A poller without a price book writes every row unpriced (05: without prices every model is unpriced), so `est_cost_cents IS NULL AND unpriced = 0` never happens.
- **Arithmetic:** rates are picodollars per token (Q-038). Every term is summed in `Int128` over the common denominator 20 (1.25 = 25/20, 2.0 = 40/20, 0.1 = 2/20), then rounded half-up to cents once. Products and sums saturate instead of trapping (R5); the result clamps to `Int64`.
- **Fallback logging:** `price.fallback_multiplier` only for a class with tokens (otherwise every OpenAI bucket would log a missing cache-write rate), once per model and field per UTC day. Tiers: `priority`/`batch` are priced at the standard rate and logged once per model per day as `price.fallback_multiplier {field: service_tier, tier_priced_as_standard: true}` (07 updated); there is no separate event.
- **Reprice:** every `usage_bucket` row of each account with `bucket_start` within the last 90 days, whatever its source, in one transaction per account; only changed rows are written; `price.repriced {acct: provider, rows: changed, snapshot_version}`. Triggers: a new feed snapshot and every override change (set, `−`, `Reset to feed`), which closes PM-3.4-3 and PM-5.1-1.
- **`N unpriced`** in the Price book snapshot line: distinct models with an unpriced bucket in the last 90 days (from the database at launch and after a reprice; kept current as rows are priced). Shown only when N > 0. Not chosen: unpriced feed entries (the user cannot act on those).
- **Spend:** per UTC day, a closed day with a provider `total` cost row uses that cost (truth); the open day, and closed days without a cost row, use Σ `est_cost_cents` (estimate), like 05's `spend_since_anchor`. Usage sources: `provider` and `rollup`; `harness` only for an account without a usage API (05). Ranges are UTC days ending today: `Today` = today, `7 d` = today and the 6 days before (30/90 the same). The aggregates are observed for the last 91 days.
- **`≈` on spend:** a spend figure that includes any estimated day is shown `≈ $X`, without `±`, because 05 defines a band only for remaining; provider-cost-only figures have no `≈`. `Unpriced in range` is always `≈ $X`.
- **`unpriced_cents`:** the median of the window's priced models' input rates (for an even count, the mean of the two middle rates, rounded down). With unpriced tokens but no priced model in the window, the cell still shows, with `—`. The cell appears when the range has unpriced tokens (08: "shown only if > 0").
- **Before the first poll** the spend cells read `No data yet`; after a usage or cost poll they show the figure, `$0.00` included.
- **Overview subline:** `Total spend <range> $X` (+ `+ N non-USD` when other currencies exist, 05 § Currency), under the title; 5.3 adds the headline above it.
- **Paper:** Paper Desktop was not running in this session, so the numbers strip and the subline follow 08's copy only; reconciliation is 11.3's.
- **Known race:** a poll that priced its rows just before an override change can write them just after the reprice; the next reprice or the next poll of that hour corrects them. Accepted (no lock between the poller and the price book).
Blocking: no

## Q-041 Process: phase 5 UI tests run once, at its end            (2026-11-15)
Context: the owner's instruction of 2026-11-15: "complete all stages in phase 5, then at the end run UI tests".
Options: A) every 5.x verify runs UI tests (Q-031: a branch that changes app code turns them on); B) 5.2–5.4 verify with `TB_UI_TESTS=0`, and the 5.5 verify, which closes the phase, runs the full UI suite.
Chosen for now: B — the owner asked for it; it overrides Q-031 for 5.2–5.4 only. So a UI-test compile break does not surface only at the end, each stage builds the UI-test target with the new `scripts/run.sh build-uitest` (`xcodebuild build-for-testing`), and the stage scripts check that it built. A UI failure found in 5.5 is fixed on the 5.5 branch and named in its postmortem.
Blocking: no

## Q-042 Stage 5.3: ledger, runway and band rules the docs leave open            (2026-11-15)
Context: 14 § Stage 5.3; `Ledger/{Spend,Burn,Remaining,EstimateBand,Runway,BandEvaluator}.swift`, `Ledger/AccountSummaryBuilder.swift`, `Presentation/AccountPresentation.swift`, `scripts/check-traceability.sh`, the popover, Overview, account page and Alerts views.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Per-day spend everywhere** (PM-5.2-1): `burn_7d`, `burn_today` and `spend_since_anchor` use `Spend.daily` (provider cost for closed days with a cost row, else the estimate). `burn_7d` = Σ of the 7 closed UTC days before today ÷ 7, half-up; "days with data" are days with a cost row or a usage row. `burn_today` uses the open day's estimate, half-up.
- **`spend_since_anchor`:** days after the anchor's UTC day by the daily rule, plus Σ `est_cost_cents` of that day's buckets starting at or after the anchor (an hourly bucket that started before the anchor is not counted). The observed aggregates reach back to the oldest current anchor when it is older than 91 days.
- **Remaining:** the latest anchor (`ts`, then id); top-ups strictly after it; `reconcile`, `note` and `auto_zero` rows do not change the amount. No V1 code path creates a `reconcile` row (05 has no formula for one), so `ledger.reconcile` has no producer yet; it stays in 07.
- **`M`:** each term rounds up to a cent (drift = ⌈3 % of spend⌉, unreported = ⌈burn_7d × usageLag s / 86400⌉, unpriced = `unpriced_cents` over the anchor's days to today), and `M` = ⌈sum × (2 + ⌊age / anchor_age_days⌋) / 2⌉, so the band never understates. A direct balance has `M = 0`.
- **Bands at or below zero:** 05's `M ≥ remaining → unknown` applies only while remaining is positive. Otherwise 08's "negative remaining … band critical" could never happen. At or below zero: V1 holds (`remaining ≥ −burn_7d`) → `critical` (runway 0); V1 broken → `unknown`, and the account page asks for a new anchor (`Spend has passed the anchor by more than a day. Set a new anchor.`, authored copy). V1 is not logged on every evaluation: the band change records it.
- **Auto-reload:** with it on and `remaining ≤ below`, the band is `watch` whatever the runway, and the runway reads `reloads at $X` (X = the threshold). The toggle needs a threshold. `Adds` is stored, not used in the math (09).
- **Band recording:** a Core `BandRecorder` actor writes `band_state` (band, `since`, `inputs_json` in one `INSERT OR REPLACE`, V6) only when the band changes, then logs `ui.band_change`. An account's first evaluation inserts its row without a log line. A failed write logs `ui.error {view: band}` and is retried at the next evaluation. `inputs_json` and the log carry remaining, burn_7d, burn_today, runway_min (s), floor and estimate_band. The log adds `trigger`: `data` (database change), `settings` (Alerts thresholds, price book), `clock` (time passing, Low Power, stale timer), or `launch` (the first evaluation in a process that differs from the stored row).
- **E2E-9 join:** only `data` changes are joined. A `poll.ok` up to 2 s **after** the change also counts, because a poll commits its rows before it logs `poll.ok`, and the observation can re-evaluate in between.
- **Before the first poll:** an anchored account shows `No data yet` and band `unknown` even with an anchor (no spend data yet).
- **Cards (08, 09):** row 2 is the pinned metric; when it has no value (Day-1 runway), the next metric with a value takes row 2, so Day-1 shows `≈ $100 ± 0` with `Collecting…` in row 3. A spend-only card shows today's spend in row 2 and `today $X · 30 d $Y` in row 3. Remaining is `≈ $N ± M` in one text.
- **Banner:** the first `critical`, else the first `low`, else the first anchored account without an anchor, in card order. The text is `Label: ~1 d left` or `Label: set an anchor to see runway`, cut to 60 characters with `…` in the label.
- **Overview:** the headline names the shortest runway among accounts not `unknown`. `Total remaining` sums USD remaining (negatives as 0) and their `M`. The runway board's `Set anchor…` opens the sheet in place.
- **Sheets:** the amount is required and ≥ 0. The date cannot be in the future. The note is trimmed and cut to 140 characters. A failed save shows `TokenBe could not save this entry. Try again.` and logs `ui.error`. The ledger list deletes with a trash button or ⌫; `deleteUserLedgerEvent` deletes only `source = 'user'` rows, in SQL.
- **Alerts tab:** steppers within 09's ranges (the dollar floor in $1 steps, shown in dollars); `Settings` repairs `critical < low < watch`. The tab sits between Sources and Privacy, in 08's order.
- **Anchor-age nudge:** `The anchor is N days old. Set a new one to tighten the estimate.` with `Set anchor…`, when the anchor is older than `tb.alerts.anchorAgeDays` (authored copy).
- **Paper:** Paper Desktop was not running, so the new views follow 08's text; 11.3 reconciles.
Blocking: no

## Q-043 Stage 5.4: notification rules the docs leave open            (2026-11-15)
Context: 14 § Stage 5.4; `TokenBeCore/{Notifications/Notifier,Ledger/AlertPolicy}.swift`, `TokenBeApp/Notifications/*.swift`, `SettingsUI/AlertsTab.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Where the seam lives:** 14 § 0.3 placed `Notifier` in the app. E2E-4 asks for `RecordingNotifier` in a Core test, which cannot import the app. A) a second protocol in Core; B) move `Notifier` to Core. **B**: one protocol, as 0.3 requires (0.3 updated). `UNNotifier` stays in the app.
- **UI tests:** under a DEBUG `TOKENBE_TEST_ROOT` the app uses a `FileNotifier` that appends JSON lines to `<root>/notifications.ndjson` and grants authorization, like `FileKeyStore` (Q-030). UI runs never show a system prompt or a real notification.
- **What counts as a transition into low/critical:** the band change `BandRecorder` logged in this evaluation, when it is still the account's band. Into `low` only from `healthy`/`watch`/`unknown`; `critical` → `low` is a better band (08: no notification). A `launch` change counts like any other (the band really changed while TokenBe was closed); restoring the same band is no change.
- **`unknown` > 24 h:** an anchored account with no anchor whose `band_state.since` (band `unknown`) is more than 24 h old. **`stale` > 6 h:** stale, and the last success of any job more than 6 h ago.
- **Dedupe:** one per account per kind (low, critical, unknown, stale) per 24 h, in memory (a relaunch may repeat one).
- **Quiet hours:** local time; `start > end` wraps past midnight; equal times mean no quiet hours. Notices are held, still deduped, and sent at the first evaluation after quiet hours end, logged `suppressed_by_quiet_hours: true`.
- **Snooze:** `Snooze 24 h` sets `tb.alerts.snoozedUntil.<provider>` to now + 24 h. A snoozed provider gets no notice of any kind; nothing is held for it.
- **Authorization** is asked at the first notice, or at `Send test notification`. Denied → `ui.notification_denied` once per process, nothing is sent, and the Alerts tab shows `Notifications are off in System Settings` with `Open System Settings` (O-11), which opens the Notifications pane.
- **Copy:** 08's runway body (`OpenAI: ~1 d of runway left (≈ $9 ± 2).`; without a remaining amount, the parenthesis is left out). Authored: the title `TokenBe`; `OpenAI: set an anchor to see runway.`; `OpenAI: no fresh data for over 6 h.`; the test body `Notifications from TokenBe are on.`; the toggle labels; `Sent` / `Not sent: notifications are off`.
- **Quiet-hours times:** time pickers that write 09's `HH:mm` strings. The 01 S11 "optional Shortcut" is not built: no doc defines it, and R9 forbids adding controls 08/09 do not list.
Blocking: no

## Q-044 Stage 5.5: glyph and menu-bar metric rules the docs leave open            (2026-11-15)
Context: 14 § Stage 5.5; `Model/GlyphState.swift`, `TokenBeApp.swift`, `Startup.swift` (step 8).
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Step 8:** a startup step `glyph` after `daily activity` reads `band_state` into the environment. Until the accounts are observed, the glyph uses those bands. Afterwards, an account with no poll yet uses its stored band, and a polled one its computed band.
- **Metric text:** `minRunway` is the shortest `runway_min` among accounts not `unknown`, in 05's rule without spaces or `~` (`<1h`, `30h`, `12d`, `>60d`). `minRemaining` is the lowest remaining (negative as 0) in that account's currency. `todaySpend` is today's spend summed over USD accounts (05 § Currency), without `≈` (the menu bar has no room; the popover keeps it). Nothing known yet → no text. Width: `.frame(maxWidth: 64)`, one line.
- **UI test:** the metric is set with a launch argument (`-tb.menubar.metric`), so the shared UI-test settings suite is not changed (PM-4.2-5).
- **Accessibility:** a `MenuBarExtra` status item exposes only the glyph image's label, not the text beside it, so the glyph's label carries the metric: `TokenBe, 12d`. VoiceOver reads it, and the UI test asserts it.
Blocking: no

## Q-045 Stage 6.1: DeepSeek and direct-balance rules the docs leave open            (2026-11-15)
Context: 14 § Stage 6.1; `Providers/DeepSeek/*`, `Model/Money.swift` (`MinorUnits`), `Ledger/{Remaining,BandEvaluator}.swift`, `Scheduling/Poller.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **File names:** 14 named `Providers/DeepSeek/{DTOs,Probe,Client}.swift`, but SwiftPM refuses two files with one name in a module (`OpenAI/Client.swift` exists). A) prefix the provider (`DeepSeekDTOs.swift`, …); B) rename OpenAI's. **A**: OpenAI's paths are pinned by earlier stage checks. 6.2 does the same (`XAI…`). 14 updated.
- **The 401 fixture:** 14 named it `auth.401`. The recorder and `FixtureTransport` name a case after its endpoint, so it is `balance.401.synthetic.json`. 14 and 11 updated.
- **Amount strings:** parsed by `MinorUnits.decimal`: an optional `-`, ASCII digits, an optional `.` with digits, nothing else, then `Decimal(string:locale: en_US_POSIX)`. Plain `Decimal(string:)` follows the locale's separator (the owner's uses a comma) and accepts a numeric prefix (`"12abc"` → 12). Cents are rounded half up once (`MinorUnits.cents`, which OpenAI's cost rows now use too). A malformed amount fails the poll as `decode(field: <amount key>)`.
- **`balance_infos` empty:** a decode failure (`poll.schema_drift`), not a successful poll that writes nothing, which would show an old balance beside fresh freshness.
- **Currencies:** the probe makes the first entry's currency the account's. If it is not one TokenBe can show (`USD`, `CNY`), the probe fails with the unexpected-response message. A poll stores every entry's currency as sent (uppercased; the column has no CHECK), so a new currency appearing later never breaks the job. A currency listed twice keeps its first entry (03's key is `account_id, ts, currency`).
- **Which snapshot is remaining:** 05 says "first currency entry". The entries of one reading share a `ts`, so the latest reading's snapshot **in the account's currency** is used, not the order of the rows. If the latest reading has no entry in that currency, remaining is unknown (nil), never an older reading's figure. The account's currency is not changed after onboarding.
- **Capabilities:** usage, cost, per-key and key names off; balance on; `direct`. `usageLag` = 300 s, 02's "seconds–minutes" at its upper end. It only labels the Lag badge, because a direct balance has no estimate band. `currencyHint` is USD; the probe's result names the real currency.
- **Key refused (401/403):** authored copy (02 gives none): `DeepSeek did not accept this API key. Check the key at platform.deepseek.com → API keys and paste it again.`
- **Unavailable (D-deepseek-unavailable):** `is_available` of the latest reading. `BandEvaluator` checks it before every other rule, auto-reload included, so `critical` shows even with no runway: DeepSeek has no burn until harness ingest (7.2). `band_state.inputs_json` and `ui.band_change` add `unavailable: 1` only then, so other changes log the same inputs as before (07 updated; 03's DDL comment on `inputs_json` is the migration's text verbatim, checked by 2.1, so it is not edited). The forced `critical` has no runway to quote, so the banner reads `DeepSeek: account unavailable` and the notification `DeepSeek: the provider reports the account unavailable.` (authored; 08 updated), not `< 1 h left`.
- **Before harness ingest:** a DeepSeek account shows its balance with `Collecting…` and band `unknown` until 7.2 gives it spend. No anchor UI appears for it: `needsAnchor` is anchored-only.
- **Q-029's interim rule** ("a balance-capable account fails as `providerRule(<p>_balance_not_stored)`") is resolved: the poller writes `balance_snapshot`. An adapter without a balance endpoint still answers its `<p>_no_balance_api` rule.
- **Process (Q-041 extended, the owner's choice of 2026-11-15):** phase 6 also runs its UI suite once, at its end (6.2). 6.1 compiles the UI tests.
Blocking: no

## Q-046 Stage 6.2: xAI rules the docs leave open            (2026-11-15)
Context: 14 § Stage 6.2; `Providers/XAI/*`, `Providers/BearerRequest.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **"Numeric" (D-xai-balance, 02):** `remaining_balance` decoded as a JSON number into `Decimal`. A string (`"42.50"`), a Bool, null or a missing key is "no usable balance": the probe passes as `anchored` with `balance = false` and logs `poll.provider_rule rule=xai_no_balance_field` (warn, job `probe`). A string is not parsed as a number, because 02's rule says "as a number".
- **Unit:** 02 says USD and gives no unit, so the number is read as dollars, cents rounded half up once (`MinorUnits.cents`). Swift's `JSONDecoder` builds a `Decimal` from the number's digits: `42.505` → 4251 cents, which `XAITests` pins. The recording (H3) confirms or corrects the unit. Until then xAI stays unverified.
- **A direct account that later loses the field:** the poll fails as `decode(field: "remaining_balance")` (schema drift). It never writes a zero, and it never switches the account to `anchored` on its own. The mode is the probe's (D-xai-balance); `Test` in the Accounts tab re-probes.
- **Snapshot:** one USD row; `granted_cents`, `topped_up_cents` and `is_available` are NULL. `total_granted` and `spent_balance` are DeepSeek-unlike fields with no column, so they are not stored.
- **Capabilities:** usage, cost, per-key and key names off; `usageLag` 60 s (02's "seconds"); USD. For an anchored xAI account, spend comes only from harness reports (7.2), so it stays spend-only (`no runway until anchored`) and then `Collecting…` until harness data arrives.
- **Key refused (401/403):** authored copy, like DeepSeek's (Q-045): `xAI did not accept this API key. Check the key at console.x.ai → API Keys and paste it again.`
- **Shared request:** DeepSeek and xAI each call one Bearer-authenticated endpoint, so both use `BearerRequest.get` rather than two copies.
- **Step 3 (H3):** the owner has an xAI key and runs the recorder (open gate). When it is recorded, the PR that consumes H3 updates `13 § D-xai-balance` with the recorded shape and `Verified += .xai`. This is not "resolved-by-scope".
Blocking: no

## Q-047 Process: UI tests run only for the suites that cover changed code            (2026-11-15)
Context: the owner's request of 2026-11-15 ("run UI tests only for suites covering changed/added code", confirmed "yes, do it that way from phase 7"); `scripts/{verify-stage,run,ui-select}.sh`, `Tests/TokenBeUITests/*.swift`.
Options: A) keep Q-031 (any app change runs every suite) and Q-041 (phases 5–6: one full run at the phase end); B) each suite declares the paths it covers and verify runs the suites the branch touched.
Chosen for now: B — the owner asked for it. It supersedes Q-031 and Q-041 from phase 7 on:
- Every suite has `// ui-covers:` lines: repo-relative path prefixes (app or Core), or `always`. `scripts/ui-select.sh` (`--explain` says why) selects a suite when the branch (commits since main, uncommitted edits, untracked files) changes one of its paths or the suite's own file.
- `LaunchSmokeTests` and `PopoverEmptyStateUITests` always run. A change to a shared file runs every suite: the owner's list (`AppModel`, `Startup`, `AppEnvironment`, `UITestSupport`) plus the files every suite equally depends on (`TokenBeApp.swift`, the scene root; Core's `Store/Observation.swift`, the UI's only data feed; `TokenBe.xcodeproj/`, `Config/`).
- UI tests stay off for a branch that changes no `Sources/`, UI-test, project or `Config/` file. A phase-closing stage no longer forces the full suite.
- `TB_UI_TESTS=0` turns UI tests off; `TB_UI_TESTS=1` runs every suite. The full suite runs once more before 11.5 (14 § 11.5).
- A `ui_check` reads the suite its command names (`Test Suite 'X'`, `TokenBeUITests.X`) and prints `skip` when that suite was not selected. Checks that read what a suite leaves behind name it with `ui_check_for <Suite>`: 1.3's settings values (`SettingsGeneralUITests`) and 4.1's 190 s cadence run (`RefreshPauseUITests`, whose paths include `Scheduling/`).
- 7.1's stage script checks that every suite declares its paths and that every declared path exists.
- **Known gap:** `Strings.swift` is in no suite's paths (nearly every UI stage edits it, and listing it would run everything again). So a copy-only branch selects only the smoke suites, and the copy the other suites assert goes unchecked. 11.3 (strings reconciliation) verifies with `TB_UI_TESTS=1`.
Blocking: no

## Q-048 Stage 7.1: app-attribution rules the docs leave open            (2026-11-15)
Context: 14 § Stage 7.1; `Ledger/Attribution.swift`, `Store/Repository+Apps.swift`, `Dashboard/{ByAppTable,AppsThisPeriod,AppsPage}.swift`, `SettingsUI/BoundAppPicker.swift`, `Popover/AccountCardView.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Which day rule:** each UTC day's spend is `Spend.daily`'s (the provider's cost on a closed day with a cost row, else the estimate), so the By-app `Total` always equals the numbers strip's `Spend in range`. Per day: a closed day with the provider's `api_key_id` cost rows uses them; a closed day with only the total splits it by the keys' estimates (by tokens when no key has one); the open day and days without cost rows use each key's estimate. Whatever the per-key figures leave of the day (rounding, the cost of results without a key) goes to the day's largest key; ties go to the smallest key id, so the result never depends on row order.
- **Usage without a key** (`provider_key_id = ''`) is the `Unassigned` row (03's V4 sentinel), with no `Name…`: there is no key to bind. A day with spend but no usage rows at all goes there too.
- **Unbound keys:** 08 shows `(unnamed key …a9f2)`; 01 A2 asks for "human key names". 01 wins (R1): an unbound key shows the provider's key name when it has one, else `(unnamed key …a9f2)` (`…—` without a hint). A bound key shows its app's display name. `Name…` suggests the key's name. 08 updated.
- **One row per key**, not per app: the table has a Key column (08), and two keys bound to one app are two rows. Overview `Apps this period` sums an app's rows across accounts, per currency (05: never across currencies); an unbound key is its own entry. Its rows are not buttons until 7.3 adds the filter (D6).
- **Share:** whole percent, half up; the shares need not add to 100.
- **Popover row 4:** shown only when an app spent something today. Up to 3 entries by today's spend; with more than 3, two and `other` (the sum of the rest), as 08's example `… · other $0.10` reads. Amounts use the card's spend format (`≈` for estimates, R9). Collapsed it reads `Apps`; the chevron button's accessibility label is the row's text (VoiceOver) or `Show apps`.
- **Slug (O-16):** characters outside 06's `[a-z0-9._-]` become `-`, so `Čitač` → `ita` (diacritics are not folded: O-16 is literal); the name starts with `[a-z0-9]` (06's regex) and never ends in `-`; nothing left → `app`; `-2`, `-3` cut the base to stay within 64. The `unassigned` sentinel's name counts as taken. An empty display name defaults to the name (03).
- **The sentinel** is not offered in `Bound app`, not listed on the Apps page, and cannot be renamed (`upsertApp(id:)` → not found).
- **Apps page:** each app's display name (committed on Return or when the field loses focus; an empty name reverts), its name as `Harness tag`, and the keys bound to it (`OpenAI …a1b2`). Empty: `No apps yet` / `Name a key in an account's By app table, or bind it in Settings → Accounts → Keys & apps.` (authored).
- **Authored copy:** column titles `App · Key · Requests · Tokens · Spend · Share`, `Total`, `Bound app`, `—` (no app), `App name`, `Create`, `Harness tag`, `Show apps` / `Hide apps`, `other`, `Apps`.
- **Prompt:** `New app…` and `Name…` open one `New app…` alert with an `App name` field; `Create` makes the app and binds the key in one transaction (R7).
- **The Sources strip** (4.2) was an `HStack` whose minimum width (~1 100 pt for OpenAI's four sources and the price chip) pushed the account page wider than the Dashboard's 920 pt window, so the sidebar was drawn outside the window and could not be clicked. Found by `AppsBindingUITests`; the strip's columns now wrap (an adaptive grid, 200 pt minimum).
- **`Strings.swift` file length:** R9 keeps all copy in one file, which passed SwiftLint's 400 lines here; the file disables `file_length` with that reason, rather than splitting the copy.
Blocking: no

## Q-049 Stage 7.2: harness-ingest rules the docs leave open            (2026-11-15)
Context: 14 § Stage 7.2; `Ingest/*`, `Normalize/HarnessNormalizer.swift`, `Store/Repository+Ingest.swift`, `Ledger/Attribution+Harness.swift`, `Ledger/Spend.swift`, `SettingsUI/HarnessReportsSection.swift`, `Startup.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **FSEvents and R6:** FSEvents delivers on a dispatch queue or a run loop, and the run-loop call is deprecated (CI builds with warnings as errors). The stream uses `DispatchQueue.main`; its C callback only yields the paths into an `AsyncStream`, and the actor does the work. No app logic runs on a dispatch queue, which is what 04 and R6 forbid. Flags: 06's `FileEvents | UseCFTypes | NoDefer` (04 omitted `NoDefer`; 04 updated).
- **Polling:** 04 lists "polling the folder" as a Don't; 06 and 14 make a 30 s poll the fallback when FSEvents cannot start. Both hold: polling is never the primary watch. 04 updated. A watch event (FSEvents or poll) rescans the folder; unchanged files cost one `stat`.
- **Where the folder is:** in the support folder the database uses (startup's data root), so UI tests under `TOKENBE_TEST_ROOT` never touch the owner's `ingest/` (D10). In normal runs that is 09's `tb.ingest.folderPath`; Settings shows the folder in use. `ingest.folder_recreated` is logged only when `tokenbe.sqlite` existed before the launch.
- **Field failures 07 names no event for** (`ts`, `request_id`, `model`, `usage`, `status`, a non-string `key_hint`): rejected and logged `ingest.bad_json` with `field`. Only bad JSON or `v != 1` on a file's first non-empty line rejects the whole file (06 § Tailing 6), and only when the file is read from offset 0.
- **`provider` case:** exactly one of the five lowercase names (`DeepSeek` is unknown). `app` is lowercased before the regex (06).
- **`usage_json`:** the usage object re-serialized with sorted keys: its content is the provider's, its byte layout is not. "Same request id, different usage" compares these strings.
- **`source_line`:** 1-based among the file's non-empty lines, resumed from `lines_ok + lines_bad + lines_dup`.
- **03's names win** over 06's prose: counters are `lines_ok/lines_bad/lines_dup`; `status` is 1/0; a conflict counts as a duplicate (`lines_dup`). A rejected file counts 1 in `lines_bad`.
- **Normalizers:** 05 has no per-response OpenRouter row; OpenRouter's usage is OpenAI's chat shape, so it uses that row (05 updated). OpenAI's chat and responses shapes are told apart by `prompt_tokens` vs `input_tokens`. A JSON Boolean is not a count. One line is one request; an `error` line without usable usage still adds a request to its bucket (06 `status`).
- **Buckets:** a harness bucket's classes are summed and the bucket priced as a whole (as `repriceUsage` prices it), not per-line cents added, so a later reprice gives the same figure. A line's own `est_cost_cents` (price book, or OpenRouter's `cost_cents`) is the weight for splits and harness rows. OpenRouter buckets are priced from the book like any other (a reprice could not keep `cost_cents`); OpenRouter is gated until phase 10.
- **Clock and age:** `ts` > now + 5 min → `future_ts = 1`; older than `tb.retention.hourlyDays` → stored without a bucket (`ingest.too_old`).
- **Quiescence and moves:** after a read reaches EOF with no partial line, a 2 s check on the injected clock; `moveWhenDone` is read then. The stamp is UTC `YYYYMMDD-HHMMSS`; a name taken in `ingested/` gets `-2`, `-3`. The move is logged before the row's state is saved. A file with a known path, a new inode and state `ingested`/`rejected` is a new file (no `ingest.inode_changed`).
- **Errors:** a failed read, a failed batch write and a failed move log `ingest.read_failed` (07 has no other ingest error); the offset does not move, so the next change reads the same lines again and dedup keeps the count right. After 5 failed reads of one file it is marked `rejected` in place.
- **Burst:** every read commits in 1 000-line transactions; `ingest.burst` is logged once per read over 10 000 lines.
- **Harness spend and currency:** a harness estimate is priced in USD, and nothing is converted (05, R13). For an account without a usage API it counts as spend only when the account's currency is USD; a CN¥ DeepSeek account gets no burn from harness lines, and no drift check.
- **Inferred (D-deepseek-single-app):** closed days only, exactly one `harness_tag` app on the account, no top-up that day, no harness lines that day, and a balance that fell between the previous day's last snapshot and the day's last snapshot (in the account's currency). The delta is the day's spend (`Spend.daily`), so the By-app `Total` still equals the provider total (08) and DeepSeek's burn and runway include it (PM-6.1-3).
- **Split:** per day, a key's share is split among the harness apps whose lines resolved to that key that day (by their estimate, by tokens + lines when none has one); the key's other days stay `key` rows. A split row's tokens are its harness lines'.
- **Harness rows:** one row per app (and per kind: an app can have a `harness` and an `inferred` row). A day with harness spend but no attributable lines is the `Unassigned` row. Apps this period sums per app, kind and currency.
- **Drift (`ledger.harness_drift`):** a daily-activity step after the cost polls checks yesterday (UTC): for a USD direct account without a usage API, with harness lines and no top-up, `|Σ harness est − balance delta| > tb.alerts.driftThresholdPct % of the delta` logs `{acct, day, delta_cents = harness − delta}`. A day whose balance rose is skipped. The chip is 7.3's (04 updated).
- **xAI anchored:** has no polled job, so its summary treats harness lines as data (`hasHarness`): spend, burn and the card's rows appear once lines arrive (PM-6.2-2).
- **Startup:** step 5 `ingest` sits after `prices` (04 order); 2.1's and 5.1's checks and `StartupSequenceTests` list it.
- **Sources → Harness reports (authored copy):** `Folder`, `Reveal in Finder`, `Watch the folder`, `Move files to ingested/ when done`; the status `Watching · N files · last line 14 s ago` (08; `no lines yet`), `Off`, `The folder is not writable. Harness reports are off.` in `HealthLow`; `Today: N ok · N duplicate · N rejected` (local day, since launch); O-12's `N lines for providers you haven't added`; `<file> is over 512 MiB. Start a new file to rotate it.`; `Copy reporter snippet` → `Python` / `Node`, then `Python snippet copied`. The snippets are `docs/reporters/*` bundled as resources (byte-identical; 7.2's check compares them).
- **Account page:** an empty By-app table is the link `Report apps from your harness →` (08), which opens Settings → Sources. The Sources strip adds `Harness · N files · M lines today` for an account with harness lines.
- **A3 timing:** asserted inside E2E-3 (the first burst's rows within 5 s of the write), rather than by a separate stage-script launch.
- **E2E-3 fixture dates:** the UI test moves every `ts` to the last minutes when it appends, and Core tests inject `now`, so the fixtures never age past the hourly horizon. Move-when-done is off for E2E-3 by launch argument, or a 2 s pause would move the file between bursts. 06's DoD ("500 rows, 0 duplicates") and 11's E2E-3 ("488") describe different files; 06 now says one row per distinct request id.
Blocking: no

## Q-050 Stage 7.3: drilldown rules the docs leave open            (2026-11-16)
Context: 14 § Stage 7.3; `Dashboard/{DashboardView,OverviewView,AppsThisPeriod,AccountDetailView,ByAppTable,DriftChip}.swift`, `Ledger/{Attribution,Attribution+Harness,AccountSummaryBuilder}.swift`, `Model/Formatters.swift`.
Options and choices (each the least code; none adds a setting or a persisted value):
- **Which account a row opens:** an Apps-this-period entry is one app, kind and currency summed across accounts. Its click opens the account where the app (any kind) spent most in that currency over the range; a tie goes to the first account in sidebar order. Core computes it (`Attribution.drilldownAccount`, 04 I3).
- **What the filter matches:** the row's app (`AppRow.appKey`: the bound or harness app id, the `unassigned` sentinel included), else the unbound key's row. Every kind of the app shows (`key`, `≈ split`, `harness`, `inferred`), not only the clicked entry's kind.
- **Filter state:** Dashboard-window view state (`DashboardView`), tied to one account id, never persisted. The chip's ✕ clears it, and so does selecting any page other than that account. The numbers strip, sources strip and ledger are not filtered; only the By-app table is.
- **The filtered `Total`:** 08's `Total` must equal the provider total, which a filtered table cannot. The row is relabelled `App total` and sums the shown rows. An app with no rows in the range (after a range change) keeps the chip and reads `No spend for <app> in this range`; the "Report apps from your harness" link appears only for an account with no rows at all.
- **Drift chip:** beside the band pill, in `HealthWatch` (a data-quality hint, not a band). It names the newest closed day in the Dashboard range that drifted under Q-049's rule, `Harness drift · Nov 14 · −$4.02`, plus ` · N days` when more days in the range drifted. Its help gives both figures. The daily `ledger.harness_drift` checks only yesterday, so over a range the chip shows what those daily logs found. The threshold is `tb.alerts.driftThresholdPct`, passed in `SpendContext`, and changing it rebuilds the summaries. The name is `harnessDrift`, which keeps 8.1's `Drift`/`ledger.drift` free.
- **Unassigned:** keyless provider usage (7.1) and a harness day with spend but no lines (7.2, reachable once raw lines are purged, PM-7.2-1) are both the sentinel's rows. Both read `Unassigned` and have the element id `unassigned`, and both filter like any app. Apps this period keeps them as separate entries per kind (`key`, `harness`), like any other app's kinds.
- **Copy (authored; 08 gives none):** `App: <name>`, ✕ `Clear app filter`, `App total`, `No spend for <name> in this range`, `Harness drift · <MMM d> · ±$N[ · N days]`, and the help `On <day> harness lines add up to $X, but the balance fell by $Y. Lines may be missing, or a request was reported under another provider.` 08 updated.
Blocking: no

## Q-051 Stage 8.1: By-model table and drift rules the docs leave open            (2026-11-16)
Context: 14 § Stage 8.1; `Ledger/Drift.swift`, `Store/Observation.swift`, `Dashboard/{ByModelTable,AccountDetailView}.swift`, `DailyActivityRegistration.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Line item → model (05 "exact model name within the line item string"):** A) the text before the first comma equals the model; B) the longest usage-model name that occurs in the line item between boundaries (the string's ends or a character no model id uses: not a letter, digit, `-`, `_`, `.`, `:` or `/`). Chosen: B. It reads 05 literally, keeps `gpt-4o-mini, input` off `gpt-4o`, and still maps if the real format has no comma. The models are the account's usage models in the 91-day window. A line item that names none (`web search tool calls`) is left out of the table. The format comes from our synthetic fixture only (H2 open): PM-8.1-1 re-checks it against recorded line items.
- **Anthropic `description` rows:** no adapter yet (10.1), so `Drift` reads only `line_item` rows. 10.1 decides how a `description` row carries its model so `Drift` can map it (PM-8.1-2).
- **What each column covers:** Requests to Est. cost cover the whole range, today included, from the sources `Spend.counts` allows (provider and roll-up rows; harness rows only for a USD account without a usage API). Provider cost is the mapped line items of the range's closed days. Drift compares the estimate and the provider's cost over exactly the closed days that have a mapped row for the model (05), so a row's own Est. cost and Provider cost need not reproduce its drift. The Drift cell's help names the two figures it compares: `Over N closed days with a provider cost: estimate ≈ $X, provider $Y.`
- **Unpriced (A6):** a model with any unpriced bucket in the range has no estimate. Its Est. cost reads `unpriced` in `HealthWatch`, with the help `This model is not in the price book, so its usage is left out of spend and runway. Add a price in Settings → Sources → Price book.` It has no drift, even with a cost row, so missing prices never read as −100 % drift. Priced and unpriced buckets are summed apart in SQL, so the table never shows `≈ $0` for a model it cannot price.
- **Zero provider cost:** a mapped cost of 0 shows `$0` and Drift `—`. Nothing is divided by zero.
- **Flag:** `|est − provider| × 100 > tb.alerts.driftThresholdPct × provider`, in integers; exactly the threshold is not flagged. The cell shows a signed percent with one decimal (`+12.5 %`, U+2212 minus). A flagged cell is semibold in `HealthWatch`, with a warning icon, and its VoiceOver label says `Drift +12.5 %, above the 10 % threshold` (08 § Accessibility: colour is never the only carrier).
- **Order:** by estimate, largest first; unpriced models last; then by name.
- **Empty:** 08 gives the table no empty state, so the account page shows it only when the range has usage.
- **Header layout:** two-word column titles take two lines (`Cache` / `write`), so ten columns leave the model name room at 920 pt. The words are 08's, and VoiceOver reads them as one line.
- **`ledger.drift` (07: acct, model, drift_pct):** a daily-activity step `model drift`, after `harness drift`, checks yesterday (UTC) for each account and logs each flagged model at `warn`, with `drift_pct` in percent (one decimal). The table's figures are never logged: the summary is rebuilt on every database change. A `DailyOnce` logs each account, model and day once, also when `Run daily tasks now` repeats the step. Like `price.unpriced`, the once-per-day memory is per process, so a relaunch on the same day can log the model again. 04 updated.
- **E2E-8:** the UI test uses a fixture case, `openai/usage_completions=unpriced`, so the real pricing path stores `est_cost_cents NULL` and logs `price.unpriced` once. It then moves those rows to today, and adds yesterday's usage and line item by SQL, so the 7 d range shows them on any date.
Blocking: no

## Q-052 Stage 8.2: chart and cache savings rules the docs leave open            (2026-11-17)
Context: 14 § Stage 8.2; `Ledger/{SpendChart,CacheSavings,AccountSummaryBuilder}.swift`, `Pricing/CostEstimator.swift`, `Dashboard/{SpendByDayChart,CacheTile,OverviewView}.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Chart data:** each account's bars are its `Spend.daily` figures for the range's days, the same rule that sums to `rangeSpend`: truth on a closed day with a provider cost row, the estimate otherwise, and DeepSeek's inferred days (06) included. So each account's stack segments sum to its `Spend in range`, and `ChartDataTests` asserts it for every range. A day with $0 adds no segment.
- **Currency (05 § Currency):** a stacked money axis cannot add CN¥ to $, and nothing is converted. A) one chart per currency; B) USD accounts only, with a caption, like the Overview's `Total spend … + N non-USD`. Chosen: B. The caption reads `USD accounts only · N non-USD account(s) not shown` and counts only accounts with spend in the range.
- **Palette (O-3):** blue, purple, teal, orange, pink, indigo, mint, brown, by the account's place in the sidebar (`model.accounts`), repeating after the eighth. An account keeps its colour when another has no spend. A legend under the chart names the accounts that have bars.
- **Axes and tooltip:** x is the range's UTC days (`Nov 14`), at most 8 labels, ending on today. y is money in whole cents, so no money is a `Double` (lint `tokenbe_no_double_money`). Hovering a day draws a rule and lists that day's accounts, then `Total`, with the Overview's `≈` rule. VoiceOver reads each segment as `OpenAI, Nov 14` with its amount. Swift Charts does not expose an annotation's text, so the hovered day's rule carries the tooltip's total as its label (`Total, Nov 14, ≈ $3.20`). The tooltip fits inside the plot, so it never covers the y-axis labels. A category axis draws every day's mark whatever `values` it is given, so only the 8 chosen days get a label. A y tick between whole dollars keeps its cents (`$0.25`), so hidden cents never print `$0, $0, $1`.
- **Visible-only rendering (14):** the card builds the `Chart` only between `onAppear` and `onDisappear`, and keeps its height while off screen.
- **Cache savings formula:** what the cached tokens would cost as plain input minus what they cost, computed by `CostEstimator`'s own unrounded total. It is the same as 05's formula, with the same fallbacks: read 0.1 × input, 5 m write 1.25 ×, 1 h write the 5 m rate, then 2 ×. Picodollars are summed over the range and rounded once. Unpriced models are left out.
- **Sources (05):** Anthropic counts `source = 'provider'` buckets. DeepSeek and xAI count harness buckets, whose per-response fields carry cache counts. OpenAI reads `—` (`Not computed — OpenAI aggregate cache counts are unreliable`), even for harness rows, as 14 and D-openai-cache-savings-off say. OpenRouter reads `—`, because its harness lines carry a cost, not cache counts. An account with no rows of its source in the range reads `—` with its reason (`No usage in this range`, `Computed from harness reports; none in this range`); `$0` would claim a figure we do not have. Before the first poll, the figure is empty like every other figure (`No data yet`).
- **Dollars:** savings are price-book dollars whatever the account's currency, so a CN¥ DeepSeek account's savings are still `$`, and the headline sums every computed account.
- **Tile layout:** a headline `Saved $X via cache (net of writes)` (08's sentence, X summed over the accounts that have a figure), then one line per account with its amount or `—`, the reason in the help and the VoiceOver label. With no figure at all, the headline reads `Not computed for any account in this range`.
- **Negative savings:** writes that cost more than reads saved show a negative figure (`Saved −$3 …`, U+2212), not `—`. 05 says net of writes.
- **Order on the Overview:** 08's: headline, runway board, chart, Apps this period, cache tile. The chart sits above `Apps this period`, as 08 numbers them.
Blocking: no

## Q-053 Stage 8.3: CSV export rules the docs leave open            (2026-11-17)
Context: 14 § Stage 8.3, O-4; `Export/ViewCSVExporter.swift` (Core), `Dashboard/{ViewExport,DashboardView,RunwayBoard,ByAppTable,AppsPage}.swift`.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Which table each page exports:** the Overview's runway board, the board 08 calls a table. The chart, `Apps this period` and the cache tile are summaries of other tables. An account page shows By app, By model and the ledger. A) all three in one file; B) one file per table, chosen in the panel; C) By app. Chosen: C. It is the table A2 is about, and the one the Overview's drilldown (7.3) filters. RFC 4180 has no sections, so A would not be one CSV, and B adds a control. The Apps page exports its list: App (display name), Harness tag, Key (the bound keys).
- **Current state:** the account export respects the app filter: only the app's rows, footer `App total`. The By-app footer row is written, with empty cells where the screen has none. The Overview board keeps the screen's sort (runway ascending, `unknown` last).
- **Cell text:** each cell is the string the page prints, from the same function the view draws from (`RunwayBoard.cells`, `ByAppTable.cells` / `totalCells`, `AppsPage.keys`). The file cannot disagree with the screen: `≈`, `±`, currency symbols, the locale's separators and `Hide cents` all carry over. The machine-readable export is 9.2's `Export CSV (all tables)`. The By-app badge column has no title on screen; its CSV header is `Attribution`. The Tokens cell is the mini-bar's compact total (`1.2M`). The band dot is its word (`healthy`).
- **File:** UTF-8 without a BOM; every record, the header included, ends with CRLF; a field is quoted only when it holds a comma, a double quote, CR or LF, with quotes doubled. An empty table is its header. The write is atomic.
- **File name:** `TokenBe-<page>-<label>-<range>-<UTC date>.csv`, e.g. `TokenBe-DeepSeek-By-app-news-digest-7-d-2026-11-17.csv`. A label is user-typed, so `/`, `:`, `\`, control characters and spaces become `-`, runs of `-` collapse, and a leading or trailing `-` or `.` is trimmed.
- **Logging:** `db.export {kind: csv_view, path, rows}` at `info`, where `rows` counts table rows without the header and `path` is the chosen file's path, as `ingest.*` logs its paths. A failed write logs `ui.error` (`view export failed`) and shows an alert; it logs no `db.export`.
- **Panel:** an `NSSavePanel` sheet on the Dashboard window, `.csv` only, folders can be created. The app is not sandboxed, so no entitlement is needed.
- **UI test:** DrilldownUITests opens `Export…` on the filtered account page, checks the suggested name, and presses Cancel. A UI test never presses Save, which would write into the owner's folders. Core's `CSVExporterTests` covers the bytes and the log.
Blocking: no


## Q-054 Stage 8.4: accessibility rules the docs leave open            (2026-11-17)
Context: 14 § Stage 8.4, 08 § Accessibility; Core `Model/SpokenFormatters.swift` (`Spoken`), `Components/{AccessibilityOverrides,TableKeyboard}.swift`, the views that show a figure or a band.
Options and choices (each the least code; none adds a dependency, screen or setting):
- **Words.** 08 gives one sentence, `Remaining, approximately 42 dollars, plus or minus 3`. A) let VoiceOver read the screen's symbols (`≈` "almost equal to", `~12 d` "tilde 12 d", `CN¥` letter by letter); B) words built in Core from `Money`, the band and the runway seconds, never by rewriting display strings. Chosen: B. `≈` → `approximately`; `±` → `plus or minus` with no unit after the band (08's example); `$` → `dollar`/`dollars`; `CN¥` → `yuan`; `-` → `minus`; runway `< 1 h` / `N h` / `~N d` / `> 60 d` → `less than 1 hour` / `N hours` / `about N days` / `more than 60 days`; the second pace → `… at today's pace`; `—` → `none`; `7 d` → `7 days`. Digits and separators are the screen's (the locale's), so the figure heard is the figure seen.
- **One element, one rendering.** A probe showed that on macOS a `Text`'s `accessibilityLabel` replaces its accessibility value: VoiceOver and XCUITest see only the label. So each figure's `Text` carries `<title>, <words>` (`Spoken` + `Strings.spoken`), the numbers strip hides its caption, popover row 2 is titled although the screen shows no title, the runway board's cells carry their column titles, and the By-app, By-model, ledger and Apps-this-period amounts carry their words. The UI tests that read a figure now assert its words (AnchorRunway, DirectBalance, Onboarding, Drilldown).
- **Grid rows.** A `GridRow` passes its modifiers to every cell: the board's `.accessibilityElement(children: .combine)` never combined a row, and its identifier landed on each cell. The row id now sits on the name cell; every cell is its own element.
- **Band.** The band dot and the pill already said `Band: <word>`. The band-coloured Overview headline and the band-tinted banner now end with `band <word>`. The dot gets the image trait: the accessibility audit flagged a labelled `Circle` as "Unknown role".
- **Dynamic Type.** A probe measured the card figure at 26 pt both at `large` and at `xxLarge`: macOS text styles do not grow with `dynamicTypeSize`. A) leave 08's line unmet; B) the popover's cards scale their own point sizes (`ScaledFont`, iOS body ratios 14–23 pt over 17) under a cap of `xxLarge`. Chosen: B, about 30 lines; the card figure is Paper's 20 pt again (it measured 24 pt at the default size and 29 pt at `xxLarge`). The apps row may take two lines above the default size. The header, banner and footer keep system text styles. Whether macOS's own Text size setting reaches SwiftUI's `dynamicTypeSize` was not checked: the agent never changes the owner's system settings (owner checklist below).
- **Test overrides.** DEBUG only, under `TOKENBE_TEST_ROOT`: `TOKENBE_TEST_TEXT_SIZE=xxLarge` sets the popover's text size and `TOKENBE_TEST_REDUCE_MOTION=1` turns Reduce Motion on, like `TOKENBE_TEST_OFFLINE` (Q-036). They live in `AccessibilityOverrides.swift`, not in `Startup`, so no shared file changed.
- **Reduce Motion.** The refresh button pulses instead of spinning. The four `ProgressView` spinners (Settings loading, Sources `Run daily now`, Accounts `Test`, onboarding `Test`) become `BusyIndicator`: a spinner, or under Reduce Motion a pulsing dot labelled `In progress`. A symbol effect is not exposed to accessibility, so 8.4.sh checks the code.
- **Keyboard.** The grid tables (runway board, By app, By model): each row's first cell is focusable (Tab, a click), ↑/↓ move between rows, Esc leaves; macOS delivers Esc as the exit command, so `onExitCommand`, not `onKeyPress(.escape)`. ⏎ does nothing: no board or table row has an action in 08. The ledger is already a selectable `List` (⌫ deletes a user row); the Apps page is a `Form` of text fields.
- **Audit.** `xcrun accessibility-inspector` is not scriptable (14), but XCTest's `performAccessibilityAudit` works on macOS. AccessibilityUITests runs it on the Dashboard's Overview and on the popover at `xxLarge`. It fails on any issue except three classes that belong to system chrome, which it logs: an unlabelled container without an identifier (a `Group` drawn by `NavigationSplitView`, or the `MenuBarExtra` panel, an untitled `Dialog` the app cannot name), contrast on the sidebar's rows and the window title, and a contrast that "nearly passed" (system secondary text). One contrast failure is ours: the popover header's `Refreshed …`, Paper's secondary caption on the header material (the cards' same style "nearly passed"). Paper decides visuals (12 § R1), so the test tolerates it by name and 11.3 settles its colour against Paper (PM-8.4-2).
- **Owner checklist (open; not done by the agent, PM-8.4-1 → 11.3):**
  - [ ] VoiceOver (⌘F5) on the popover: each card reads its label, band, figure in words and freshness; ↑/↓ and ⏎ work.
  - [ ] VoiceOver on the Overview: headline with its band; the runway board cell by cell; the chart's days; Apps this period.
  - [ ] VoiceOver on an account page: numbers strip, By app, By model, ledger.
  - [ ] System Settings → Accessibility → Display → Text size, larger: does the popover grow? If not, macOS does not pass its setting to SwiftUI, and only the test override shows the scaled cards.
  - [ ] Reduce Motion on: the refresh button pulses, no spinner turns.
  - [ ] Accessibility Inspector's audit on the popover, the Dashboard and Settings: no issue beyond the three tolerated classes.
Blocking: no
- **Correction (2026-11-18, Stage 9.1).** The audit's contrast tolerance is wider than this entry says: AccessibilityUITests tolerates contrast on the sidebar's rows and on *any* element with an empty identifier, not only the window title. The code is unchanged; the test's comment now says so, and PM-8.4-2 (11.3) narrows the predicate to the window title.


## Q-055 Stage 9.1: retention roll-up rules the docs leave open            (2026-11-18)
Context: 14 § Stage 9.1, 03 § Retention tiers; `Store/Rollup.swift`, `Store/Observation.swift`, `Ledger/{Attribution,Attribution+Harness,Drift,CacheSavings}.swift`, `SettingsUI/AdvancedTab.swift`.
Options and choices (each the least code that keeps every total exact; none adds a dependency, screen, setting or migration):
- **Roll-up source of harness hours.** 03 says hourly rows become `1d` rows with `source='rollup'`. A) one `rollup` row from provider and harness hours together; B) provider hours → `rollup`, harness hours → `1d` rows that keep `harness`. Chosen: B. `Spend.counts` drops harness rows for an account with a usage API and for a non-USD account (05, Q-049). A merged row would count those harness hours once they are rolled up: a double count for OpenAI and a dollar estimate added to DeepSeek's CN¥ spend. 03's own `harness_event` row already speaks of "`1h`/`1d` buckets (source harness)". 03's table now says this.
- **Anchor day.** `spend_since_anchor` reads the anchor day's buckets that start at or after the anchor (05). A daily row starts at midnight, so rolling up that day would silently raise Remaining by the hours after the anchor. A) roll it up anyway; B) keep the hours of every day that holds one of the account's `anchor` events. Chosen: B: about 24 rows per model and key for each anchor. An anchor back-dated (Set anchor sheet) to a day that was already rolled up reads no remainder for that day; the hours are gone and can't be recovered. That costs at most one day's usage. It is accepted.
- **Mixed pricing in one day.** If some hours are priced and others unpriced (e.g. a model priced mid-day): `est_cost_cents = Σ` of the priced hours, `unpriced = 0`. When every hour is unpriced, `est_cost_cents` stays NULL and `unpriced = 1`. Σ cents (05: unpriced counts 0) and Σ tokens stay exact in every reader. The unpriced tokens of a mixed day stop being flagged. `provisional` and `fetched_at` take the maximum.
- **A late hour of a rolled day** (an hour that arrives after its day was rolled up) is added to the existing daily row. Upsert with addition, then delete the hours, in one transaction. Usage polls look back 48 h and ingest's `too_old` uses a later cut-off, so neither writes hours older than the horizon in practice.
- **Monthly tier.** Only whole months whose last day is more than 400 days back are rolled up. The `1mo` rows are recomputed from the daily rows on every run, and a row is written only when a sum changed. Recomputing keeps a second run a no-op even though the daily rows stay; adding to existing rows would grow them on every run. Every summary read of `usage_bucket` (Observation's usage, priced-model and anchor-day reads, `KeyUsageDay`, `ModelUsageDay`) skips `1mo`. Observation's window can reach back to an old anchor, and the monthly rows would otherwise count each day twice. `repriceUsage` and the unpriced-model list still read `1mo` rows: they only price rows and list models, so including them is harmless.
- **Balance thinning.** 03 keeps the first snapshot of each day. `BalanceDay` (06's balance deltas: inferred days and harness drift) reads each day's last snapshot, and with only the first kept every delta older than 7 days would shift by a day. Chosen: keep the first and the last snapshot per UTC day and currency. 03 now says so.
- **Purged harness lines (PM-7.2-1).** `harness_event` holds the app tag; the harness buckets do not. For days older than `tb.retention.rawHarnessDays`: a day that has harness buckets still counts as a day with reports, so it never becomes `inferred` (`withLines` reads both). An account with exactly one harness app gives the whole day to that app, the only tag its lines can have had. With several apps the day's split is gone and the row is Unassigned (`harness`). The drift chip (`ledger.harness_drift`, 7.3) has no lines for those days and shows none. Both defaults are 90 days, the longest Dashboard range, so nothing is lost unless the owner shortens a window.
- **Cut-offs and logging.** Every cut-off is the start of a UTC day (`today − N days`), so a day is never split. The purge runs only after both roll-ups succeeded: a failure throws, and the daily activity retries the step. Each tier logs one `db.rollup {tier, rows_in, rows_out, before}` record per run, summed over the accounts. The tiers are `hourly` (hours read, daily rows written), `monthly` (daily rows read, monthly rows written), `harness_event` (rows present, rows deleted) and `balance_snapshot` (rows past 7 d, rows deleted).
- **Dedup after the purge.** `harness_event` is ingest's dedup key (06). A line re-delivered after its event was purged is stored again. If it is still inside `tb.retention.hourlyDays`, its bucket is upserted a second time and counted twice. With the defaults (90 / 90), the purge cut-off is a day start no later than ingest's `too_old` cut-off, so such a line is `too_old` and touches no bucket. The double count needs both a raw window shorter than the hourly window and a line delivered again (a re-dropped file, or a reporter retry into a new file). Accepted: guarding against it would mean keeping a request-id index past the purge, which 03 does not have.
- **Controls.** Advanced → a section under the log rows with two steppers, `Hourly detail kept for` / `Raw harness events kept for` + `N days`, built like `Log retention` and bounded by 09's ranges. They write only the setting; ingest already follows `tb.retention.hourlyDays`, and the next daily run applies both.
Blocking: no
