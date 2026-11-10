# Postmortem — Stage 2.1 Database, migration 001, Repository
Date: 2026-11-10 · Branch: s2.1-database · PR: #9 · Planned size: L · Commits: 1

## Outcome
TokenBe now keeps its data in `~/Library/Application Support/TokenBe/tokenbe.sqlite` (03).

**Opening the database.** `AppDatabase` is a GRDB `DatabasePool` with 03's PRAGMAs on every connection: WAL, `synchronous=NORMAL`, foreign keys, `auto_vacuum=INCREMENTAL`, `cache_size=-2000`, `mmap_size=0`, `temp_store=MEMORY` and `busy_timeout=5000`. A wait above 100 ms for the writer logs `db.busy`. The support folder is `0700`.

**Migration 001.** `001_initial.sql` is 03's DDL verbatim, 15 tables and 3 indexes, plus the seed rows `schema_version(1)` and `app('app_unassigned')`. `2.1.sh` diffs it against 03. `Migrator` is forward-only with one transaction per file and logs `db.migrate`, or `db.migrate_failed` at fault after a rollback.

**Durability.** `DatabaseOpener` is 04 startup step 2: open, `quick_check`, migrate.
- A corrupt file is moved aside to `tokenbe.sqlite.corrupt-<ts>` with its `-wal`/`-shm` (`db.corrupt`). Then `.bak` is restored (`db.restore`), or a fresh database is created.
- Any other failure raises `DatabaseOpenError`. The app shows `FatalErrorAlert`, naming the migration, the error and both paths, and quits without touching the file.
- `backup()` does an online backup to a temp file and an atomic rename (`db.backup` / `db.backup_failed`). `integrityCheck()` and `quickCheck()` log `db.integrity_check` and `db.quick_check`, and on failure `db.integrity_failed` with a copy. `incrementalVacuum()` logs `db.vacuum`.

**Records and Repository.**
- 14 GRDB record types, one per table, with explicit snake_case coding keys. Timestamps are RFC3339-millisecond strings (`DBTime`); flags are 0/1.
- `Repository = AccountRepository & MaintenanceRepository`, declaring only what 2.1 implements (Q-024).
- `GRDBRepository` is an actor; `insertAccount` also seeds the four `poll_state` rows. `MemoryRepository`, in the test target, behaves the same: the account tests run against both.

**Fixtures.** `schema_v1.sqlite` has one row in every table and is built by `FixtureDBBuilder`. `FixtureDBTests` fails if the committed file drifts from what the builder produces. `corrupt.sqlite` is its first 4 KiB.

**Verification.**
- 129 Core tests pass, 29 of them new in 5 suites: Migration, Durability, FixtureDB, RepositoryAccount and RecordRoundTrip. TokenBeCore coverage is 94.1%; the Store files are at 83–99%.
- `2.1.sh` launches the Debug app twice on a throwaway `TOKENBE_TEST_ROOT`. While the app runs, `tokenbe.sqlite` and its WAL exist and the folder is `0700`.
- The log has `db.open` (wal), `db.quick_check ok` and `db.migrate from=0 to=1`, with the startup steps in order: logging, database, login item.
- The relaunch migrates nothing. No error or fault records appear, and the owner's real support folder is unchanged.

DoD D1–D3, D5 (per Q-024), D7 and D9–D11 are met. D12 is met by the PR's green CI, D13 by this file.

## What went as planned
- The DDL went into 001 by extraction from 03, not by retyping, and `2.1.sh` re-diffs it on every verify. All 14 record types were generated from that same DDL, so no column could be missed or misspelled.
- The bundled `Migrations` resource ships inside the Xcode-built app without any project change. The first launch's `db.migrate from=0 to=1` proves it.
- Running the static checks standalone before the full verify (PM-1.3-5) and checking the screen lock first (PM-1.1-1) were followed.

## What went wrong
1. **The fixture builder wrote to the wrong folder on the first run.** `sourceDirectory(file: String = #filePath)` evaluates `#filePath` at the *call site*, MigrationTests.swift, one folder up from where the helper lives. It produced `/Fixtures/db` at the repo root. Fixed by reading `#filePath` inside the function.
2. **The first full test run failed `LogFacadeTests`.** `FixtureDBBuilder.build` opened the database without a test pipeline, so its `db.*` events went through the process-wide `Log` while `LogFacadeTests` had its own sink installed there. Every store test now passes a private pipeline.
3. **Two first-attempt test failures exposed real issues.**
   - GRDB gives pool readers a 10 s busy timeout, where 03 says 5000 ms everywhere.
   - `ISO8601FormatStyle` truncates the binary fraction, so `.123` printed as `.122`: a read-then-write drift. Both are fixed in the source, not the test (Q-024).
4. **The first `DatabaseOpenError` in the app log read "error 1".** `LogError` uses `localizedDescription`. The type is now a `LocalizedError`, and a test asserts the logged description names the migration.
5. **The fatal alert could not be screenshotted** (no screen-capture permission in this session). Its path was exercised by hand: the failing step logged `app.launch` at error with the `database` step, and the app stayed up showing a modal. Its appearance is not machine-verified.

## Verify and CI failures
- Verify: (filled in after the run)
- CI: (filled in after the run)

## Deviations from the docs
- 03 "migration 001 runs [auto_vacuum] first" → set by the writer connection before GRDB's WAL setup. 03's comment is corrected (Q-024).
- 14 step 5: only the account and maintenance methods implemented now are declared; `observeSummaryInputs` moves to 2.2. 14 is reworded (Q-024).
- 14 inventory `Tests/Support/FixtureDBBuilder.swift` → `Tests/TokenBeCoreTests/Support/`, the SwiftPM test target. 14 is corrected.
- 08 has no copy for the fatal and repair alerts; the strings are logged in Q-024.

## Judgment calls
All are in Q-024:
- the `auto_vacuum` placement and `busy_timeout` on readers;
- `db.busy` measured around writes;
- a hand-written migrator rather than GRDB's;
- the Repository composed per aggregate;
- what counts as corruption, move versus copy, and the sidecars;
- runtime integrity failure copies the file and leaves the restore to the next launch;
- `poll_state` seeds on account creation;
- millisecond rounding;
- the support folder tightened to `0700`;
- the alert copy.

## Carry-forward actions
- PM-2.1-1 · agent · process · A helper that defaults to `#filePath` or `#file` resolves at the caller. Read it inside the function when the helper's own location matters.
- PM-2.1-2 · agent · process · Tests never log through the process-wide `Log`. Every Core API that logs takes a `logPipeline:`, and tests pass one.
- PM-2.1-3 · agent · 2.2 · Declare `observeSummaryInputs` with `SummaryInputs`; `AppModel` reads the repository from `AppEnvironment.repository`.
- PM-2.1-4 · agent · 9.x · The weekly `integrity_check` decides whether a failure forces a restore on the next launch (Q-024). Closing the pool at quit, and the idle `wal_checkpoint(TRUNCATE)` / `optimize` of 03, are still open.
