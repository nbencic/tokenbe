import SwiftUI
import TokenBeCore

/// One account card (08 § Popover 3). Row 1: label, mode chip, band dot. Row 2: the pinned metric
/// (09 `tb.popover.pinnedMetric`), or "No data yet". Row 3 and 4 fill in as the data exists (Phases 3–7).
/// The stale overlay (08: opacity 0.6, freshness `stale · 3 h ago` in `HealthLow`) covers a stale account, and every
/// card while offline, so the state is in the text too, not only in the opacity (08 § Accessibility). A click opens
/// the account's page in the Dashboard (08).
struct AccountCardView: View {
  let summary: AccountSummary
  /// Stale, or the Mac is offline (08 § Popover states).
  let dimmed: Bool
  /// `Key missing · Fix…` opens Settings → Accounts (08).
  let fixKey: () -> Void
  let open: () -> Void
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        ProviderGlyph(provider: summary.provider, size: 16)
        Text(summary.label)
          .font(.headline)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).label")
        if let chip = modeChip {
          Text(chip)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        BandDot(band: summary.band)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).band")
      }
      if summary.needsKey {
        Button(Strings.keyMissingFix, action: fixKey)
          .buttonStyle(.link)
          .font(.system(size: 13, weight: .semibold))
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).fixKey")
      } else {
        Text(pinnedText)
          .font(.system(size: 20, weight: .semibold).monospacedDigit())
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).pinned")
      }
      Text(Formatters.freshness(summary.lastSuccessAt, now: Date(), calendar: .current, stale: dimmed))
        .font(.caption.monospacedDigit())
        .foregroundStyle(dimmed ? Color(.healthLow) : Color.secondary)
        .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).freshness")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.ground), in: RoundedRectangle(cornerRadius: 8))
    .opacity(dimmed ? 0.6 : 1)
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture(perform: open)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("popover.card.\(summary.provider.rawValue)")
  }

  private var modeChip: String? {
    switch summary.mode {
    case .direct: nil
    case .anchored: Strings.modeAnchored
    case .spendOnly: Strings.modeSpendOnly
    }
  }

  /// Row 2 (09 `tb.popover.pinnedMetric`); a metric not known yet reads "No data yet".
  private var pinnedText: String {
    let hideCents = environment?.settings.uiHideCents ?? true
    switch environment?.settings.popoverPinnedMetric ?? "runway" {
    case "remaining":
      guard let cents = summary.remainingCents else { return Strings.noDataYet }
      return Formatters.remaining(Money(cents: cents, currency: summary.currency), hideCents: hideCents, locale: .current)
    case "todaySpend":
      guard let cents = summary.todaySpendCents else { return Strings.noDataYet }
      return Formatters.money(Money(cents: cents, currency: summary.currency), hideCents: hideCents, locale: .current)
    default:
      return Formatters.runwayPair(sevenDay: summary.runway7d, today: summary.runwayToday) ?? Strings.noDataYet
    }
  }
}
