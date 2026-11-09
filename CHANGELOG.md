# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository skeleton: SwiftPM `TokenBeCore` package (GRDB 7.12.0), lint rules, build/verify scripts, and the engineering docs (Stage 0.1).
- Logging core: redacted NDJSON log files with rotation and retention, os.Logger mirror, breadcrumbs, and a crash handler that records the last 50 breadcrumbs (Stage 0.2).
- Settings core: every setting from the spec with its default, range checks with logging, threshold ordering, reset, and the log level setting (Stage 0.3).
- The app: a menu-bar glyph with a placeholder popover; launch, quit and crash are logged, and an unclean previous run is detected (Stage 0.4).
