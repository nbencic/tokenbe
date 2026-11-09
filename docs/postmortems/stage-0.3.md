# Postmortem — Stage 0.3 Settings core
Date: 2026-11-09 · Branch: s0.3-settings-core · PR: #3 · Planned size: S · Commits: 6

## Outcome
`09` is now code:
- `SettingsKey`: 53 keys generated from the 09 tables, each with type, default, rule and tab.
- Per-provider keys through `TemplatedSettingsKey` (`SettingsKey.expanded(_:)`, `.snoozedUntil(_:)`).
- `ProviderID`.
- The `SettingsStore` seam with `UserDefaultsStore` (the only file that mentions UserDefaults) and `InMemorySettingsStore`.
- `@Observable @MainActor Settings`, which provides:
  - clamp-on-write with `app.settings_changed {key, old, new, clamped, source}`;
  - the `critical < low < watch` order;
  - repair of invalid stored values at launch;
  - `Settings.didChange` and `changes`;
  - `resetAll()`, which keeps `tb.ui.onboardingDone` and logs `app.settings_reset`;
  - the `tb.log.level` binding.

65 tests pass, and passed 10 of 10 repeated runs. TokenBeCore line coverage is 93.2%. DoD D1–D4, D9 and D11 are met; for D4, consumers and controls arrive in the stages listed in 14 § 13.2. D12 has no CI yet (Q-005); D13 is met by this file. 09 § Definition of done is met. No human gate.

## What went as planned
- Generating `SettingsKey` and the accessors from the 09 tables worked first time: 53 keys, and every range in 09 mapped to a rule without exception. `0.3.sh` now diffs 09 against the enum in both directions.
- Settings carries over the pattern from 0.2 of injecting a log pipeline in tests, so the parameterized tests (53 keys × invalid values, 5 providers) ran in parallel without touching global state.
- Every test passed on its first full run once the code compiled.

## What went wrong
1. **Lint exclusion pointed at the wrong file.** `10`'s SwiftLint excerpt exempted `Settings/Settings.swift` from `tokenbe_no_userdefaults`, while 09 and 14 name `Settings/UserDefaultsStore.swift` as the only allowed file.
   - Root cause: a doc conflict.
   - Fix: per 12 § R1 the lower number (09) wins; `.swiftlint.yml` and `10` corrected in this PR.
   - Cost: none.
2. **A doc comment would have failed the 09 grep check.** The comment in `SettingsStore.swift` named the production type (`UserDefaults…`), which `grep -R "UserDefaults" Sources/` matches even in comments. Caught before the first build; reworded.
3. **Two logic slips caught while reading back:**
   - `set` announced a change even when nothing had changed;
   - a logging helper ignored its level argument.

   Fixed before the first test run.
4. **`Harness` was not `@MainActor`,** so creating the main-actor `Settings` failed to compile. One-line fix.
5. **Coverage fell to 73 %.** The generated accessors were mostly untested (28 % of their lines).
   - Fix: a generated `SettingsAccessorTests` exercising every property.
   - Cost: three lint rounds to fit the 50-line function limit.
6. **Trailing commas again.** Same lint rule as in 0.2; this time removed with a regex pass. A recurring habit, so listed under carry-forward.

## Verify and CI failures
- Build: one compile error (item 4).
- `swiftlint --strict`: 8 violations (trailing commas, cyclomatic complexity in `validate`, a 3-tuple), then 2 and 1 (test function length), then 0.
- `verify-stage.sh 0.3`, first run: every stage check green, D13 missing, as designed.
- No CI yet.

## Deviations from the docs
- `10 § SwiftLint rules`: exclusion path changed to `Settings/UserDefaultsStore.swift` (item 1).
- Files beyond the 14 inventory:
  - `Settings/UserDefaultsStore.swift`, named by 09;
  - `Settings/SettingSpec.swift` (rules, `ProviderID`, templated keys);
  - `Settings/Settings+Accessors.swift`, generated;
  - tests `UserDefaultsStoreTests` and `SettingsAccessorTests`.
- Both `Settings.didChange` (09) and `changes` (14) exist; `changes` returns a new stream per access (Q-010).
- `SettingsStore` adds `storedKeys()` to `get/set/remove/registerDefaults`, needed for "reset removes every `tb.*` key".
- `NDJSONSink.limits` is now settable through `setRetentionDays(_:)`, a 0.2 file changed for the PM-0.2-2 follow-up.

## Judgment calls
- Q-010 generated keys and accessors, templated-key type, both change announcements, injectable pipeline.
- Q-011 clamp semantics for non-numeric settings, pattern grammars, implied threshold bounds, launch repair.
- Q-012 suite name equal to the bundle id → the app's standard domain.

## Carry-forward actions
- PM-0.3-1 · agent · 0.4 · In the composition root, call `NDJSONSink.setRetentionDays` when `tb.log.retentionDays` changes, and pass the stored value at sink creation. Replaces the open part of PM-0.2-2. Status: closed in Stage 0.4 (`Startup.startLogging` applies the stored value and watches `changes`).
- PM-0.3-2 · agent · every stage · Write multi-line collection literals and argument lists without trailing commas: SwiftLint's `trailing_comma` flagged them in 0.2 and 0.3, and Swift 6.0 on CI rejects trailing commas in argument lists anyway. Status: open (process).
- Earlier actions targeting 0.3: PM-0.2-2 partly closed: `tb.log.level` bound, `setRetentionDays` added; the remainder moved to PM-0.3-1.
