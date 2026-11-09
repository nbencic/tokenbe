# Postmortem — Stage 0.4 App project, build configuration, first launch
Date: 2026-11-09 · Branch: s0.4-app-project · PR: #4 · Planned size: M · Commits: 7

## Outcome
TokenBe now builds from `xcodebuild`:
- `TokenBe.xcodeproj` has two targets on synchronized folders, the local `TokenBeCore` package, a shared scheme and **zero build settings**. Everything comes from `Config/*.xcconfig`.
- The app launches to a code-drawn ring in the menu bar, with a placeholder popover until Stage 1.1.
- Startup step 1 of 04 configures logging and logs `app.launch`, installs the crash handler, checks and creates the sentinel, and wires `tb.log.level` and `tb.log.retentionDays`.
- Quit logs `app.terminate`, removes the sentinel and drains the log. A hard kill is reported at the next launch as `crash.previous_launch`.

Assets: 14 colour sets from 08 and a generated AppIcon. Verification: 67 Core tests and the UI launch smoke test pass. The launch, quit, relaunch and kill cycles ran under a throwaway root; the owner's real folders were never touched. DoD D1–D3, D7 and D9–D11 are met. D12 has no CI yet (Q-005); D13 is met by this file. **H1 is retired** at the owner's request (D-xcodeproj-agent).

## What went as planned
- Every build setting `14` lists resolved correctly from the xcconfig files on the first `-showBuildSettings`, except hardened runtime (item 2).
- `StartupSequence` lives in Core as a list of closures, as 14 asks, so the startup order is unit-tested (`StartupSequenceTests`, D7) without the app.
- The crash path built in 0.2 worked in the real app the first time:
  - `kill -9` left the sentinel;
  - the next launch logged `crash.previous_launch`;
  - a clean quit removed the sentinel.

## What went wrong
1. **H1 asked the owner to work around Xcode-template behaviour the plan did not mention.** Xcode 26's App template writes target-level settings (deployment target 26, App Sandbox on, default MainActor isolation, Swift 5) that override any xcconfig. I wrote GUI steps for clearing them. The owner asked me to write the project file instead.
   - Fix: a hand-written `project.pbxproj` with empty `buildSettings`, recorded as D-xcodeproj-agent (supersedes D-xcodeproj); `0.4.sh` enforces the empty blocks.
   - Cost: one round-trip with the owner.
2. **Hardened runtime was off in Debug** despite `ENABLE_HARDENED_RUNTIME = YES`.
   - Found by checking the resolved settings per target; root cause found by elimination: `ENABLE_PREVIEWS = YES` forces it off.
   - Fix: previews removed (Q-013). Xcode still omits `--options runtime` when signing Debug builds to run locally; Release is signed `adhoc,runtime`.
   - Cost: three probe builds.
3. **XCUITest kills the app,** leaving `.running` in the owner's real support folder; the next real launch would have reported a false crash. Found by checking the sentinel after the first UI-test run.
   - Fix: a Debug-only `TOKENBE_TEST_ROOT` (Q-014); the stale sentinel and today's test logs were removed.
   - The same review showed **14 D10 told the agent to `rm -rf` the owner's real data folders.** D10 now uses the test root, which removes a data-loss path for every later stage.
4. **The 0.3 regression check failed in 0.4.** The app named the store type, and 09's DoD is a plain grep for `UserDefaults` in `Sources/`.
   - Fix: a `SettingsSuite` factory inside `UserDefaultsStore.swift`.
   - Cost: one verify run. The regression design caught it.
5. **Smaller slips:**
   - a Swift 6 isolation error (a `@MainActor` class's static constant read from a nonisolated context);
   - zsh aborting on an empty glob in an ad-hoc check;
   - an over-broad `grep` that dumped full compiler command lines.

   One run each.
6. **`.env` was not git-ignored.** The owner mentioned a development key in `.env`; the file existed in the repo root, unignored (never committed).
   - Fix: `.env` / `.env.*` added to `.gitignore` in this PR. The key was not read.
   - My `chmod 600 .env` was denied by the permission system and left to the owner.

## Verify and CI failures
- `verify-stage.sh 0.4`, run 1: `FAIL 0.3 UserDefaults only in Settings/UserDefaultsStore.swift` (item 4).
- Run 2: every stage check green, D13 missing, as designed.
- UI tests run 1 (before isolation): passed but left the sentinel (item 3).
- Run 2: compile error (item 5). Run 3: green, with the real folders confirmed absent.
- No CI yet.

## Deviations from the docs
- D-xcodeproj → D-xcodeproj-agent; H1 retired (13, 14 § 0.4 and Stage 0.4, 12 § R13, 10 layout).
- `14` D10 rewritten to use `TOKENBE_TEST_ROOT` instead of deleting the owner's data (Q-014).
- `Config/Project.xcconfig` and `Config/UITests.xcconfig` added; extra signing and runpath settings in `Base.xcconfig`; no `ENABLE_PREVIEWS` (Q-013).
- Files beyond the inventory:
  - `Sources/TokenBeApp/Strings.swift` (R9);
  - `Sources/TokenBeCore/Startup/StartupSequence.swift` (14 Tests line);
  - `SettingsSuite` in `UserDefaultsStore.swift`;
  - `run.sh` tasks `build-app`, `build-app-release`, `uitest`;
  - `.gitignore` entries for `.env`.
- `app.launch` is logged twice at startup (launch context, then `startup_step`); `crash.previous_launch` reports `unknown` for the signal (Q-015).

## Judgment calls
- Q-013 extra xcconfig files and settings; no previews.
- Q-014 `TOKENBE_TEST_ROOT` for UI tests and verification; D10 rewritten.
- Q-015 startup logging details, colour sets for named tokens only, template `NSImage` glyph.

## Carry-forward actions
- PM-0.4-1 · agent · 0.5 · CI on `macos-15` / Xcode 16.x must open the objectVersion 77 project (introduced in Xcode 16) and build Release with `CODE_SIGNING_ALLOWED=NO`. If the runner's Xcode rejects it, record the minimum Xcode in 10. Status: open.
- PM-0.4-2 · agent · every stage · Launch checks and UI tests always set `TOKENBE_TEST_ROOT`; no script may delete or write the owner's real TokenBe folders or settings domain. `0.4.sh`'s "untouched" check keeps guarding this in every regression run. Status: open (process).
- PM-0.4-3 · Nikola · now · `chmod 600 ~/tokenbe-app/.env` (the agent's attempt was denied). Status: open.
- Earlier actions targeting 0.4:
  - PM-0.2-1 closed (startup and terminate wiring);
  - PM-0.3-1 closed (retention wiring);
  - PM-0.1-3 re-targeted → 11.5 (a Team is needed only for H4 now).
