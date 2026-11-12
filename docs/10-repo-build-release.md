# 10 — Repository, build, release

## Repository: `github.com/nbencic/tokenbe` (public, MIT)

```
tokenbe/
├── Package.swift                       # SwiftPM: TokenBeCore + tests (no app target here)
├── TokenBe.xcodeproj/                  # App + UI-test targets, written by the agent (D-xcodeproj-agent); synchronized folders; no build settings
├── Config/                             # Base.xcconfig, Debug.xcconfig, Release.xcconfig — ALL build settings live here (D-xcconfig)
├── Sources/
│   ├── TokenBeCore/
│   │   ├── Model/                      # DB records (GRDB Record types), TokenClasses, Band, Money
│   │   ├── Store/                      # Database.swift, Migrations/001_initial.sql, Repository protocol + GRDBRepository
│   │   ├── Providers/                  # ProviderAdapter protocol, ProviderRegistry, Verified.swift; OpenAI/, Anthropic/, OpenRouter/, DeepSeek/, XAI/ (one folder each: Client.swift, DTOs.swift, Normalizer.swift, Probe.swift)
│   │   ├── Network/                    # HTTPTransport, URLSessionTransport, FixtureTransport (DEBUG), PollError, RetryPolicy, NetworkMonitor
│   │   ├── Normalize/                  # Normalizers (05)
│   │   ├── Pricing/                    # PriceBook, FeedFetcher, Lookup (05)
│   │   ├── Ledger/                     # Remaining, Burn, Runway, Band, Drift (05)
│   │   ├── Ingest/                     # FSEventsStream, Tailer, LineParser, Attribution (06)
│   │   ├── Scheduling/                 # SchedulerLoop, Job, Backoff, Circuit (04)
│   │   ├── Logging/                    # Log.swift (API), Redactor, NDJSONSink, Breadcrumbs, CrashHandler (07)
│   │   ├── Keychain/                   # KeyStore (SecItem wrapper)
│   │   └── Settings/                   # SettingsKey, Settings (09)
│   └── TokenBeApp/
│       ├── TokenBeApp.swift            # @main; MenuBarExtra + Window("Dashboard") + Settings
│       ├── Popover/, Dashboard/, Onboarding/, SettingsUI/, Components/, Notifications/, HotKey/, Export/, Update/
│       └── Resources/                  # Assets.xcassets (colors from 08, AppIcon), prices.bundled.json(+.sha256), reporters/ (copied from docs/reporters)
├── Tests/
│   ├── TokenBeCoreTests/               # unit + integration (11)
│   ├── TokenBeUITests/                 # XCUITest target (Xcode), accessibility-identifier state tests
│   ├── Load/                           # LOAD-1 generator
│   └── Fixtures/                       # providers/<p>/*.recorded.json + RECORDED marker, *.synthetic.json, harness JSONL samples, DB fixtures per schema version
├── scripts/
│   ├── run.sh / wait.sh                # background + log + timeout runner for every long command (14 § 0)
│   ├── verify-stage.sh + stages/<id>.sh # machine-checked stage DoD (14)
│   ├── make-icon.swift                 # renders AppIcon PNGs (D-icon-script)
│   ├── update-bundled-prices.sh        # refreshes Resources/prices.bundled.json at release
│   ├── coverage-gate.sh                # ≥ 97 % lines in TokenBeCore (Q-035)
│   ├── bootstrap.sh                    # checks macOS ≥ 15, Xcode ≥ 16.2, swiftlint
│   ├── check-log-events.sh             # 07 DoD
│   ├── check-no-secrets.sh             # SEC-1 grep over build products and bundle
│   ├── record-fixtures.sh              # curls each endpoint with env keys, redacts, writes Tests/Fixtures/<provider>/<endpoint>.json
│   ├── release.sh                      # archive → notarize → dmg → GitHub release → cask bump
│   ├── check-traceability.sh           # E2E-9: band changes ↔ causing poll/ledger records
│   ├── load-5y.sh                      # LOAD-1 driver
│   └── perf-idle.sh                    # samples RSS/CPU for 10 min (11 PERF)
├── docs/                               # THIS folder, verbatim
├── Casks/tokenbe.rb                    # Homebrew cask (tap: nbencic/homebrew-tap)
├── .swiftlint.yml
├── .github/workflows/ci.yml            # macos-15 runner: swift build, swift test, swiftlint, check-no-secrets, check-log-events
├── CHANGELOG.md                        # Keep a Changelog format
├── LICENSE                             # MIT
└── README.md                           # install, provider key how-to (02 excerpts), reporter snippets (06)
```

## Package.swift (exact)

```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
  name: "TokenBeCore",
  platforms: [.macOS(.v15)],
  products: [.library(name: "TokenBeCore", targets: ["TokenBeCore"])],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0")   // pin; bump only via a dedicated PR
  ],
  targets: [
    .target(name: "TokenBeCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Store/Migrations")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency"), .swiftLanguageMode(.v6)]),
    .testTarget(name: "TokenBeCoreTests", dependencies: ["TokenBeCore"], resources: [.copy("../Fixtures")])
  ]
)
```
If `7.12.0` (pinned in Stage 0.1, D-grdb-version) is not the current GRDB release at implementation time, use the latest 7.x and record the version in `13-decisions.md`. No other dependency may be added (00 non-negotiables).

