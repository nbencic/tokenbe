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
- **Sheet copy.** 08 names the two buttons but not their results. Integrity check: title "Integrity check", then "Result: <ok or first line>", then on failure "A copy of the database was saved to <path>". If the check could not run: "Integrity check could not run" and the error. Backup: "Backup saved", "<size>, <date and time>", then the path. If it fails: "Backup failed" and the error. Every sheet has an `OK` button.
- **No confirm dialog.** Phase 1's postmortem called these "the first destructive controls". Neither one destroys user data: the backup replaces only the previous `.bak` through an atomic rename, and the integrity check only reads, plus a copy on failure. 08 lists a destructive confirm only for `Reset all settings…`, so none is added (R9). Both buttons are disabled while one is running.
- **Verify location.** 14's Verify line tested `~/Library/Application Support/TokenBe/tokenbe.sqlite.bak`, the owner's real folder. That contradicts D10 and Q-014, and would fail `real_support_unchanged`. The UI test asserts `.bak` inside its own `TOKENBE_TEST_ROOT`. `2.2.sh` checks that the last UI-test run wrote both `tb.db.*` keys to the UI-test suite, and that the owner's real folder is unchanged. 14 is reworded.
- **Remembered Settings tab.** The Settings window reopens on the tab last used in the UI-test suite. 2.2's test leaves General selected, and `SettingsGeneralUITests` selects General itself instead of assuming it.
Blocking: no
