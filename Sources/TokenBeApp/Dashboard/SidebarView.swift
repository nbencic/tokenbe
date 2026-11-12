import SwiftUI

import TokenBeCore

/// 08 § Dashboard window sidebar: `Overview`, then one row per account (glyph, label, band dot; 3.5), each opening
/// its account page (4.2); `Apps` follows in 7.1. A row whose key is missing reads `Key missing` (14 § Stage 4.2).
struct SidebarView: View {
  enum Item: Hashable {
    case overview
    case account(String)
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
          VStack(alignment: .leading, spacing: 1) {
            Text(account.label)
            if account.needsKey {
              Text(Strings.keyMissing)
                .font(.caption)
                .foregroundStyle(Color(.healthLow))
            }
          }
          Spacer()
          BandDot(band: account.band)
        }
        .tag(Item.account(account.id))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.sidebar.account.\(account.provider.rawValue)")
      }
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    .accessibilityIdentifier("dashboard.sidebar")
  }
}
