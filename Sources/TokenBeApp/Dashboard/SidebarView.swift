import SwiftUI

/// 08 § Dashboard window sidebar. Stage 1.2: `Overview` only; account rows (3.5) and `Apps` (7.1) follow.
struct SidebarView: View {
  enum Item: Hashable {
    case overview
  }

  @Binding var selection: Item?

  var body: some View {
    List(selection: $selection) {
      Label(Strings.overview, systemImage: "gauge.with.dots.needle.33percent")
        .tag(Item.overview)
        .accessibilityIdentifier("dashboard.sidebar.overview")
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    .accessibilityIdentifier("dashboard.sidebar")
  }
}
