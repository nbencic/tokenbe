# 12 — Agent working rules (read before every session; follow literally)

You are implementing TokenBe from `docs/`. These rules are not suggestions.

## R1 — Source of truth and precedence
1. `docs/13-decisions.md` (closed decisions) override everything else.
2. Then the numbered docs `01`–`11`; `14-development-plan.md` fixes the ORDER of work and each stage's inventory and definition of done. On a conflict between two docs, the LOWER number wins, and you fix the higher-numbered doc in the same PR.
3. Then the Paper file, for visual layout only.
4. Your own judgment is LAST and applies only to things the docs do not cover (see R3).

## R2 — No guessing
- If a value, name, format, threshold, endpoint field, or behavior is specified anywhere in `docs/`, use it exactly. Do not "improve" names, defaults or copy.
- If a provider response field is marked `[expected]` in `02`, you may develop against a `*.synthetic.json` fixture authored strictly from `02`'s field list, but the provider stays OUT of `Verified` until a `*.recorded.json` + `RECORDED` marker exist (`13 § D-verified-providers`). Never invent a field that is in neither `02` nor a fixture.
- Never invent API endpoints, parameters, headers, or response shapes. Never assume a provider has a balance endpoint; `02` lists which do.
- Never hard-code prices. Prices come from the feed or `price_override` (05).

## R3 — When something is unspecified
Check `13-decisions.md` → "Open items with defaults". If it is there, apply the default. If it is not:
1. Choose the option that adds the LEAST code and NO new dependency.
2. Write a dated entry to `docs/QUESTIONS.md` in this exact shape:
   ```
   ## Q-<nnn> <short title>            (YYYY-MM-DD)
   Context: <file/function where it arose>
   Options: A) … B) …
   Chosen for now: A — <one sentence why>
   Blocking: no|yes
   ```
3. Continue. Do not stop to ask unless `Blocking: yes`, which is reserved for: data loss risk, secret exposure risk, or a provider contract contradiction.

## R4 — Scope fence
- Build ONLY what `01` lists as V1 IN. Anything in V1 OUT is forbidden even as a stub, flag, TODO, or "future" enum case.
- No new SwiftPM dependency, ever, in V1. GRDB only. Need a feature a library would give? Write ≤ 200 lines yourself or log a Q and skip.
- No telemetry, analytics, crash reporters, or any outbound request not enumerated in `02` (provider endpoints, LiteLLM feed URL, GitHub releases URL). `check-no-secrets.sh` also greps for `URL(string:` literals and fails on any host outside the allowlist.
- No background daemon, launch agent, helper tool, or XPC service. One process.

## R5 — Errors and logging (hard)
- Every `catch` logs via `Log.<level>(evt:…)` with an event name from `07`. New event → add to `07`'s table in the same commit.
- No `try?`, no `catch {}`, no `print`, no `debugPrint`, no `NSLog`, no `os_log` direct calls (use `Log`).
- Every state transition the user can observe (band, stale, paused, circuit, ingest state) logs with its inputs.
- A failure must degrade, never crash: a failing adapter marks its account stale; a failing DB write retries per `04` then logs `error` and the UI shows the Sources strip error. The only acceptable `fatalError` is in `Migrations` when a migration file is missing from the bundle (programmer error, caught in CI).

## R6 — Concurrency (Swift 6 strict)
- Actors: `AccountPoller(provider)`, `PollCoordinator`, `IngestService`, `LogSink`, `PriceBook`. `@MainActor`: all SwiftUI views and view models, `Settings`.
- No `DispatchQueue`, no `Thread`, no `Timer` (use `ContinuousClock.sleep`), no `@unchecked Sendable` without a comment citing the invariant (`04` I1–I3) and a test.
- One `DatabasePool` (WAL) as `04` I2 states: writes are serialized on the pool's writer; UI reads use `ValueObservation` on reader connections, delivered on main. No second connection anywhere else.

## R7 — Data integrity
- Money is `Int64` cents. Tokens are `Int64`. Never `Double`, never `Float`, never `NSDecimalNumber` in storage or arithmetic. `Decimal` only inside `Formatters`.
- Every multi-row write is one transaction. Ingest offset + events: same transaction (06). Roll-ups: one transaction per tier per account.
- Migrations are forward-only, additive, numbered, and come with a fixture DB (03).
- Never delete user-entered `ledger_event` rows except by explicit user action.

## R8 — Secrets
- Keys enter via the paste field and go to Keychain in the same function that validated the probe. They are read into memory only inside the adapter call and dropped after; never stored on a view model, never in `UserDefaults`, never in DB, never in logs, never in exports, never in fixtures (redacted on record).
- `last_raw` in `poll_state` passes through `Redactor` BEFORE being stored.

## R9 — UI
- Copy strings are exactly those in `08`; put them in `Strings.swift` as `static let`. Do not paraphrase. Do not add emoji.
- Colors via asset names in `08`. No literal hex in views.
- Every number uses `.monospacedDigit()`. Every estimate carries `≈` and `±`.
- Do not add screens, tabs, menus, toolbar items, or settings that `08`/`09` do not list.

## R10 — Tests travel with code
- A PR that adds a function in `TokenBeCore` adds its test in the matching `*Tests` file (`11`).
- Fixture-driven adapter tests must assert exact DB row values, not just "no throw".
- Run `swift test` and `swiftlint --strict` before declaring any task done. Paste the summary line of both into the PR description.

## R11 — Commits and PRs
- One stage (`14`) per branch: `s<phase>.<stage>-<slug>`, e.g. `s3.4-openai-adapter` (D-stage-branches).
- Every stage PR contains its postmortem `docs/postmortems/stage-<id>.md`; the PR that closes a phase also contains `docs/postmortems/phase-<n>.md` (`14 § 0.6`, D-postmortems).
- Commit message: `<area>: <imperative summary>` where area ∈ `core|providers|ledger|ingest|ui|settings|logging|db|build|docs|tests`. Body lists the doc sections implemented (`Implements 05 §Runway, 09 tb.alerts.*`).
- Update `CHANGELOG.md` `[Unreleased]` in every PR that changes behavior.
- Never force-push a shared branch. Never commit `Tests/Fixtures` without running `scripts/record-fixtures.sh --verify-redacted`.

## R12 — Definition of done for ANY task
1. Behavior matches the referenced doc section word for word.
2. Tests exist and pass; lint passes; no new warnings.
3. Every new error path logs a `07` event.
4. Docs updated if you touched a contract (schema, event table, settings key, copy).
5. `docs/QUESTIONS.md` has an entry for every judgment call you made.
6. You did not add a dependency, a screen, a setting, an endpoint, or a background process that the docs do not list.
7. At stage level: the stage postmortem (and phase postmortem, if the stage closes a phase) exists per `14 § 0.6`, and every open carry-forward action from earlier postmortems that targets this stage is closed or explicitly re-targeted.

## R13 — Things you must NEVER do
- Call a provider API during `swift test`.
- Store or print a key, even partially beyond the last 4 characters.
- Add Gemini, proxies, virtual keys, Claude Code log parsing, quota cards, a local HTTP API, webhooks, Sparkle, or currency conversion (all V1 OUT).
- Change a default in `09` or a threshold in `05` because it "seems better".
- Replace GRDB with raw `sqlite3` or add another storage layer.
- Add a provider to `Verified` without a `RECORDED` marker, or ship a Release build that offers an unverified provider.
- Start a stage of `14` before `scripts/verify-stage.sh` passes for the previous one, or skip a stage.
- Edit `TokenBe.xcodeproj/project.pbxproj` by hand (settings go in `Config/*.xcconfig`; the project was created once in the GUI).
