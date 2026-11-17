import AppKit
import TokenBeCore
import UniformTypeIdentifiers

/// The toolbar's `Export…` (08 § Dashboard window, O-4; 14 § Stage 8.3): the table of the page on screen, in its
/// current state, as RFC 4180 CSV (`ViewCSVExporter`) through a save panel.
/// - Overview: the runway board.
/// - Account page: the By-app table, under the app filter when one is set.
/// - Apps page: the apps list.
/// Each table's cells come from the function its view draws from, so the file says what the screen says (Q-053).
@MainActor
enum ViewExport {
  /// What `Export…` writes for a page, and the file name it suggests.
  struct Plan {
    let table: CSVTable
    let fileName: String
  }

  static func plan(selection: SidebarView.Item?, model: AppModel, filter: AppFilter?) -> Plan {
    let settings = model.environment?.settings
    let hideCents = settings?.uiHideCents ?? true
    let range = RangePicker.label(DashboardRange(setting: settings?.uiDashboardRange
                                                   ?? DashboardRange.default.rawValue))
    let date = DailyOnce.utcDay(Date())
    if case .account(let id) = selection, let summary = model.accounts.first(where: { $0.id == id }) {
      let shownFilter = filter?.accountID == id ? filter : nil
      let parts = [summary.label, Strings.byAppFile] + (shownFilter.map { [$0.label] } ?? []) + [range]
      return Plan(table: ByAppTable.csvTable(summary, filter: shownFilter, hideCents: hideCents),
                  fileName: ViewCSVExporter.fileName(parts, date: date))
    }
    if selection == .apps {
      return Plan(table: AppsPage.csvTable(model), fileName: ViewCSVExporter.fileName([Strings.apps], date: date))
    }
    return Plan(table: RunwayBoard.csvTable(model.accounts, hideCents: hideCents),
                fileName: ViewCSVExporter.fileName([Strings.overview, range], date: date))
  }

  /// Asks where to save, then writes; a failure is logged (`ui.error`) and shown in an alert.
  static func run(_ plan: Plan) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = plan.fileName
    panel.canCreateDirectories = true
    let save = { (response: NSApplication.ModalResponse) in
      guard response == .OK, let url = panel.url else { return }
      do {
        try ViewCSVExporter.write(plan.table, to: url)
      } catch {
        Log.error(.uiError, cat: .ui, msg: "view export failed", err: error, ctx: ["view": "export"])
        let alert = NSAlert(error: error)
        alert.messageText = Strings.exportFailed
        alert.runModal()
      }
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: save)
    } else {
      save(panel.runModal())
    }
  }
}
