# 13 — Decisions (closed) and open items with defaults

Closed decisions are final for V1. Reopening one requires a new entry below with `Supersedes: D-xxx` — never edit the original.

## Closed

| ID | Decision | Rationale | Date |
|---|---|---|---|
| D-direct-first | Measure usage from provider APIs; no proxy in the request path. Harness JSONL fills gaps. | Zero latency/availability risk to the user's own calls; a proxy would make TokenBe a single point of failure. | 2026-11-09 |
| D-no-balance-estimate | OpenAI and Anthropic have no balance endpoint → `anchored` mode with user-entered anchor, visible `≈ … ±`. Never present an estimate as a balance. | Verified 2026-11-09 against both API references; honesty of the number is the product. | 2026-11-09 |
| D-one-dep | GRDB is the only third-party dependency. | Review surface, supply chain, long-term maintainability for a one-person OSS project. | 2026-11-09 |
| D-grdb-version | Pin GRDB `exact:` to the latest 7.x at Milestone 1; record the version here. **Pinned: 7.12.0** (latest 7.x on 2026-11-09, Stage 0.1). | Reproducible builds. | 2026-11-09 |
| D-sandbox | App Sandbox OFF; Hardened Runtime ON; Developer ID + notarization. | Human-readable ingest path for harness reporters; no App Store distribution planned for V1. | 2026-11-09 |
| D-swift6 | Swift 6 language mode, strict concurrency complete, macOS 15 minimum. | Compiler-enforced data-race freedom; `MenuBarExtra(.window)` and Swift Charts maturity. | 2026-11-09 |
| D-no-sparkle | No in-app updater. Daily `GET` to GitHub releases API; install via Homebrew/dmg. | Removes a dependency + XPC helper; cask handles upgrades. | 2026-11-09 |
| D-fsevents-offsets | FSEvents directory stream + persisted byte offsets per file (same transaction as inserts). | Survives crash/kill; no double counting; one stream regardless of file count. | 2026-11-09 |
| D-two-pace-runway | Show `runway_7d` and `runway_today` side by side; band from the smaller. | Bursty harness usage makes a single average misleading. | 2026-11-09 |
| D-bands | healthy > 14 d, watch 7–14 d, low 2–7 d, critical < 2 d or < $5; `unknown` when no anchor or `M ≥ remaining`; stale is an overlay not a band. | Critique: colors must mean one thing. | 2026-11-09 |
| D-green-healthy-only | Green is used only for `healthy`. Accent blue for interactive controls incl. toggles. | macOS convention; avoids false reassurance. | 2026-11-09 |
| D-no-sparklines | No sparklines in popover cards in V1. | They repeated information and cost layout; dashboard has the chart. | 2026-11-09 |
| D-deepseek-harness | DeepSeek per-app attribution only via harness JSONL; balance from `/user/balance`. | DeepSeek exposes no usage/per-key API (verified 2026-11-09). | 2026-11-09 |
| D-deepseek-single-app | ON: when a DeepSeek account has exactly one harness app and no topup that day, attribute the day's balance delta to it with badge `inferred` if harness lines are missing. | Common single-purpose-key case; badge keeps honesty. | 2026-11-09 |
| D-anthropic-per-key-est | ON: show per-key $ on Anthropic as `≈` from usage × price book (cost_report is not per key). | Users need per-app $; estimate is labeled. | 2026-11-09 |
| D-xai-balance | xAI: if `GET /v1/api-key` returns a usable `remaining_balance`, treat as `direct`; otherwise `anchored`. Field is `[expected]` until Milestone 0 fixture confirms. | Secondary source only; do not trust until recorded. | 2026-11-09 |
| D-no-currency-conversion | No FX conversion; each account in its native currency; cross-account totals sum USD only and annotate others. | Avoids a rate feed dependency and false precision. | 2026-11-09 |
| D-provider-truth | Provider totals are truth; harness rows split or substitute, never add. | Prevents double counting across sources. | 2026-11-09 |
| D-integer-money | All money in `Int64` cents; `Decimal` only for display. | Exactness; summing cents over years must be stable. | 2026-11-09 |
| D-retention-tiers | Hourly 90 d → daily forever → monthly roll-up; harness raw events 90 d. | <250 MB after 5 years with real headroom. | 2026-11-09 |
| D-log-ndjson | NDJSON file sink + os.Logger, 14-day retention, 50 MiB rotation, mandatory event table. | Debuggability requirement from the owner: every error, edge case, race logged. | 2026-11-09 |
| D-no-telemetry | No outbound traffic other than provider APIs, LiteLLM feed, GitHub releases. | Trust; the app sees billing data. | 2026-11-09 |
| D-keychain-only | Keys in Keychain `WhenUnlockedThisDeviceOnly`, non-synchronizable. The login keychain, not the data-protection keychain (owner, 2026-11-10, Q-027). | Device-bound secrets; no iCloud spread. | 2026-11-09 |
| D-one-key-per-provider | V1: one account per provider (UNIQUE provider). Multiple orgs per provider is V2. | Scope. | 2026-11-09 |
| D-inter-standin | Paper uses Inter because SF Pro is not installed on the design machine; app uses system SF via `.system(design:)`. | Fidelity in app, pragmatism in design file. | 2026-11-09 |
| D-paper-nodes | Paper node ids listed in 08 are the reference for reconciliation at Milestone 4; this doc set wins on conflict. | Single source of truth. | 2026-11-09 |
| D-hotkey-carbon | Global shortcut via Carbon `RegisterEventHotKey`. | No Accessibility permission prompt. | 2026-11-09 |
| D-utc-days | All day math in UTC; labels in local time. | Provider buckets are UTC. | 2026-11-09 |
| D-openai-cache-savings-off | Cache savings tile not computed for OpenAI from aggregate usage API. | Aggregate cached counts have known inconsistencies (02 quirk). | 2026-11-09 |
| D-executor | The plan in `14` is executed by Claude Code on the owner's Mac (Xcode ≥ 16.2); the agent builds/tests/lints itself. | Owner's choice; enables machine-checked stage DoD. | 2026-11-09 |
| D-xcodeproj | `TokenBe.xcodeproj` is created once in the Xcode GUI (14 § H1) with Xcode 16 file-system-synchronized groups; the agent never edits `project.pbxproj`. | Long-term maintainability: adding files needs no project edits; no XcodeGen/Tuist toolchain dependency; GUI-created project stays compatible with Xcode upgrades. | 2026-11-09 |
| D-xcconfig | Every build setting lives in `Config/{Base,Debug,Release}.xcconfig`; `Info.plist` is generated from `INFOPLIST_KEY_*`. | Reviewable text diffs; pbxproj stays tiny. | 2026-11-09 |
| D-verified-providers | The Release build offers only providers whose live fixtures were recorded (`Tests/Fixtures/providers/<p>/RECORDED` ↔ `Providers/Verified.swift`). Initial set: openai, deepseek, xai (as keys allow). Anthropic and OpenRouter are compiled, tested on synthetic fixtures, hidden in Release. | Owner has no Anthropic organization and no OpenRouter management key; shipping untested adapters violates R13. Contributors can verify (14 § 10.3). | 2026-11-09 |
| D-synthetic-fixtures | `*.synthetic.json` fixtures authored strictly from `02` are allowed for development and for unrecordable error cases; they never satisfy `RECORDED`. | Non-blocking development while H2/H3 gates are open. | 2026-11-09 |
| D-no-pixel-snapshots | No pixel snapshot tests; UI state is tested with XCUITest on accessibility identifiers. | A snapshot library would be a dependency; pixel tests are machine-dependent. | 2026-11-09 |
| D-run-wrapper | Every build/test/perf command runs through `scripts/run.sh` (background, log file, timeout) + `scripts/wait.sh` (bounded polling). | Owner rule: never leave a long foreground process holding the shell. | 2026-11-09 |
| D-composition-root | Explicit DI: `AppEnvironment` (app) / `TestEnvironment` (tests) assemble the seams listed in `14 § 0.3`; no singletons or service locator; no protocols beyond that list. | Testability without a DI framework; bounded abstraction. | 2026-11-09 |
| D-context-menu | No right-click context menu on the menu-bar item in V1; footer carries the actions. | `MenuBarExtra` offers no supported right-click hook and `04` forbids `NSStatusItem` fallbacks. | 2026-11-09 |
| D-daily-no-fixed-time | The daily activity has no preferred clock time; `NSBackgroundActivityScheduler(interval 86400, tolerance 3600)` decides. `tb.poll.costDailyLocalTime` removed from `09`. | The API cannot pin a time of day; a second scheduler would duplicate `04`. | 2026-11-09 |
| D-deepseek-unavailable | DeepSeek `is_available == false` → remaining still shown, band forced `critical`, header chip `Provider reports account unavailable`. | The provider's own hard-stop signal must outrank the runway math. | 2026-11-09 |
| D-nwpathmonitor | Reachability via `Network.framework` `NWPathMonitor` behind the `NetworkMonitor` seam; offline → polls skipped (`sched.skip reason=offline`), UI banner. | System framework; avoids failing requests every minute while offline. | 2026-11-09 |
| D-ditto-zip | Diagnostics bundle zipped with `/usr/bin/ditto -c -k --sequesterRsrc` via `Process`. | Foundation has no zip writer; `ditto` ships with macOS; no dependency. | 2026-11-09 |
| D-icon-script | App icon rendered by `scripts/make-icon.swift` (CoreGraphics ring glyph on a rounded rect) into `AppIcon.appiconset`; committed PNGs. | Deterministic, dependency-free, re-renderable. | 2026-11-09 |
| D-postmortems | Every stage ends with a blameless postmortem `docs/postmortems/stage-<id>.md`, and the last stage of every phase also adds `docs/postmortems/phase-<n>.md`, both in the stage's own PR, following `14 § 0.6`. Machine-checked as D13. | Owner's instruction: lessons from each stage must feed the next one instead of being lost in chat history. | 2026-11-09 |
| D-xcodeproj-agent | **Supersedes: D-xcodeproj.** The agent writes `TokenBe.xcodeproj` (objectVersion 77, file-system-synchronized groups, local `TokenBeCore` package, shared scheme) at the owner's request; H1 is retired. Every `buildSettings` block in `project.pbxproj` stays empty — all settings live in `Config/*.xcconfig` (D-xcconfig), enforced by `scripts/stages/0.4.sh`. The agent may change the project file only to add or remove targets, package references or build phases. | Owner request 2026-11-09 ("can you make pbxproj instead of me?"). A hand-written file with no build settings also avoids the Xcode 26 template's target-level overrides (deployment target 26, sandbox on, default MainActor isolation) that would silently beat the xcconfig files. | 2026-11-09 |
| D-stage-branches | One branch per **stage** (`s<phase>.<stage>-<slug>`, `14 § 0`); `12 § R11`'s former "one milestone per branch" rule is replaced. Milestones in `10` remain aliases for groups of phases. | The stage is the unit of done, verify and merge; a milestone branch would hold many stages unmerged. | 2026-11-09 |

