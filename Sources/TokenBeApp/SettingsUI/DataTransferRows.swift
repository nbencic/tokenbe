import AppKit
import SwiftUI
import TokenBeCore
import UniformTypeIdentifiers

/// Advanced → `Export data (JSON)…`, `Import…`, `Export CSV (all tables)…` (08 § Settings, 03 § Durability, O-5, O-17;
/// 14 § Stage 9.2), after `Back up now`. Each asks where in a panel, runs Core's exporter or importer (which log
/// `db.export`, `db.import`, `db.import_failed`) and reports in the maintenance sheet. An import goes only into an empty
/// database; otherwise the sheet explains how to get one (Q-056).
struct DataTransferRows: View {
  let repository: any Repository
  @State private var running = false
  @State private var report: MaintenanceReport?

  var body: some View {
    Button(Strings.exportDataJSON) { run(exportJSON) }
      .disabled(running)
      .accessibilityIdentifier("settings.advanced.exportJSON")
    Button(Strings.importData) { run(importJSON) }
      .disabled(running)
      .accessibilityIdentifier("settings.advanced.import")
    Button(Strings.exportCSVAllTables) { run(exportCSV) }
      .disabled(running)
      .accessibilityIdentifier("settings.advanced.exportCSV")
      .sheet(item: $report) { report in
        MaintenanceReportSheet(report: report) { self.report = nil }
      }
  }

  /// Runs one action; a cancelled panel reports nothing.
  private func run(_ action: @escaping @MainActor () async -> MaintenanceReport?) {
    running = true
    Task {
      report = await action()
      running = false
    }
  }

  private func exportJSON() async -> MaintenanceReport? {
    guard let url = DataTransferPanels.save(name: JSONExporter.fileName(date: DailyOnce.utcDay(Date())),
                                            types: [.json]) else { return nil }
    do {
      let rows = try await JSONExporter.export(from: repository, to: url)
      return MaintenanceReport(title: Strings.exportSavedTitle, lines: [Strings.rowsCount(rows), url.path])
    } catch {
      Log.error(.uiError, cat: .ui, msg: "data export failed", err: error, ctx: ["view": "settings.advanced"])
      return MaintenanceReport(title: Strings.exportFailedTitle, lines: [error.localizedDescription])
    }
  }

  private func exportCSV() async -> MaintenanceReport? {
    guard let folder = DataTransferPanels.save(name: TablesCSVExporter.folderName(date: DailyOnce.utcDay(Date())),
                                               types: []) else { return nil }
    do {
      let rows = try await TablesCSVExporter.export(from: repository, to: folder)
      return MaintenanceReport(title: Strings.exportSavedTitle, lines: [Strings.rowsCount(rows), folder.path])
    } catch {
      Log.error(.uiError, cat: .ui, msg: "tables export failed", err: error, ctx: ["view": "settings.advanced"])
      return MaintenanceReport(title: Strings.exportFailedTitle, lines: [error.localizedDescription])
    }
  }

  /// `JSONImporter` logs the outcome (`db.import` / `db.import_failed`); the sheet says what happened.
  private func importJSON() async -> MaintenanceReport? {
    guard let url = DataTransferPanels.open(types: [.json]) else { return nil }
    do {
      let rows = try await JSONImporter.run(url, into: repository)
      return MaintenanceReport(title: Strings.importDoneTitle, lines: [Strings.rowsCount(rows), url.path])
    } catch ImportRefusal.notEmpty {
      return MaintenanceReport(title: Strings.importNotEmptyTitle, lines: [Strings.importNotEmptyDetail])
    } catch ImportRefusal.schemaVersion(let found, let expected) {
      return MaintenanceReport(title: Strings.importFailedTitle,
                               lines: [Strings.importSchemaVersion(found: found, expected: expected)])
    } catch {
      return MaintenanceReport(title: Strings.importFailedTitle, lines: [error.localizedDescription])
    }
  }
}

/// The panels of the data rows. A DEBUG UI test under `TOKENBE_TEST_ROOT` sets `TOKENBE_TEST_EXPORT_DIR`: the rows
/// then use that folder (the suggested name to save, the newest `.json` to import) and open no panel, so a test never
/// writes into the owner's folders (Q-056).
@MainActor
enum DataTransferPanels {
  static let directoryVariable = "TOKENBE_TEST_EXPORT_DIR"

  /// Where to save `name`; nil when cancelled.
  static func save(name: String, types: [UTType]) -> URL? {
    if let directory = testDirectory { return directory.appendingPathComponent(name) }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    if !types.isEmpty { panel.allowedContentTypes = types }
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
  }

  /// The file to read; nil when cancelled.
  static func open(types: [UTType]) -> URL? {
    if let directory = testDirectory {
      let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
      return files.max { $0.lastPathComponent < $1.lastPathComponent }
    }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
  }

  private static var testDirectory: URL? {
    #if DEBUG
    let environment = ProcessInfo.processInfo.environment
    guard environment[Startup.testRootVariable] != nil, let path = environment[directoryVariable] else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
    #else
    return nil
    #endif
  }
}
