# Stage 9.2 — JSON export/import & CSV (all tables) (14 § Stage 9.2, 03 § Durability, O-5, O-17). Sourced by
# scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Export/JSONExporter.swift $core/Export/JSONImporter.swift $core/Export/TablesCSVExporter.swift
  $core/Store/Repository+Export.swift $app/SettingsUI/DataTransferRows.swift
  Tests/TokenBeCoreTests/ExportImportTests.swift Tests/TokenBeUITests/ExportImportUITests.swift scripts/stages/9.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 03's document (O-5): its tables, its key order, no poll_state / ingest_file, no key.
check "the nine tables of 03's document, in order" grep -qF 'case account, providerKey = "provider_key", app, appBinding = "app_binding", usageBucket = "usage_bucket"' $core/Store/Repository+Export.swift
check "top-level keys in 03's order (schema_version, exported_at, then the tables)" bash -c "grep -qF 'try part(.schemaVersion, document.schemaVersion), try part(.exportedAt, document.exportedAt),' $core/Export/JSONExporter.swift && grep -qF 'try part(.balanceSnapshots, document.balanceSnapshots), try part(.ledgerEvents, document.ledgerEvents),' $core/Export/JSONExporter.swift"
check "poll_state and ingest_file are not exported (O-5)" bash -c "! grep -nE 'poll_state|ingest_file' $core/Export/JSONExporter.swift $core/Export/JSONImporter.swift $core/Export/TablesCSVExporter.swift && ! grep -nE 'case .*(pollState|ingestFile)' $core/Store/Repository+Export.swift"
check "provider_key.redacted leaves as its key hint (A9, Q-056)" bash -c "grep -qF 'key.redacted = Self.exportedHint(key.redacted)' $core/Store/Repository+Export.swift && grep -qF 'table == .providerKey && column == \"redacted\"' $core/Store/Repository+Export.swift"

# O-17: only into an empty database, all or nothing; the account's poll_state seeding shared with insertAccount.
check "the import checks and inserts in one write transaction" bash -c "grep -qF 'database.write(\"importDocument\")' $core/Store/Repository+Export.swift && grep -qF 'guard occupied == 0 else { throw ImportRefusal.notEmpty }' $core/Store/Repository+Export.swift"
check "another schema version is refused" grep -qF 'throw ImportRefusal.schemaVersion(found: document.schemaVersion, expected: expected)' $core/Store/Repository+Export.swift
check "insertAccount and the import seed poll_state through one function (03)" bash -c "test \$(grep -c 'Self.seedPollStates(accountID: account.id, db: db)' $core/Store/GRDBRepository.swift $core/Store/Repository+Export.swift | awk -F: '{s+=\$2} END {print s}') -eq 2"
check "db.export {json, csv_tables}, db.import, db.import_failed (07)" bash -c "grep -qF '\"kind\": .string(\"json\")' $core/Export/JSONExporter.swift && grep -qF '\"kind\": .string(\"csv_tables\")' $core/Export/TablesCSVExporter.swift && grep -qF '.dbImport, cat: .db' $core/Export/JSONImporter.swift && grep -qF '.error, .dbImportFailed, cat: .db' $core/Export/JSONImporter.swift"
check "CSV uses 8.3's RFC 4180 writer" grep -qF 'ViewCSVExporter.data(csv).write(to: folder.appendingPathComponent(table.table + ".csv")' $core/Export/TablesCSVExporter.swift
check "Repository composes DataTransferRepository" grep -qF '& DataTransferRepository' $core/Store/Repository.swift

# Advanced → the three data rows, 08's copy and order, after Back up now (D6, D8).
check "Strings has 08's copy with the ellipsis" bash -c "grep -qF 'exportDataJSON = \"Export data (JSON)\\u{2026}\"' $app/Strings.swift && grep -qF 'importData = \"Import\\u{2026}\"' $app/Strings.swift && grep -qF 'exportCSVAllTables = \"Export CSV (all tables)\\u{2026}\"' $app/Strings.swift"
rows_order() {
  local f=$app/SettingsUI/DataTransferRows.swift e i c m d
  e="$(grep -n 'Button(Strings.exportDataJSON)' $f | cut -d: -f1)"; i="$(grep -n 'Button(Strings.importData)' $f | cut -d: -f1)"
  c="$(grep -n 'Button(Strings.exportCSVAllTables)' $f | cut -d: -f1)"
  m="$(grep -n 'DatabaseMaintenanceRows(settings: settings, repository: repository)' $app/SettingsUI/AdvancedTab.swift | cut -d: -f1)"
  d="$(grep -n 'DataTransferRows(repository: repository)' $app/SettingsUI/AdvancedTab.swift | cut -d: -f1)"
  [[ -n "$e" && -n "$i" && -n "$c" && -n "$m" && -n "$d" && "$e" -lt "$i" && "$i" -lt "$c" && "$m" -lt "$d" ]]
}
check "Export data (JSON)…, Import…, Export CSV (all tables)… after Back up now (08)" rows_order
check "the O-17 sheet explains how to get an empty database" grep -qF 'importNotEmptyTitle = "Import needs an empty database"' $app/Strings.swift
check "the test folder override is DEBUG-only under a test root (Q-056)" bash -c "grep -qF 'guard environment[Startup.testRootVariable] != nil, let path = environment[directoryVariable]' $app/SettingsUI/DataTransferRows.swift && grep -qF '#if DEBUG' $app/SettingsUI/DataTransferRows.swift"
check "1.3.sh no longer guards Export / Import (PM-8.3-1)" bash -c "! grep -qE '^for later in .*\"(Export|Import)\"' scripts/stages/1.3.sh"
check "03 names what an import reproduces" grep -qF 'reproduces every exported table, in one transaction' docs/03-data-model.md

for suite in ExportImportTests RepositoryAccountTests MigrationTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "ExportImportUITests passed (E2E-7)" grep -q "Test Suite 'ExportImportUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
