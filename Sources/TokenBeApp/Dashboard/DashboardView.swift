import SwiftUI
import TokenBeCore

/// 08 § Dashboard window: `NavigationSplitView`, min 920×600, frame kept in `tb.ui.dashboardFrame`.
/// Stage 1.2: sidebar `Overview`, the range picker and the Overview empty state; 4.2: account pages and the
/// toolbar's `Refresh`; 7.1: the Apps page; 7.3: an Overview `Apps this period` row opens the account page filtered
/// by that app; 8.3: the toolbar's `Export…` (`ViewExport`).
struct DashboardView: View {
  static let windowID = "dashboard"
  static let minimumSize = CGSize(width: 920, height: 600)

  let model: AppModel
  @Environment(\.appEnvironment) private var environment
  /// The account page's app filter (7.3); cleared when the selection leaves its account.
  @State private var appFilter: AppFilter?

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      SidebarView(model: model, selection: $model.dashboardSelection)
    } detail: {
      if let account = selectedAccount {
        AccountDetailView(model: model, summary: account, filter: $appFilter)
      } else if model.dashboardSelection == .apps {
        AppsPage(model: model)
      } else {
        OverviewView(model: model) { total in drill(into: total) }
      }
    }
    .onChange(of: model.dashboardSelection) {
      if case .account(let id) = model.dashboardSelection, id == appFilter?.accountID { return }
      appFilter = nil
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        RangePicker(selection: rangeBinding)
      }
      ToolbarItem(placement: .primaryAction) {
        // 08 toolbar `Refresh`: the account shown, or every account on the Overview.
        Button(Strings.refresh, systemImage: "arrow.clockwise") { model.refreshNow(selectedAccount?.id) }
          .help(Strings.refresh)
          .accessibilityIdentifier("dashboard.toolbar.refresh")
      }
      ToolbarItem(placement: .primaryAction) {
        // 08 toolbar `Export…` (O-4): the page's table as CSV (8.3).
        Button(Strings.exportEllipsis, systemImage: "square.and.arrow.up") {
          ViewExport.run(ViewExport.plan(selection: model.dashboardSelection, model: model, filter: appFilter))
        }
        .help(Strings.exportHelp)
        .accessibilityIdentifier("dashboard.toolbar.export")
      }
    }
    .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    .background(WindowFrameKeeper(settings: environment?.settings, minimum: Self.minimumSize))
    .accessibilityIdentifier("dashboard.root")
  }

  /// 08 Overview 4 "row click → app filter in account detail": the account where the app spent most (Core, Q-050).
  private func drill(into total: AppTotal) {
    guard let account = Attribution.drilldownAccount(total, accounts: model.accounts) else { return }
    appFilter = AppFilter(accountID: account, appKey: total.row.appKey, label: Strings.appLabel(total.row))
    model.dashboardSelection = .account(account)
  }

  /// The selected account; nil on the Overview, or when the selected account was removed (back to the Overview).
  private var selectedAccount: AccountSummary? {
    guard case .account(let id) = model.dashboardSelection else { return nil }
    return model.accounts.first { $0.id == id }
  }

  /// `tb.ui.dashboardRange`, read and written through `Settings` (09 validates).
  private var rangeBinding: Binding<DashboardRange> {
    Binding(
      get: { DashboardRange(setting: environment?.settings.uiDashboardRange ?? DashboardRange.default.rawValue) },
      set: { environment?.settings.uiDashboardRange = $0.rawValue }
    )
  }
}
