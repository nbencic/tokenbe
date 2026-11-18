import SwiftUI

import TokenBeCore

/// 08 § Dashboard window sidebar: `Overview`, then one row per account (glyph, label, band dot; 3.5), each opening
/// its account page (4.2); then `Apps` (7.1), the Apps page. A row whose key is missing reads `Key missing` (14 § Stage
/// 4.2). At its foot, `+` / `−` in the macOS source-list style (14 § Stage 10.0.1, Q-060): `+` opens Add account,
/// `−` removes the selected account through `Remove account…`'s confirm.
struct SidebarView: View {
  enum Item: Hashable {
    case overview
    case account(String)
    case apps
  }

  let model: AppModel
  @Binding var selection: Item?
  @Environment(\.appEnvironment) private var environment
  @State private var confirmingRemove = false

  private var accounts: [AccountSummary] { model.accounts }

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
      Label(Strings.apps, systemImage: "square.stack.3d.up")
        .tag(Item.apps)
        .accessibilityIdentifier("dashboard.sidebar.apps")
    }
    .accessibilityIdentifier("dashboard.sidebar")
    .safeAreaInset(edge: .bottom, spacing: 0) { foot }
    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    .removeAccountConfirm(selectedRecord, isPresented: $confirmingRemove, model: model, environment: environment,
                          view: "dashboard.sidebar") { selection = .overview }
  }

  /// `+` and `−`: small borderless buttons under a divider, like a macOS source list's foot.
  private var foot: some View {
    VStack(spacing: 0) {
      Divider()
      HStack(spacing: 2) {
        Button { model.showOnboarding() } label: {
          Image(systemName: "plus").frame(width: 22, height: 20)
        }
        .disabled(!canAdd)
        .help(Strings.sidebarAddAccount)
        .accessibilityLabel(Strings.sidebarAddAccount)
        .accessibilityIdentifier("dashboard.sidebar.add")
        Button { confirmingRemove = true } label: {
          Image(systemName: "minus").frame(width: 22, height: 20)
        }
        .disabled(selectedRecord == nil)
        .help(Strings.sidebarRemoveAccount)
        .accessibilityLabel(Strings.sidebarRemoveAccount)
        .accessibilityIdentifier("dashboard.sidebar.remove")
        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
    }
  }

  /// `+` is off once every provider onboarding offers has an account (V1: one account per provider, 03).
  private var canAdd: Bool {
    let added = Set(accounts.map(\.provider))
    return environment?.registry.availableForOnboarding.contains { !added.contains($0) } ?? false
  }

  /// The selected account's row; nil on Overview and Apps, so `−` is off there.
  private var selectedRecord: AccountRecord? {
    guard case .account(let id) = selection else { return nil }
    return model.records.first { $0.id == id }
  }
}
