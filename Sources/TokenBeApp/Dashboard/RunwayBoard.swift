import SwiftUI
import TokenBeCore

/// 08 § Overview 2 (`QD-0`, `QW-0`, `RE-0`, `RW-0`): one row per account — Account | Remaining (`≈` and ±) | Runway
/// (two paces, 176 pt) | Burn 7 d/day | Today | Freshness (124 pt) | Band dot — sorted by runway ascending, `unknown`
/// last, with `Set anchor…` in the Runway cell of an anchored account without an anchor.
struct RunwayBoard: View {
  let model: AppModel
  let hideCents: Bool
  let setAnchor: (AccountSummary) -> Void

  var body: some View {
    let rows = AccountOrder.sorted(model.accounts, by: .runway, manualOrder: [])
    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
      GridRow {
        ForEach([Strings.boardAccount, Strings.boardRemaining, Strings.boardRunway, Strings.boardBurn,
                 Strings.boardToday, Strings.boardFreshness, Strings.boardBand], id: \.self) { title in
          Text(title).font(.caption).foregroundStyle(.secondary)
        }
      }
      Divider()
      ForEach(rows) { summary in
        row(summary)
      }
    }
    .padding(16)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.runwayBoard")
  }

  private func money(_ cents: Int64, _ currency: Currency) -> String {
    Formatters.money(Money(cents: cents, currency: currency), hideCents: hideCents, locale: .current)
  }

  private func row(_ summary: AccountSummary) -> some View {
    GridRow {
      HStack(spacing: 6) {
        ProviderGlyph(provider: summary.provider, size: 14)
        Text(summary.label)
      }
      Text(remaining(summary)).monospacedDigit()
      Group {
        if summary.band == .unknown, summary.needsAnchor {
          Button(Strings.setAnchor) { setAnchor(summary) }
            .buttonStyle(.link)
            .accessibilityIdentifier("dashboard.runwayBoard.\(summary.provider.rawValue).setAnchor")
        } else {
          Text(runway(summary)).monospacedDigit()
        }
      }
      .frame(width: 176, alignment: .leading)
      Text(summary.burn7dCents.map { money($0, summary.currency) } ?? "\u{2014}").monospacedDigit()
      Text(summary.todaySpend.map {
        Formatters.spend($0, currency: summary.currency, hideCents: hideCents, locale: .current)
      } ?? "\u{2014}").monospacedDigit()
      Text(Formatters.freshness(summary.lastSuccessAt, now: Date(), calendar: .current, stale: summary.isStale))
        .monospacedDigit()
        .foregroundStyle(summary.isStale ? Color(.healthLow) : Color.secondary)
        .frame(width: 124, alignment: .leading)
      BandDot(band: summary.band)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("dashboard.runwayBoard.\(summary.provider.rawValue)")
  }

  private func remaining(_ summary: AccountSummary) -> String {
    guard let cents = summary.remainingCents else { return "\u{2014}" }
    let amount = Money(cents: cents, currency: summary.currency)
    if summary.mode == .anchored, let band = summary.estimateBandCents {
      return Formatters.estimate(amount, bandCents: band, hideCents: hideCents, locale: .current)
    }
    return Formatters.remaining(amount, hideCents: hideCents, locale: .current)
  }

  private func runway(_ summary: AccountSummary) -> String {
    if summary.reloadPending, let reload = summary.autoReload {
      return Strings.reloadsAt(money(reload.belowCents, summary.currency))
    }
    if summary.burn7dCents == nil, summary.lastSuccessAt != nil, summary.mode != .spendOnly {
      return Strings.collecting
    }
    return Formatters.runwayPair(sevenDay: summary.runway7d, today: summary.runwayToday) ?? "\u{2014}"
  }
}
