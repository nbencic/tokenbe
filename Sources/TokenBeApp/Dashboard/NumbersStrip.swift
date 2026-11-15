import SwiftUI
import TokenBeCore

/// 08 § Account detail 3, the numbers strip (14 § Stage 5.2 step 4): `Spend today`, `Spend in range` and, only when
/// the range has unpriced usage, `Unpriced in range` in `HealthWatch`. Remaining, runway and burn arrive in 5.3.
/// Core computes every figure (04 I3); this view only formats them.
struct NumbersStrip: View {
  let summary: AccountSummary
  let hideCents: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 32) {
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
