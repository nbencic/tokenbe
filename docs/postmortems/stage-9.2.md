# Postmortem — Stage 9.2 JSON export/import & CSV (all tables)
Date: 2026-11-18 · Branch: s9.2-export-import · PR: #40 · Planned size: M · Commits: 5

## Outcome
03 § Durability's export and import are in Settings → Advanced, after `Back up now` (08):
- **`Export data (JSON)…`** writes 03's document in O-5's order: `schema_version`, `exported_at`, then the nine tables, one top-level key per line. Within each record the keys are column names, and rows are sorted by primary key. The output never holds a key, and `provider_key.redacted` leaves as its key hint, `…` + the last 4 characters.
- **`Import…`** reads such a file into an empty database (O-17), in one transaction: no account, no price override and no app besides the `Unassigned` seed. Each account gets its four `poll_state` rows through the same function `insertAccount` uses. A database that isn't empty, or a document of another schema version, is refused with a sheet, and nothing is written.
- **`Export CSV (all tables)…`** writes one RFC 4180 file per exported table into a new folder.
- **Logging:** `db.export {kind: json | csv_tables}`, `db.import`, `db.import_failed` (07).

E2E-7 (ExportImportUITests) runs export, wipe and import in the real app: every table comes back with the file's row count, and the card reads the same Remaining. The file holds no `sk-`, and a second import is refused. D1–D13 are met. No H-gate belongs to this stage; H2 and H3 stay open (owner).

## What went as planned
- **The design was reviewed before code.** The advisor added four points; each became code, a check or a Q-056 line before the first build:
  - 2.2.sh counts `.uiError` in `AdvancedTab.swift`, so the rows live in their own `DataTransferRows.swift` and that count stays at 2.
  - The empty check and the inserts share one write, and `poll_state` seeding is shared with `insertAccount`.
  - "Empty" is defined from what a fresh launch actually holds.
  - The refusal's log level.
- **Core tests passed on their first run.** `ExportImportTests` (5 cases) passed with the repository and migration suites: 34 tests in 6 suites.
- **E2E-7 passed on its first run** (`testExportWipeImport`, 1 min 59 s), with AdvancedMaintenanceUITests.
- **No pbxproj edit was needed.** The UI-test folder is synchronized, so the new suite needed no project change. That kept Q-047's selection to 6 suites; touching the project would have run all of them.
- **PM-8.3-2 held.** Before the first verify, the stage scripts were grepped for `Export`, `Import` and `AdvancedTab`. 1.3.sh's guards were retired with their controls (PM-8.3-1). The `Export` guard became an `Export diagnostics` guard, so 9.3 retires its own. 2.2.sh's `.uiError` count and its order check still hold.

## What went wrong
1. **A key prefix would have reached the export.**
   - **Symptom:** while writing the round-trip test, the seed rows turned out to store `provider_key.redacted = "sk-…abcd"`, and the synthetic OpenAI fixtures store `sk-FIXTURE-openai-a1b2`. E2E-7 and SEC-1 forbid both in an export.
   - **Root cause:** the column holds the provider's `redacted_value` verbatim, and providers keep the key's prefix in it.
   - **Fix:** the export writes `…` + the last 4 characters, the only part TokenBe reads (Q-056). `ExportImportTests.document` asserts no `sk-` and no `FIXTURE` in the file.
   - **Cost:** found before the first test run. The database itself still stores the provider's value (PM-9.2-1).
2. **`err.desc` of a refusal was empty of meaning.** `LogError` takes `localizedDescription`, which is generic for a plain Swift error. **Fix:** `ImportRefusal` is a `LocalizedError`, so the record reads `ImportRefusal.not_empty` / `not_empty`. Caught while writing the test, before it ran.
3. **Four lint violations on the first lint run.** These were a `String(decoding:)` conversion, an import function with complexity 11, `Strings` past 250 lines, and an extra blank line after moving the strings. **Fix:** the JSON is assembled as `Data`; the inserts became `insert(_:db:)`; the new copy went into its own `extension Strings`. Two lint reruns, before the first commit.

## Verify and CI failures
- **Core and lint:** 34 tests in the touched suites passed on the first run. Lint was clean after What went wrong 3.
- **Stage-script dry run** (9.2's static checks, 1.3 with its new guard list, 2.2's checks on `AdvancedTab.swift`): every check passed. One FAIL, 2.2's row order, was an artifact of the dry run copying the check without its function; run directly, it passes (rows 98 < 101).
- **UI, targeted:** ExportImportUITests and AdvancedMaintenanceUITests passed, 3 tests in 3 min 10 s.
- **Full verify** (Q-047 selected 6 suites: LaunchSmoke, PopoverEmptyState, AdvancedMaintenance, DailyRunNow, ExportImport, SettingsGeneral): `STAGE 9.2 OK` on the first run, with 1 457 checks passed and 23 printing `skip` (the unselected suites' checks and 3.6's H2 check). 7 UI tests passed with 0 failures in 6 min 35 s, and 569 Core tests in 85 suites passed. Disk had 86 GiB free, and the screen was unlocked.
- **CI:** the head that carries this file is checked by SHA before the merge.

## Deviations from the docs
- **03 § Durability** (Q-056), with 03 updated in this PR:
  - An import reproduces the nine exported tables. 03 said "every table except `poll_state` and `ingest_file`", which its own list contradicts.
  - "Empty" is defined.
  - `provider_key.redacted` is exported as the key hint.
  - The CSV files are named after the tables, with column-name headers.
- **O-17** says "reset first", but `Reset all settings…` never touches the database (08). The sheet tells the user to move the data folder aside instead (Q-056).
- **14 § Stage 9.2:** the Inventory now lists the files, and the Tests line the cases.

## Judgment calls
- Q-056: the export and import rules the docs leave open:
  - the nine tables;
  - the empty database;
  - the refusal and how it is logged;
  - row order and the shared `poll_state` seeding;
  - the key hint;
  - the JSON shape (NULLs omitted, sorted keys);
  - the CSV folder and files;
  - the panels and the DEBUG `TOKENBE_TEST_EXPORT_DIR`.

## Carry-forward actions
- PM-9.2-1 · agent · 11.2 · `provider_key.redacted` stores the provider's `redacted_value` verbatim. With the synthetic OpenAI fixtures that is `sk-FIXTURE-openai-a1b2`, so SEC-1's grep of `tokenbe.sqlite` for `sk-FIXTURE` will match. Decide in 11.2 whether the adapter stores only the hint (`…` + last 4), as the export now does, or whether SEC-1 should allow the redacted column.
- Earlier actions that targeted 9.2:
  - PM-9.1-2: closed. `1mo` rows go in as stored; `ExportImportTests.roundTrip` checks the counts per width.
  - PM-8.3-1: closed for 9.2. 1.3.sh no longer guards `Export` / `Import`, and now guards `Export diagnostics` for 9.3. Still open for 9.3, 9.4 and 9.5.
  - Statuses edited in stage-9.1 and stage-8.3.
- Still open from earlier stages:
  - PM-9.1-1 (11.1);
  - PM-8.1-1 (the H2 PR);
  - PM-8.1-2 (10.1);
  - PM-8.1-3 (9.5);
  - PM-8.4-1 (owner, 11.3);
  - PM-8.4-2 (11.3);
  - PM-4.3-3 (9.4).