## Open items — apply the default, log a Q only if the default cannot work

| ID | Item | Default to apply |
|---|---|---|
| O-1 | Exact GRDB 7.x version | Latest 7.x at Milestone 1; record under D-grdb-version. **Applied: 7.12.0 (Stage 0.1).** |
| O-2 | Menu bar glyph artwork | Simple 1.5 pt ring, 18 pt template PDF, three variants drawn in code (`Path`) if no asset is provided. |
| O-3 | Account color palette for Overview chart (8 steps) | Use system `Color` set: blue, purple, teal, orange, pink, indigo, mint, brown — assigned by sidebar order. |
| O-4 | Export CSV columns per view | Exactly the visible columns, header row, RFC 4180 quoting, UTF-8 no BOM. |
| O-5 | JSON export schema | Exactly `03 § Durability` (`schema_version`, `exported_at`, then one array per exported table); `poll_state` and `ingest_file` excluded; no secrets. |
| O-6 | What happens when the LiteLLM feed changes shape | Decoder is lenient (unknown keys ignored); if `input_cost_per_token` key disappears for >50 % of entries, keep the last good snapshot and log `price.feed_failed reason=shape`. |
| O-7 | Anthropic `inference_geo`, `context_window` group_by | Not requested in V1 (not in 02 group_by list); if present in fixtures, ignored. Consequence: `_above_200k_tokens` prices are not applied (05 § Cost formula). |
| O-8 | Max accounts | 5 (one per provider). UI never needs pagination. |
| O-9 | Localization | English only; strings centralized in `Strings.swift` for later. |
| O-10 | Dark mode asset values | As listed in 08; adjust only for AA failures and record the change here. |
| O-11 | Notification authorization denied | Band changes still log; Alerts tab shows `Notifications are off in System Settings` with a button opening the pane. |
| O-12 | Harness line where `provider` account does not exist in TokenBe | Store `harness_event`, create no account, show count in Sources as `N lines for providers you haven't added`. |
| O-13 | User renames an app | `app.name` is immutable (it is the harness tag); `app.display_name` is editable and shown everywhere. |
| O-14 | Time zone change while running | Recompute "today" boundaries on `NSSystemTimeZoneDidChange`; log `sched.clock_jump` with `tz=true`. |
| O-15 | ⌥-click on the menu-bar item | Implement via `NSEvent.modifierFlags` at click; if unreliable, drop ⌥-click (footer `Open dashboard` remains) and log the choice in `QUESTIONS.md`. |
| O-16 | App slug for apps created from the Keys & apps `New app…` picker | Lowercase display name, non-matching chars → `-`, collapse repeats, trim; collision → `-2`, `-3`. |
| O-17 | Import into a non-empty database | Refused with a sheet explaining to reset first; no merge logic in V1. |
| O-18 | `ledger_event.kind = 'auto_zero'` | Kept in the CHECK constraint; no producer in V1 (admin endpoints never return the credit-exhausted signal; harness lines carry no error body). |

## Changelog of this document
- 2026-11-09 — Initial set, derived from the architecture brief, UX plan, critique, V1 scope lock, and stack iteration.
- 2026-11-09 — Added D-executor … D-icon-script and O-15 … O-18 from the development-plan review passes (`14 § 14`); O-5 aligned to `03`.
- 2026-11-09 — Added D-postmortems (owner instruction) and D-stage-branches (resolves the `12 § R11` ↔ `14 § 0` branching conflict).
- 2026-11-09 — D-grdb-version / O-1: GRDB pinned at 7.12.0 (Stage 0.1).
- 2026-11-09 — D-xcodeproj-agent supersedes D-xcodeproj (owner request; H1 retired, Stage 0.4).
