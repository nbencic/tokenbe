# Migrations

Forward-only, additive, numbered SQL files (`001_initial.sql`, …), bundled as a resource and applied by `Migrator` (`Store/Migrator.swift`; `docs/03-data-model.md § Migrations`, `docs/12-agent-rules.md § R7`).

- Only files named `NNN_slug.sql` are migrations; this README is ignored.
- Each file runs in one transaction. On success its `schema_version` row is appended unless the file inserted it (001 seeds its own).
- A released file is never edited. A change is a new file, plus a fixture DB of the previous version and a test that migrates it (03).
- Every file runs with `foreign_keys` OFF (set outside its transaction) and must leave `PRAGMA foreign_key_check` empty, so a table that others reference can be rebuilt without cascading deletes (002 rebuilds `account` to widen a CHECK; no column is dropped or renamed).
