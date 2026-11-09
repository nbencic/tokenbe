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