## Xcode app target settings (exact)
All settings below are set in `Config/*.xcconfig` (not in the pbxproj) — see `14 § 0.4` for the file contents and the one-time GUI steps.
- Bundle id `dev.bathyon.tokenbe`; display name `TokenBe`; `LSUIElement = YES` (no Dock icon); `MACOSX_DEPLOYMENT_TARGET = 15.0`; `SWIFT_VERSION = 6.0`; `SWIFT_STRICT_CONCURRENCY = complete`; `ENABLE_HARDENED_RUNTIME = YES`; App Sandbox **OFF** (decision D-sandbox in 13: Developer ID distribution does not require it, and the harness drop folder must live at the human path `~/Library/Application Support/TokenBe/ingest/` so reporters can append to it without container gymnastics). Entitlements file contains only `com.apple.security.cs.allow-jit = false` defaults — i.e., no sandbox keys. Hardened Runtime stays ON; no `disable-library-validation`.
- `NSUserNotificationsUsageDescription` not required on macOS but set `UNUserNotificationCenter` auth request at first band alert, not at launch.
- Build settings: `-warnings-as-errors` for the Core package in CI; `DEAD_CODE_STRIPPING = YES`; `SWIFT_OPTIMIZATION_LEVEL = -O` (Release), `-Osize` NOT used.

## SwiftLint rules (`.swiftlint.yml` excerpt; all are errors)
```yaml
custom_rules:
  tokenbe_no_silent_catch:
    regex: 'catch\s*\{\s*\}|try\?'
    message: "Every error must be logged (07). Use `catch { Log.error(...) }`."
    severity: error
  tokenbe_no_userdefaults:
    regex: 'UserDefaults\.'
    excluded: 'Sources/TokenBeCore/Settings/UserDefaultsStore.swift'   # 09 names this as the only file (fixed in Stage 0.3)
    severity: error
  tokenbe_no_double_money:
    regex: '(cents|amount|price|cost)\w*\s*:\s*Double'
    severity: error
  tokenbe_no_hex_in_views:
    regex: 'Color\(red:|#[0-9A-Fa-f]{6}'
    included: 'Sources/TokenBeApp'
    severity: error
  tokenbe_no_print:
    regex: '^\s*print\('
    severity: error
disabled_rules: [line_length]
```

## Versioning
- SemVer. V1 ships as `1.0.0`. `CFBundleShortVersionString` = semver, `CFBundleVersion` = monotonically increasing integer (CI run number).
- Schema version (03) is independent; bumping schema requires a new migration file and a fixture DB.

## Signing & notarization (`scripts/release.sh`, run locally by the maintainer; never in CI)
1. `xcodebuild -scheme TokenBe -configuration Release archive -archivePath build/TokenBe.xcarchive`
2. `xcodebuild -exportArchive -exportOptionsPlist scripts/ExportOptions.plist` (method `developer-id`, team id from `TOKENBE_TEAM_ID` env).
3. `create-dmg` is NOT allowed (dependency). Use `hdiutil create -volname TokenBe -srcfolder build/export -ov -format UDZO build/TokenBe-<ver>.dmg`.
4. `codesign --sign "Developer ID Application: …" --timestamp build/TokenBe-<ver>.dmg`
5. `xcrun notarytool submit build/TokenBe-<ver>.dmg --keychain-profile tokenbe-notary --wait`
6. `xcrun stapler staple build/TokenBe-<ver>.dmg`
7. `shasum -a 256` → written to the release notes and the cask.
8. `gh release create v<ver> build/TokenBe-<ver>.dmg --notes-file build/notes.md` (notes = CHANGELOG section).
9. Update `Casks/tokenbe.rb` `version` and `sha256`; push to `nbencic/homebrew-tap`.

## Homebrew cask (exact template)
```ruby
cask "tokenbe" do
  version "1.0.0"
  sha256 "<sha256>"
  url "https://github.com/nbencic/tokenbe/releases/download/v#{version}/TokenBe-#{version}.dmg"
  name "TokenBe"
  desc "Menu bar runway and spend tracker for LLM provider accounts"
  homepage "https://github.com/nbencic/tokenbe"
  depends_on macos: ">= :sequoia"
  app "TokenBe.app"
  zap trash: [
    "~/Library/Application Support/TokenBe",
    "~/Library/Logs/TokenBe",
    "~/Library/Preferences/dev.bathyon.tokenbe.plist",
  ]
end
```

## CI (`.github/workflows/ci.yml`) — must pass before merge
Steps on `macos-15`: checkout → `xcode-select` 16.x → `swift build -c release` → `swift test` → `swiftlint --strict` → `scripts/check-log-events.sh` → `scripts/check-no-secrets.sh` → `xcodebuild -scheme TokenBe -configuration Release build CODE_SIGNING_ALLOWED=NO`. Any step failing blocks.

## Milestones (aliases for the phases of `14-development-plan.md`, which is the authoritative order)
| # | Name | Exit criterion |
|---|---|---|
| 0 | Fixtures | `scripts/record-fixtures.sh` run against real keys by the maintainer; every `[expected]` in 02 resolved and 02 updated; fixtures committed redacted. |
| 1 | Core skeleton | Package builds; DB opens + migrates; Log sink writes; Settings registers; `swift test` green on empty suite. |
| 2 | Providers | All 5 adapters pass fixture-driven tests; probe sequences implemented; poll_state persisted. |
| 3 | Ledger & pricing | 05 tests green; runway/band for fixture data matches hand-computed table in `Tests/Fixtures/expected/ledger.csv`. |
| 4 | UI | Popover/Dashboard/Onboarding/Settings per 08/09; snapshot tests green; Paper reconciled. |
| 5 | Ingest | 06 E2E green incl. kill −9. |
| 6 | Hardening | PERF, LOAD-1, SEC-1 green; 14-day soak on maintainer machine with log review; zero `error`-level events not explained in `docs/QUESTIONS.md`. |
| 7 | Release 1.0.0 | notarized dmg, cask, README, CHANGELOG. |
