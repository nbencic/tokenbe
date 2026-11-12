# Postmortem — Stage 0.5 CI & secret/URL guards
Date: 2026-11-09 · Branch: s0.5-ci · PR: #5 · Planned size: S · Commits: 6

## Outcome
`10 § CI` runs on every PR and every push to `main`: `macos-15`, Xcode 16.4 (Swift 6.1.2), with these steps:
- release build with warnings as errors;
- `swift test` with coverage, then the coverage gate (TokenBeCore lines **94.31 %**, minimum 85 %);
- `swiftlint --strict`;
- `check-log-events.sh` (103 events);
- the app's Release build, unsigned;
- `check-no-secrets.sh` over the tracked tree and the build products.

The guard has a self-test that plants a key, a bearer token and an off-list URL, and passes only if all three are caught and nothing else. CI went green on the second run. DoD D1–D3 and D11 are met; D12 is met (PR merged with CI green); D13 is met by this file and `phase-0.md`.

## What went as planned
- The hand-written Xcode project (D-xcodeproj-agent) built in Release on Xcode 16.4 first time, closing PM-0.4-1.
- The coverage gate reads SwiftPM's own coverage JSON (`swift test --show-codecov-path`), so it doesn't depend on where the test bundle is. That location changed during this session (`.build/out/Products`).
- The local stage checks and CI use the same commands, so the only CI-only failure was the toolchain difference itself.

## What went wrong
1. **CI's first run failed to compile the tests on Swift 6.1:** `main actor-isolated class property 'changedKeyName' can not be referenced from a Sendable closure`.
   - Swift 6.2 (local) lets code anywhere read a `static let` of a `@MainActor` class; 6.1 does not. Exactly the drift Q-001 anticipated.
   - Fix: `nonisolated` on `Settings`' three constant statics.
   - Cost: one CI run, about 3 minutes.
2. **The secret guard's first run flagged 5 things, none of them secrets:**
   - a test literal (`"sk-ant-admin01-"`);
   - key-format prefixes in 02;
   - **the fixture placeholder `sk-FIXTURE-…` that 11 itself prescribes**, so correctly redacted fixtures would have failed;
   - the test binary built from that literal.

   Fix: the guard now matches individual strings and exempts exactly the placeholder and bare prefixes ending in `-`/`_`; the test literal is split. The self-test proves real keys are still caught.
3. **The coverage figure in the 0.3 postmortem was function coverage,** read from the wrong `llvm-cov` column. Found while writing the gate; corrected in `stage-0.3.md` (lines were higher).
4. **The local `.build` layout moved** (`.build/arm64-apple-macosx/debug` → `.build/out/Products/Debug`, test bundle renamed), which broke my hard-coded coverage command. Avoided in the gate by using the JSON path SwiftPM reports.

## Verify and CI failures
- Local `verify-stage.sh 0.5`: every stage check green on the first run, D13 missing, as designed.
- CI run 1 (42649239700): `Test TokenBeCore` failed (item 1); the later steps were skipped.
- CI run 2 (42649846718): all steps green in 5 min 44 s.

## Deviations from the docs
- `check-no-secrets.sh` exempts the 11 placeholder `sk-FIXTURE-<provider>-<last4>` and bare key prefixes (Q-016). The URL allowlist applies to Swift sources only: docs, the license and `Package.swift` legitimately contain other URLs, and R4 is about outbound requests from the app.
- The guard also fails on a tracked `.env` and supports `--root DIR` for its self-test. The `--runtime` mode (SEC-1, 11) belongs to Stage 11.2.
- CI installs SwiftLint from Homebrew (0.65.1 on the runner, the same as local).
- No branch protection rule was added on GitHub; the plan does not ask for one, and merges follow CLAUDE.md (CI green).

## Judgment calls
- Q-016 what the secret guard tolerates, and the scope of the URL allowlist.
- Q-001 and Q-005 resolved.

## Carry-forward actions
- PM-0.5-1 · agent · every stage · Swift 6.1 is the compile gate. Avoid 6.2-only behaviour (implicitly nonisolated `static let` on `@MainActor` types, trailing commas in argument lists, exit tests). When CI and local disagree, fix the code, not the CI toolchain. Status: open (process).
- PM-0.5-2 · Nikola · any time · Coverage beyond 85 %: the owner asked what 100 % takes. About 97–98 % is cheap (facade tests, failure injection with read-only folders, a test-only crash-probe executable). True 100 % would need a fake filesystem seam, which 14 § 0.3 forbids. Decide whether to schedule the cheap part; default: Stage 11.2. Status: closed 2026-11-12: the owner chose 97 %; the gate is 97 % (Q-035).
- Earlier actions targeting 0.5:
  - PM-0.1-1 closed;
  - PM-0.1-2 closed;
  - PM-0.2-3 partly closed (`--from-tests` → 9.5);
  - PM-0.4-1 closed.
