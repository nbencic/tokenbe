import SwiftUI
import TokenBeCore

/// 08 § Dashboard window: `NavigationSplitView`, min 920×600, frame kept in `tb.ui.dashboardFrame`.
/// Stage 1.2: sidebar `Overview`, the range picker and the Overview empty state. The refresh (4.1) and
/// CSV-export (8.3) toolbar buttons join with their actions.
struct DashboardView: View {
  static let windowID = "dashboard"
  static let minimumSize = CGSize(width: 920, height: 600)

  let model: AppModel
  @Environment(\.appEnvironment) private var environment
  @State private var selection: SidebarView.Item? = .overview

  var body: some View {
    NavigationSplitView {
      SidebarView(accounts: model.accounts, selection: $selection)
    } detail: {
      OverviewView(model: model)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        RangePicker(selection: rangeBinding)
      }
    }
    .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    .background(WindowFrameKeeper(settings: environment?.settings, minimum: Self.minimumSize))
    .accessibilityIdentifier("dashboard.root")
  }

  /// `tb.ui.dashboardRange`, read and written through `Settings` (09 validates).
  private var rangeBinding: Binding<DashboardRange> {
    Binding(
      get: { DashboardRange(setting: environment?.settings.uiDashboardRange ?? DashboardRange.default.rawValue) },
      set: { environment?.settings.uiDashboardRange = $0.rawValue }
    )
  }
}
