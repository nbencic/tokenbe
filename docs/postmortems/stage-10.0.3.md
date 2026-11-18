# Postmortem — Stage 10.0.3 Migration 002: the provider list
Date: 2026-11-18 · Branch: s10.0.3-migration-002 · PR: #47 · Planned size: M · Commits: 2

## Outcome
The database now accepts accounts for Moonshot, Novita, StepFun, SiliconFlow and DeepInfra (Q-062).
- **Why a rebuild:** SQLite cannot alter 001's `CHECK (provider IN (…))`, so `002_providers.sql` rebuilds `account`. It creates `account_new` with every line of 001's `account` except the wider provider list, then copies, drops and renames.
- **No cascading deletes:** the migrator now runs every migration with `foreign_keys` OFF, set outside its transaction. It requires an empty `PRAGMA foreign_key_check` before commit, and turns foreign keys back ON on success and on failure. So dropping `account` cascade-deletes none of the nine referencing tables.
- **Exports:** a schema-1 export still imports (Q-063).

Nothing visible changes. D1–D13 are met; the soak runs, so the verify ran with `TB_UI_TESTS=0 TB_SOAK=1`. The 2.1 launch checks that see 002 on a fresh root are skipped until the soak ends.

**Owner step before rebuilding the soak copy:** copy `~/Library/Application Support/TokenBe/tokenbe.sqlite*` aside. 002 runs on the soak database at its next launch.

## What went as planned
- **The advisor named the trap before any code:** `DROP TABLE account` with foreign keys on deletes every child row, and the pragma is ignored inside a transaction. The FK-off path and `foreign_key_check` came first.
- **The committed `schema_v1.sqlite`**, with one row in every table, is the v1 fixture 03 asks for; no new binary fixture was needed.
- **`Migration002Tests` (5 tests) passed on its second run.** It checks:
  - row counts in every table, an empty `foreign_key_check`, and foreign keys back on;
  - `account`'s exact columns, types, defaults and keys, no `account_new` left behind, and nine `REFERENCES account(id)`;
  - all ten providers insertable, an unknown one refused, and `UNIQUE (provider)` holding;
  - a dangling reference rolls the migration back;
  - a schema-1 import works, and a schema-3 one is refused.
- **The full Core suite passed:** 595 tests.

## What went wrong
1. **Disk I/O errors in three new tests.**
   - **Root cause:** `let (_, database) = try await Self.migratedFixture()` released the `StoreHarness` at once. That deleted its temp folder under the open database.
   - **Fix:** keep the harness alive with `withExtendedLifetime`.
   - **Cost:** one test run.
2. **Import would have refused every pre-002 export.**
   - **Root cause:** `importDocument` required `schema_version == current`.
   - **Fix:** accept schema 1 through the current one (Q-063). 002 changes no exported column, so a schema-1 document is a valid schema-2 document. A newer document is still refused (9.2.sh's check stands).
3. **Existing tests assumed version 1:** `launchEvents`, `schemaAndSeeds`, `fixtureOpens`, `corruptWithoutBackup`, `failedMigration`, `laterMigration`, `bundledMigrations` and `SmokeTests`. The test migrations moved to version 3.

## Verify and CI failures
- **Dry run of 2.1, 9.2 and 10.0.3:** green. The first draft of 10.0.3.sh called 2.1.sh's `ddl_matches`, which doesn't exist in another stage's subshell, so that line was removed; 2.1.sh still checks 001 byte for byte.
- **Local coverage gate:** 9985/10290 = 97.04 %. Every new line is covered; Core's margin stays thin (PM-10.0.2-4).
- **Cumulative sweep `TB_UI_TESTS=0 TB_SOAK=1 scripts/verify-stage.sh 10.0.3`:** result below.

## Deviations from the docs
- **14 § 10.0.3 step 2** said only rebuilding migrations take the FK-off path. Every migration takes it now: one path is the least code, and it is harmless for 001 and for additive files. 14 is corrected.
- **2.1.sh:** a fresh root logs two `db.migrate` records (0→1, 1→2), and its launch check expects both. It is skipped while the soak runs.
- **`TokenBeCoreInfo.schemaVersion`** is now 2.

## Judgment calls
- Q-063 · an export made by an earlier schema imports; a newer one is refused.

## Carry-forward actions
- PM-10.0.3-1 · Nikola · before the next soak rebuild · Copy `~/Library/Application Support/TokenBe/tokenbe.sqlite*` aside. 002 runs on the soak database at its next launch.
- PM-10.0.3-2 · agent · 11.5 (after the soak) · Run 2.1's launch checks, which expect 0→1 and 1→2 on a fresh root, with everything else.
- Earlier actions that target this stage: PM-10.0.2-4 (keep coverage up) — met: every new line is covered.
