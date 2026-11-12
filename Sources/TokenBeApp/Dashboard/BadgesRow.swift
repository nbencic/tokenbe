import SwiftUI
import TokenBeCore

/// 08 `B1-0`: `Balance: …` · `Usage: …` · `Cost: …` · `Lag: …`, each with a one-sentence help popover from 02.
/// Paper's chips: a capsule with a check where the provider reports the thing, an outlined cross where TokenBe
/// has to estimate or cannot know it.
struct BadgesRow: View {
  let provider: ProviderID
  let badges: AccountBadges

  var body: some View {
    HStack(spacing: 8) {
      Badge(id: "balance", text: Strings.badgeBalance(badges.balance.rawValue), reported: badges.balance == .direct,
            help: balanceHelp)
      Badge(id: "usage", text: Strings.badgeUsage(badges.usage.rawValue), reported: badges.usage != .harness,
            help: usageHelp)
      Badge(id: "cost", text: Strings.badgeCost(badges.cost.rawValue), reported: badges.cost == .provider,
            help: badges.cost == .provider ? Strings.helpCostProvider : Strings.helpCostEstimated)
      Badge(id: "lag", text: Strings.badgeLag(Formatters.interval(seconds: Int(badges.lag.components.seconds))),
            reported: true, help: Strings.helpLag(provider))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.account.badges")
  }

  private var balanceHelp: String {
    switch badges.balance {
    case .direct: Strings.helpBalanceDirect
    case .anchored: Strings.helpBalanceAnchored
    case .none: Strings.helpBalanceNone
    }
  }

  private var usageHelp: String {
    switch badges.usage {
    case .perKey: Strings.helpUsagePerKey
    case .orgOnly: Strings.helpUsageOrgOnly
    case .harness: Strings.helpUsageHarness
    }
  }
}

/// One badge; a click shows its help sentence.
private struct Badge: View {
  let id: String
  let text: String
  let reported: Bool
  let help: String
  @State private var showsHelp = false

  var body: some View {
    Button {
      showsHelp.toggle()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: reported ? "checkmark" : "xmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(reported ? .secondary : .tertiary)
        Text(text)
          .font(.caption.weight(.medium))
          .foregroundStyle(reported ? .primary : .secondary)
      }
      .padding(.horizontal, 10)
      .frame(height: 24)
      .background(reported ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear), in: Capsule())
      .overlay(Capsule().strokeBorder(.separator, lineWidth: reported ? 0 : 1))
    }
    .buttonStyle(.plain)
    .help(help)
    .popover(isPresented: $showsHelp, arrowEdge: .bottom) {
      Text(help)
        .font(.callout)
        .frame(width: 260, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .accessibilityIdentifier("dashboard.account.badge.\(id).help")
    }
    .accessibilityLabel(text)
    .accessibilityIdentifier("dashboard.account.badge.\(id)")
  }
}
