import SwiftUI
import TokenBeCore

/// Advanced → `Export diagnostics…` (08 § Settings, 07 § Diagnostics bundle; 14 § Stage 9.3), between `Log retention`
/// and `Open log folder`. A save panel (or the DEBUG test folder, `DataTransferPanels`) names the zip; Core builds it
/// (`DiagnosticsBundle`, which logs `app.diagnostics_exported`), and the maintenance sheet reports its size and path.
struct DiagnosticsExportButton: View {
  let settings: TokenBeCore.Settings
  let logsDirectory: URL
  let repository: any Repository
  @State private var running = false
  @State private var report: MaintenanceReport?

  var body: some View {
    Button(Strings.exportDiagnostics) {
      running = true
      Task {
        report = await export()
        running = false
      }
    }
    .disabled(running)
    .sheet(item: $report) { report in
      MaintenanceReportSheet(report: report) { self.report = nil }
    }
  }

  /// Nil when the panel was cancelled.
  private func export() async -> MaintenanceReport? {
    guard let url = DataTransferPanels.save(name: DiagnosticsBundle.fileName(Date()), types: [.zip]) else { return nil }
    let inputs = DiagnosticsInputs(
      logsDirectory: logsDirectory, breadcrumbs: Log.breadcrumbs.snapshot(), settings: settings.diagnosticsValues(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
    do {
      let result = try await DiagnosticsBundle.export(store: repository, inputs: inputs, to: url)
      let size = Int64(result.bytes).formatted(.byteCount(style: .file))
      return MaintenanceReport(title: Strings.diagnosticsSavedTitle,
                               lines: [Strings.diagnosticsDetail(files: result.files.count, size: size), url.path])
    } catch {
      Log.error(.uiError, cat: .ui, msg: "diagnostics export failed", err: error, ctx: ["view": "settings.advanced"])
      return MaintenanceReport(title: Strings.diagnosticsFailedTitle, lines: [error.localizedDescription])
    }
  }
}
