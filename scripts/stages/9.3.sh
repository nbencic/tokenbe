# Stage 9.3 — Diagnostics bundle (14 § Stage 9.3, 07 § Diagnostics bundle, D-ditto-zip). Sourced by
# scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Export/DiagnosticsBundle.swift $core/Store/Repository+Diagnostics.swift
  $app/SettingsUI/DiagnosticsExportButton.swift Tests/TokenBeCoreTests/DiagnosticsBundleTests.swift scripts/stages/9.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# 07's contents, zipped with ditto (D-ditto-zip); never the database or the Keychain.
check "07's fixed files, in its order" grep -qF 'public static let fixedFiles = ["breadcrumbs.ndjson", "settings.json", "schema.sql", "db-stats.json",' $core/Export/DiagnosticsBundle.swift
check "the last 3 logs, parsed by NDJSONSink's own file-name rule" bash -c "grep -qF 'public static let logFileCount = 3' $core/Export/DiagnosticsBundle.swift && grep -qF 'NDJSONSink.logFile(named: \$0, in: directory, calendar: .current)' $core/Export/DiagnosticsBundle.swift"
check "zipped with /usr/bin/ditto -c -k --sequesterRsrc" bash -c "grep -qF 'URL(fileURLWithPath: \"/usr/bin/ditto\")' $core/Export/DiagnosticsBundle.swift && grep -qF '[\"-c\", \"-k\", \"--sequesterRsrc\", staging.path, zip.path]' $core/Export/DiagnosticsBundle.swift"
check "the bundle never reads the database file or the Keychain" bash -c "! grep -nE 'tokenbe\\.sqlite|KeyStore|Keychain|SecItem' $core/Export/DiagnosticsBundle.swift $core/Store/Repository+Diagnostics.swift | grep -v '///'"
check "every written text passes the Redactor again; the pipeline is drained first" bash -c "grep -qF 'try Data(redactor.redact(text).utf8).write' $core/Export/DiagnosticsBundle.swift && grep -qF 'await flush()' $core/Export/DiagnosticsBundle.swift"
check "app.diagnostics_exported {path, bytes, files} (07)" grep -qF '.appDiagnosticsExported, cat: .app' $core/Export/DiagnosticsBundle.swift
check "07's file name TokenBe-diagnostics-YYYYMMDD-HHMMSS.zip" grep -qF 'return "TokenBe-diagnostics-\(stamp).zip"' $core/Export/DiagnosticsBundle.swift
check "Repository composes DiagnosticsRepository" grep -qF '& DiagnosticsRepository' $core/Store/Repository.swift

# Advanced → Export diagnostics… between Log retention and Open log folder (08's order).
check "Strings has 08's copy with the ellipsis" grep -qF 'exportDiagnostics = "Export diagnostics\u{2026}"' $app/Strings.swift
diagnostics_order() {
  local f=$app/SettingsUI/AdvancedTab.swift r d o
  r="$(grep -n 'settings.advanced.logRetention' $f | cut -d: -f1)"; d="$(grep -n 'DiagnosticsExportButton(settings:' $f | cut -d: -f1)"
  o="$(grep -n 'OpenLogFolderButton(logsDirectory' $f | cut -d: -f1)"
  [[ -n "$r" && -n "$d" && -n "$o" && "$r" -lt "$d" && "$d" -lt "$o" ]]
}
check "Log retention, Export diagnostics…, Open log folder (08)" diagnostics_order
check "1.3.sh no longer guards Export diagnostics (PM-8.3-1)" bash -c "! grep -qE '^for later in .*\"Export diagnostics\"' scripts/stages/1.3.sh"

for suite in DiagnosticsBundleTests LogSinkTests; do
  check "suite $suite passed" suite_passed "$suite"
done
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "AdvancedMaintenanceUITests passed (Export diagnostics…)" grep -q "Test Suite 'AdvancedMaintenanceUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
