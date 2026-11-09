# Postmortem — Stage 0.1 Repository skeleton & Core package
Date: 2026-11-09 · Branch: s0.1-repo-skeleton · PR: #1 · Planned size: S · Commits: 7

## Outcome
`github.com/nbencic/tokenbe` has a buildable SwiftPM package `TokenBeCore` (GRDB 7.12.0 pinned), a passing Swift Testing smoke test, `swiftlint --strict` with all custom rules from `10` plus `tokenbe_no_inline_text`, the background runner (`run.sh`/`wait.sh`), `bootstrap.sh`, `verify-stage.sh` with the D13 postmortem check, and the doc set under `docs/`. DoD D1–D3, D9, D11 met; D12 has no CI to wait for yet (Q-005); D13 met by this file. No open human gate.

## What went as planned
- `Package.swift` exactly as `10` (only the GRDB version changed) builds in debug and in release with `-warnings-as-errors`. `.enableUpcomingFeature("StrictConcurrency")` under `.swiftLanguageMode(.v6)` raises no warning on Swift 6.2.4.
- `.copy("../Fixtures")` resolves from the test target, even though the path leaves the target folder.
- `run.sh`/`wait.sh` checked on a throwaway copy with fake tasks: the exit code comes through (7), a task over its timeout is killed with its child processes (124, no leftover processes), `--detach` followed by `wait.sh` returns the real exit code, and an unknown task exits 2.

## What went wrong
1. First `git push` failed (`could not read Username`) → git was not set up to use the gh login → `gh auth setup-git` → cost: one retry.
2. First `swift build` failed (`missing inputs: …/Store/Migrations`) → the exact `Package.swift` declares resource folders whose content arrives in 2.1/3.4, and git does not keep empty folders → a short `README.md` in each folder (Q-004) → cost: one build.
3. First README draft said the app "sends nothing anywhere else" → wrong, since `D-no-telemetry` allows the LiteLLM feed and GitHub releases → rewritten from `01 § One sentence` before the first commit → cost: none shipped.
4. Permission prompts interrupted the run even in bypass mode → `ask` rules in the owner's user settings (`git push`, `rm`, `mv`, `cp`) override bypass → removed at the owner's request (backup `~/.claude/settings.json.bak-20261109`), and the project's local settings now start in bypass mode → cost: one rejected push, retried.
5. The new `14 § 0.6` text first said D13 runs *before* the stage scripts, which contradicts its own "verify, then write the postmortem" order → changed to *after* in this PR → cost: none shipped.

## Verify and CI failures
- `verify-stage.sh 0.1`, first run: every stage check green, `FAIL D13 postmortem stage 0.1` (missing file). Expected by design (§ 0.6); this file fixes it.
- No CI exists yet (arrives in 0.5).

## Deviations from the docs
- `10 § Package.swift`: GRDB `7.4.1` → `7.12.0` (latest 7.x); `10` and `13 § D-grdb-version`/`O-1` updated in this PR.
- `.swiftlint.yml`: added `included` (Sources, Tests, Package.swift) and `excluded` (`.build`, `build`, `DerivedData`) beyond the `10` excerpt; without them lint would scan build products. Rules unchanged.
- `.gitignore`: added `.swiftpm/` (SwiftPM's per-user Xcode state) and `.claude/settings.local.json` (per-user Claude Code settings) to the `14` list.
- `Package.resolved` committed although not in the inventory: it is the dependency lockfile that makes the pin reproducible.
- `CLAUDE.md` (owner's file) committed at the root; not in the inventory.
- Scripts go beyond the plan's wording, without changing any requirement: `run.sh --detach`, extra tasks `build-release` and `lint`, and an optional `TB_WAIT_INTERVAL` override (default 15 s). With 15 s polling, `verify-stage.sh 0.1` takes about 46 s.
- Repo root is `~/tokenbe-app`; the doc set moved into `docs/` (Q-003).

## Judgment calls
- Q-001 local toolchain (macOS 27, Xcode 26.3) newer than the documented one; CI stays the compatibility gate.
- Q-002 key variable names for H3: `DEEPSEEK_API_KEY`, `XAI_API_KEY`.
- Q-003 repo root `~/tokenbe-app`, docs moved into `docs/`.
- Q-004 resource placeholder READMEs.
- Q-005 empty root commit as the PR base; merge 0.1–0.4 on `STAGE <id> OK` without CI.

## Carry-forward actions
- PM-0.1-1 · agent · 0.5 · First CI run on `macos-15` with Xcode 16.x: confirm `Package.swift` (incl. `enableUpcomingFeature("StrictConcurrency")`) and the Swift Testing smoke test build warning-free on Swift 6.0/6.1; if not, record the fix and close Q-001. Status: closed in Stage 0.5 (Xcode 16.4 / Swift 6.1.2; one fix: `nonisolated` statics in `Settings`; Q-001 resolved).
- PM-0.1-2 · agent · 0.5 · CI runs the same commands as `run.sh` (`build-release`, `test`, `lint`), so local verify and CI cannot drift. Status: closed in Stage 0.5 (`ci.yml` uses the same commands and flags as `build-release`, `test`, `lint`, `build-app-release`).
- PM-0.1-3 · Nikola · 0.4 · No code-signing identity on the Mac: sign in with your Apple ID in Xcode → Settings → Accounts before H1, so a Team can be chosen. Status: re-targeted → 11.5 (H1 retired by D-xcodeproj-agent; a Team is now needed only for the Developer ID signing of H4).
