# Stage 8.3 — CSV export of the current view (14 § Stage 8.3). Sourced by scripts/verify-stage.sh.

app=Sources/TokenBeApp
core=Sources/TokenBeCore
inventory=(
  $core/Export/ViewCSVExporter.swift $app/Dashboard/ViewExport.swift
  Tests/TokenBeCoreTests/CSVExporterTests.swift scripts/stages/8.3.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

# O-4 in Core: RFC 4180 quoting, CRLF records, UTF-8 without a BOM, db.export {kind=csv_view, path, rows} (07).
check "fields are quoted only when they hold , \" CR or LF; quotes doubled (RFC 4180)" bash -c "grep -qF 'replacingOccurrences(of: \"\\\"\", with: \"\\\"\\\"\")' $core/Export/ViewCSVExporter.swift"
check "every record ends with CRLF" grep -qF '.joined(separator: ",") + "\r\n"' $core/Export/ViewCSVExporter.swift
check "UTF-8 bytes, no BOM written" bash -c "grep -qF 'Data(csv(table).utf8)' $core/Export/ViewCSVExporter.swift && ! grep -nE 'EF ?BB ?BF|\\\\u\\{FEFF\\}' $core/Export/ViewCSVExporter.swift"
check "db.export logs kind=csv_view, path and rows" bash -c "grep -qF '.dbExport, cat: .db' $core/Export/ViewCSVExporter.swift && grep -qF '\"kind\": .string(\"csv_view\")' $core/Export/ViewCSVExporter.swift && grep -qF '\"rows\": .int(table.rows.count)' $core/Export/ViewCSVExporter.swift"

# The toolbar (08 § Dashboard window): `Export…` → NSSavePanel → the page's table, as the page prints it (Q-053).
check "the Dashboard toolbar has Export… (U+2026)" bash -c "grep -qF 'Button(Strings.exportEllipsis, systemImage: \"square.and.arrow.up\")' $app/Dashboard/DashboardView.swift && grep -qF 'static let exportEllipsis = \"Export\\u{2026}\"' $app/Strings.swift"
check "the save panel suggests a .csv file" bash -c "grep -qF 'NSSavePanel()' $app/Dashboard/ViewExport.swift && grep -qF 'allowedContentTypes = [.commaSeparatedText]' $app/Dashboard/ViewExport.swift"
check "each page exports its table: runway board, By app (with its filter), apps" bash -c "grep -qF 'RunwayBoard.csvTable(model.accounts' $app/Dashboard/ViewExport.swift && grep -qF 'ByAppTable.csvTable(summary, filter: shownFilter' $app/Dashboard/ViewExport.swift && grep -qF 'AppsPage.csvTable(model)' $app/Dashboard/ViewExport.swift"
check "the view and the CSV draw from one cell function (the screen and the file agree)" bash -c "grep -qF 'let cells = Self.cells(summary, hideCents: hideCents, now: Date())' $app/Dashboard/RunwayBoard.swift && grep -qF 'let cells = Self.cells(row, currency: summary.currency, hideCents: hideCents)' $app/Dashboard/ByAppTable.swift && grep -qF 'keys: Self.keys(of: app, model: model)' $app/Dashboard/AppsPage.swift"
check "a failed write is logged (ui.error) and shown" bash -c "grep -qF 'Log.error(.uiError, cat: .ui, msg: \"view export failed\"' $app/Dashboard/ViewExport.swift && grep -qF 'NSAlert(error: error)' $app/Dashboard/ViewExport.swift"
check "the UI test cancels the save panel, never saves (no file in the owner's folders)" bash -c "grep -qF 'sheet.buttons[\"Cancel\"].click()' Tests/TokenBeUITests/DrilldownUITests.swift && ! grep -nE 'buttons\\[\"Save\"\\]' Tests/TokenBeUITests/*.swift"

check "suite CSVExporterTests passed" suite_passed CSVExporterTests
check "the app and UI tests compile (build-for-testing)" scripts/run.sh build-uitest
ui_check "DrilldownUITests passed (Export… opens the save panel for the filtered table)" grep -q "Test Suite 'DrilldownUITests' passed" "$(ls -t build/logs/uitest-*.log | head -n 1)"
check "the owner's real support folder is unchanged (D10)" real_support_unchanged
check "no TokenBe settings changed in the owner's real domain" real_tb_unchanged
