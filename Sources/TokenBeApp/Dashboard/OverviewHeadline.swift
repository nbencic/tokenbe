import SwiftUI
import TokenBeCore

/// 08 § Overview 1 (`Q1-0`, `Q2-0`): `Shortest runway: Anthropic · ~1 d` in the band colour, then
/// `Total remaining ≈ $312 ± 9 across 3 USD accounts + 1 non-USD` (05 § Currency) and 5.2's `Total spend` line.
struct OverviewHeadline: View {
  let accounts: [AccountSummary]
  let hideCents: Bool
  let totalSpend: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let shortest = OverviewTotals.shortest(accounts), let runway = Formatters.runway(shortest.runwayMin) {
        Text(Strings.shortestRunway(shortest.label, runway))
          .font(.title2.weight(.semibold).monospacedDigit())
          .foregroundStyle(shortest.band.color)
          .accessibilityIdentifier("dashboard.overview.headline")
      }
      let total = OverviewTotals.remaining(accounts)
      if total.usdAccounts > 0 {
        Text(Strings.totalRemaining(
          Formatters.estimate(Money(cents: total.cents), bandCents: total.bandCents, hideCents: hideCents,
                              locale: .current),
          usdAccounts: total.usdAccounts, nonUSD: total.nonUSD
        ))
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("dashboard.overview.totalRemaining")
      }
      Text(totalSpend)
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("dashboard.overview.totalSpend")
    }
  }
}
