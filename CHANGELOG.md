# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository skeleton: SwiftPM `TokenBeCore` package (GRDB 7.12.0), lint rules, build/verify scripts, and the engineering docs (Stage 0.1).
- Logging core: redacted NDJSON log files with rotation and retention, os.Logger mirror, breadcrumbs, and a crash handler that records the last 50 breadcrumbs (Stage 0.2).
- Settings core: every setting from the spec with its default, range checks with logging, threshold ordering, reset, and the log level setting (Stage 0.3).
- The app: a menu-bar glyph with a placeholder popover; launch, quit and crash are logged, and an unclean previous run is detected (Stage 0.4).
- Continuous integration: build, tests, coverage gate, lint, event-table check, app build and a secret/URL guard on every pull request (Stage 0.5).
- Popover: the empty state (`No accounts yet`) and a `Quit` button; shared formatting for money, runway, tokens and freshness (Stage 1.1).
- Dashboard window: `Open dashboard` (⌘D) in the popover, or ⌥-click the menu-bar icon; empty Overview with the `Today | 7 d | 30 d | 90 d` range picker. The range and window position are remembered (Stage 1.2).
- Settings window: `Settings…` (⌘,) in the popover opens General, Privacy and Advanced. Launch at login, menu bar metric, pinned metric, sort, hide cents, appearance, accent, log level and log retention all work. A recordable global shortcut (default ⌃⌥T) toggles the Dashboard (Stage 1.3).
- Database: TokenBe keeps its data in `tokenbe.sqlite` (migration 001, WAL). A corrupt file is moved aside and replaced by the backup, or by a fresh database. If the database cannot be opened or migrated, an alert names the migration, the error and the backup path, then TokenBe quits without touching the file (Stage 2.1).
- Settings → Advanced: `Run integrity check now` shows `ok` or the first problem SQLite found, plus where a copy of the database was saved. `Back up now` writes `tokenbe.sqlite.bak` and shows its size, time and path. The popover's account list now comes live from the database (Stage 2.2).
- Networking core: one HTTP transport with 02's User-Agent, 15/30 s timeouts and a 20 MiB response cap; 04's error taxonomy and retry policy; DEBUG fixture mode; network reachability changes are logged. Nothing visible yet (Stage 3.1).
- Keychain storage for API keys: one login-keychain item per account (service `dev.bathyon.tokenbe`, this device only, never synced), and failures are logged without the key. Nothing visible yet (Stage 3.2).
- Provider seam: provider ids with key-prefix checks, a capabilities model stored as JSON, the adapter protocol, and a registry that offers only verified providers in Release builds. Adds `scripts/record-fixtures.sh` for recording redacted live fixtures. Nothing visible yet (Stage 3.3).
- OpenAI adapter: the probe behind onboarding's "Test connection", and polls for keys, hourly usage (last 48 h, paged, resumable) and daily cost (last 7 days) into the database, with 04's retries, circuit breaker and redacted diagnostics. Built on synthetic fixtures; nothing visible yet (Stage 3.4).
- Add an account: `Add account…` (or the first launch) opens onboarding — pick the provider, paste the key, `Test & continue`, then see the mode, keys found and currency, set the anchor and `Done`. The popover shows the account card (`No data yet`, or `Key missing · Fix…`), the Dashboard sidebar lists accounts, and Settings → Accounts edits the label, tests or replaces the key, pauses, lists Keys & apps and removes the account (Stage 3.5).
- OpenAI verification, first part: the fixture recorder follows every page of usage and costs, anonymizes people and key ids, and records the real 401 body; the response envelope keys seen in the first live recording are now known. OpenAI stays unverified until the owner's row-bearing recording (H2) lands (Stage 3.6).
- Polling runs on its own: usage every 5 min and key lists every hour for OpenAI, set in the new Settings → Sources tab (with the Low Power multiplier) or per account under Accounts → `Refresh intervals`. A new account is polled at once. The popover header shows `Refreshed …` and a refresh button; `Pause polling for 1 h` / `Resume` pause everything, and an account's `Paused` toggle pauses it. Offline, Low Power Mode, sleep/wake, clock jumps and stuck polls are handled and logged (Stage 4.1).
- Stale and offline: a card whose data is older than 3 × its poll interval (`tb.alerts.staleMultiplier`) dims and reads `stale · …`; offline, the popover shows `Offline — showing last known values` and dims every card; either turns the menu-bar ring dashed. Clicking a card, or an account in the Dashboard sidebar, opens the account page: provider, label, mode, band and freshness, `Refresh`, the Balance/Usage/Cost/Lag badges with a help sentence each, and a sources strip with each job's state, last success, next run and the last error in plain words. The Dashboard toolbar has `Refresh`; sidebar rows show `Key missing` (Stage 4.2).
- Daily tasks: once a day, at a time macOS picks, TokenBe polls OpenAI's costs, backs up its database, runs the full integrity check every 7th day and frees unused space; a failing task is logged and retried the next day without stopping the others. Settings → Sources → `Run daily tasks now` runs them at once; Settings → Advanced shows `Last daily run`; the account page's cost source shows the time of its last success (Stage 4.3).
- Price book: TokenBe ships a snapshot of the LiteLLM price map and refreshes it once a day (ETag, 20 MB cap, a feed that changed shape is ignored). Settings → Sources → Price book has the feed switch, `Refresh now`, `Stale after`, and an overrides table with `+`/`−` and `Reset to feed`; Advanced edits the feed URL. Each account page shows `Prices · <date> · ok/stale` (Stage 5.1).

### Changed
- The test coverage gate for the core library is now 97 % of lines, up from 85 % (Q-035).

### Fixed
- A poll stopped while it was writing (account removed, app quitting, overrun) no longer logs a `poll.failed` error.
