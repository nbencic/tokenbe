import SwiftUI
import TokenBeCore

/// One account card (08 § Popover 3). Stage 1.1 renders row 1 (label, mode chip, band dot) and the
/// "No data yet" state; rows 2–4 fill in as the data exists (Phases 3–7).
struct AccountCardView: View {
  let summary: AccountSummary
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(summary.label)
          .font(.headline)
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).label")
        if let chip = modeChip {
          Text(chip)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Circle()
          .fill(bandColor)
          .frame(width: 8, height: 8)
          .accessibilityLabel(Strings.bandLabel(summary.band.word))
          .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).band")
      }
      Text(remainingText)
        .font(.system(size: 20, weight: .semibold).monospacedDigit())
        .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).remaining")
      Text(Formatters.freshness(summary.lastSuccessAt, now: Date(), calendar: .current, stale: summary.isStale))
        .font(.caption.monospacedDigit())
        .foregroundStyle(summary.isStale ? Color(.healthLow) : Color.secondary)
        .accessibilityIdentifier("popover.card.\(summary.provider.rawValue).freshness")
    }
    .padding(12)
    .background(Color(.ground), in: RoundedRectangle(cornerRadius: 8))
    .opacity(summary.isStale ? 0.6 : 1)
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

  private var remainingText: String {
    guard let cents = summary.remainingCents else { return Strings.noDataYet }
    return Formatters.remaining(
      Money(cents: cents, currency: summary.currency),
      hideCents: environment?.settings.uiHideCents ?? true, locale: .current
    )
  }

  private var bandColor: Color {
    switch summary.band {
    case .healthy: Color(.healthHealthy)
    case .watch: Color(.healthWatch)
    case .low: Color(.healthLow)
    case .critical: Color(.healthCritical)
    case .unknown: Color(.healthUnknown)
    }
  }
}
