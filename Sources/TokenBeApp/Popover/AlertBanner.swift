import SwiftUI
import TokenBeCore

/// 08 § Popover 2: one line, at most 60 characters, on the band colour at 12 %, shown while any account is `low` or
/// `critical`, or anchored without an anchor. Tapping it opens that account's page. `AlertBannerPick` (Core) picks the
/// account.
struct AlertBanner: View {
  let account: AccountSummary
  let kind: AlertBannerPick.Kind
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      Text(text)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(account.band.color.opacity(0.12))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(text)
    .accessibilityIdentifier("popover.banner.alert")
  }

  private var text: String {
    switch kind {
    case .runway(let runway): AlertBannerPick.fit(label: account.label, rest: Strings.bannerRunway(runway))
    case .setAnchor: AlertBannerPick.fit(label: account.label, rest: Strings.bannerSetAnchor)
    }
  }
}
