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
