import SwiftUI
import TokenBeCore

/// 08 § Dashboard window: `NavigationSplitView`, min 920×600, frame kept in `tb.ui.dashboardFrame`.
/// Stage 1.2: sidebar `Overview`, the range picker and the Overview empty state; 4.2: account pages and the
/// toolbar's `Refresh`. The CSV export (8.3) joins with its action.
struct DashboardView: View {
  static let windowID = "dashboard"
  static let minimumSize = CGSize(width: 920, height: 600)

  let model: AppModel
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      SidebarView(accounts: model.accounts, selection: $model.dashboardSelection)
    } detail: {
      if let account = selectedAccount {
        AccountDetailView(model: model, summary: account)
      } else {
        OverviewView(model: model)
      }
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
    }
    .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    .background(WindowFrameKeeper(settings: environment?.settings, minimum: Self.minimumSize))
    .accessibilityIdentifier("dashboard.root")
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
