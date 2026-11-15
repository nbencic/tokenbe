import SwiftUI
import TokenBeCore

/// 08 § Account detail 3, the numbers strip: Remaining (with ±), Runway (two paces), Burn 7 d (5.3), `Spend today`,
/// `Spend in range` and, only when the range has unpriced usage, `Unpriced in range` in `HealthWatch` (5.2).
/// Core computes every figure (04 I3); this view only formats them. Spend-only accounts have no remaining or runway.
struct NumbersStrip: View {
  let summary: AccountSummary
  let hideCents: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 28) {
      if summary.mode != .spendOnly {
        cell(Strings.remaining, value: remaining ?? Strings.noDataYet, id: "remaining")
        cell(Strings.runway, value: runway ?? Strings.noDataYet, id: "runway")
        cell(Strings.burn7d, value: summary.burn7dCents.map { Strings.perDay(money($0)) } ?? "\u{2014}", id: "burn7d")
      }
      cell(Strings.spendToday, value: summary.todaySpend.map(spend) ?? Strings.noDataYet, id: "todaySpend")
      cell(Strings.spendInRange, value: summary.rangeSpend.map(spend) ?? Strings.noDataYet, id: "rangeSpend")
      if let unpriced = summary.unpriced, unpriced.tokens > 0 {
        cell(Strings.unpricedInRange,
             value: Formatters.unpriced(unpriced, currency: summary.currency, hideCents: hideCents, locale: .current),
             id: "unpriced", tint: Color(.healthWatch))
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.account.numbers")
  }

  private func money(_ cents: Int64) -> String {
    Formatters.money(Money(cents: cents, currency: summary.currency), hideCents: hideCents, locale: .current)
  }

  private var remaining: String? {
    guard let cents = summary.remainingCents else { return nil }
    let amount = Money(cents: cents, currency: summary.currency)
    if summary.mode == .anchored, let band = summary.estimateBandCents {
      return Formatters.estimate(amount, bandCents: band, hideCents: hideCents, locale: .current)
    }
    return Formatters.remaining(amount, hideCents: hideCents, locale: .current)
  }

  private var runway: String? {
    if summary.reloadPending, let reload = summary.autoReload { return Strings.reloadsAt(money(reload.belowCents)) }
    if summary.burn7dCents == nil, summary.lastSuccessAt != nil, !summary.needsAnchor { return Strings.collecting }
    return Formatters.runwayPair(sevenDay: summary.runway7d, today: summary.runwayToday)
  }

  private func spend(_ figure: SpendFigure) -> String {
    Formatters.spend(figure, currency: summary.currency, hideCents: hideCents, locale: .current)
  }

  private func cell(_ label: String, value: String, id: String, tint: Color? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(tint ?? Color.secondary)
      Text(value)
        .font(.title3.weight(.semibold).monospacedDigit())
        .foregroundStyle(tint ?? Color.primary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("dashboard.account.numbers.\(id)")
  }
}
