import SwiftUI

import TokenBeCore

/// 08 § Dashboard window sidebar: `Overview`, then one row per account (glyph, label, band dot; 3.5); `Apps` follows
/// in 7.1. Account rows are not selectable until the account detail exists (5.x), so no row leads nowhere (D6).
struct SidebarView: View {
  enum Item: Hashable {
    case overview
  }

  let accounts: [AccountSummary]
  @Binding var selection: Item?

  var body: some View {
    List(selection: $selection) {
      Label(Strings.overview, systemImage: "gauge.with.dots.needle.33percent")
        .tag(Item.overview)
        .accessibilityIdentifier("dashboard.sidebar.overview")
      ForEach(accounts) { account in
        HStack(spacing: 8) {
          ProviderGlyph(provider: account.provider, size: 18)
          Text(account.label)
          Spacer()
          Circle()
            .fill(Color(.healthUnknown))
            .frame(width: 8, height: 8)
            .accessibilityLabel(Strings.bandLabel(account.band.word))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.sidebar.account.\(account.provider.rawValue)")
      }
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    .accessibilityIdentifier("dashboard.sidebar")
  }
}
