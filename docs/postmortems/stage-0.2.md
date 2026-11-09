# Postmortem — Stage 0.2 Logging core
Date: 2026-11-09 · Branch: s0.2-logging-core · PR: #2 · Planned size: M · Commits: 7

## Outcome
`07` is implemented in `TokenBeCore/Logging`:
- `Evt` is generated from the 07 table (103 events).
- `LogRecord` has a fixed key order and hand-written JSON.
- `Redactor` applies 7 patterns plus a substring pass over registered secrets.
- `LogPipeline` and the `Log` facade are synchronous for callers, using one bounded ordered stream, a 1 s flush and a 60 s drop report.
- `NDJSONSink` handles daily files, the `-N` size rotation, retention, the 300 MiB cap, a 0700 directory and 0600 files.
- `OSLogSink`, `Breadcrumbs` (500) and an allocation-free crash path (`CrashRing`, `CrashHandler`, `RunningSentinel`).

46 tests pass, and passed 20 of 20 repeated runs. TokenBeCore line coverage is 93.3%. DoD D1–D3, D9 and D11 are met. D12 has no CI yet (Q-005); D13 is met by this file. 07 § Definition of done items 1–3 are met. No human gate.

## What went as planned
- The `Package.swift` settings from 0.1 compiled the new concurrency code (Mutex, Atomic, actors, Regex literals) warning-free in release with `-warnings-as-errors`.
- The design review before coding caught most traps up front:
  - Swift Testing runs tests in parallel, so pipelines are per-test instances and only one serialized suite touches the global facade.
  - `drain()` is a barrier for deterministic assertions.
  - Logging's own I/O failures needed an event of their own.
  - The crash path must not lock.
- `check-log-events.sh` was verified in both directions: removing `appTerminate` from `Evt` makes it fail with the missing name.

## What went wrong
1. **Redaction gap in the spec.** Patterns 3 and 4 of 07 leak the token in `Authorization: Bearer <token>`: pattern 3 consumes only the word `Bearer`. Reproduced with the spec's regexes; JSON-quoted header names were also missed.
   - Root cause: the patterns were written without test vectors.
   - Fix: widened patterns, every vector pinned in `RedactorTests`, 07 updated (Q-006).
   - Cost: one investigation before coding.
2. **The NDJSON file handle was not in append mode,** so the sink's next write overwrote a crash line already written through the crash path's own `O_APPEND` descriptor.
   - Found by the `crashTarget` test: the first diagnosis ("the line is before the buffered record") was wrong, and printing the file contents showed the truncated tail.
   - Fix: the sink now writes through an `O_APPEND` descriptor too.
   - Cost: two test runs. Without the test this would have corrupted crash records whenever the sink flushed after a crash line, e.g. on the uncaught-exception path.
3. **`drain()` returned early when the stream was full,** because the barrier was dropped like any other item, making tests that drain right after an overflow vacuous.
   - Fix: `drain()` and `reportDroppedNow()` retry until the item is enqueued.
   - Cost: one run. My first explanation (report dropped because the stream was full) was only half right.
4. **My first `drain()` patch was malformed** (a leftover line and a type that does not exist). Caught by reading the patch back before building; rewritten.
5. **SwiftLint defaults vs. spec names.** The 3-character name minimum rejects `ts`, `v`, `db`, `ui` (fixed by 07) and `fd`, `op`. A 282-line test suite tripped `type_body_length`.
   - Fix: a named exclusion list, inline disables only for the two spec-mandated parameter lists, and the test suite split by an extension.
   - Cost: two lint rounds.

## Verify and CI failures
- `swift test` run 1: 3 failures in 2 tests (items 2 and 3 above). Run 2: the same 2 tests, after wrong first fixes. Run 3: green. Then 20 of 20 green repeated runs.
- `swiftlint --strict`: 34 violations, then 10, then 0 (item 5).
- `verify-stage.sh 0.2`, first run: every stage check green, D13 missing, as designed.
- No CI yet.

## Deviations from the docs
- `07 § Redaction` patterns 3 and 4 changed; pass 7 is a substring match; redaction runs before truncation (Q-006). 07 updated in this PR.
- `07 § Record shape`: omission of absent fields, sorted `ctx` keys, the `ctx_truncated` marker and the `crash.signal` cap exemption are now written down (Q-007, Q-008).
- New event `app.log_sink_failed` added to the 07 table (Q-009).
- The bounded stream lives in `LogPipeline`, not inside `NDJSONSink`, because the `LogSink` seam is async (Q-009).
- `Log.configure` takes optional `crashRing:` and `version:` beyond `(sinks:clock:)`. `NDJSONSink` takes injectable `limits`, `now`, `calendar`, `crashTarget` and `onFailure`, so tests never touch `~/Library/Logs/TokenBe`.
- `.swiftlint.yml` (not in the inventory): `identifier_name` exclusions for spec-fixed short names.
- Test helpers `TestClock`, `CapturingLogSink`, `TempDirectory`/`ManualDate` (in `Tests/…/Support/`) and the extra `LogFacadeTests` suite.

## Judgment calls
- Q-006 redaction patterns 3/4 widened, substring exact pass, redact before truncate.
- Q-007 NDJSON serialization details (omitted fields, sorted ctx, `ctx_truncated`, `thr` label).
- Q-008 `crash.signal` breadcrumbs as one string, exempt from the 2 KiB cap.
- Q-009 one bounded stream in `LogPipeline`; meaning of the synchronous flush; `app.log_sink_failed`.

## Carry-forward actions
- PM-0.2-1 · agent · 0.4 · Wire logging at launch (04 startup step 1):
  - `Log.configure(sinks: [NDJSONSink(crashTarget: true), OSLogSink()], clock: ContinuousClock(), crashRing: CrashRing(version:))`
  - `CrashHandler.install(ring:)`
  - `RunningSentinel` check → `crash.previous_launch`, then `markRunning()`
  - on `applicationWillTerminate`: `await Log.current?.shutdown()`, then `markClean()`

  Status: open.
- PM-0.2-2 · agent · 0.3 · Connect `tb.log.level` to `Log.minimumLevel` and `tb.log.retentionDays` to `NDJSONSink.Limits.retentionDays`. Retention runs when a file opens; decide whether a change re-opens the sink or waits for the next file. Status: open.
- PM-0.2-3 · agent · 0.5 · CI runs `check-log-events.sh` (D3) and the coverage gate. `11` also mentions a `--from-tests` mode ("every event produced by a test"), which can only pass once events have producers; schedule it then and say where. Status: open.
- Earlier actions targeting 0.2: none.
