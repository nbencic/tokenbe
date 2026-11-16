import SwiftUI
import TokenBeCore

/// 06 precedence 2's drift chip on the account page (14 § Stage 7.3), beside the band pill: the newest closed day in
/// the range whose harness spend drifted from the balance delta by more than `tb.alerts.driftThresholdPct`
/// (`AccountSummary.harnessDrift`, Core), `Harness drift · Nov 14 · −$4.02`, with ` · 3 days` when more days drifted.
/// Its help names both figures. In `HealthWatch`: drift is a data-quality hint, not a band (Q-050).
struct DriftChip: View {
  let drift: [HarnessDrift]
  let currency: Currency
  let hideCents: Bool

  var body: some View {
    if let newest = drift.first {
      let day = Formatters.day(newest.day)
      Text(Strings.harnessDrift(day: day, amount: money(newest.deltaCents, signed: true), days: drift.count))
        .font(.callout.weight(.medium).monospacedDigit())
        .foregroundStyle(Color(.healthWatch))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color(.healthWatch).opacity(0.12), in: Capsule())
        .help(Strings.harnessDriftHelp(day: day, harness: money(newest.harnessCents, signed: false),
                                       balance: money(newest.balanceCents, signed: false)))
        .accessibilityIdentifier("dashboard.account.drift")
    }
  }

  private func money(_ cents: Int64, signed: Bool) -> String {
    let amount = Money(cents: cents, currency: currency)
    return signed ? Formatters.signedMoney(amount, hideCents: hideCents, locale: .current)
      : Formatters.money(amount, hideCents: hideCents, locale: .current)
  }
}
