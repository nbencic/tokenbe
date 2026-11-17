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
    let rows = Self.order(model.accounts)
    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
      GridRow {
        ForEach(Self.columns, id: \.self) { title in
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

  /// 08's columns; the band dot's column exports the band's word.
  static let columns = [Strings.boardAccount, Strings.boardRemaining, Strings.boardRunway, Strings.boardBurn,
                        Strings.boardToday, Strings.boardFreshness, Strings.boardBand]

  /// Runway ascending, `unknown` last (08).
  static func order(_ accounts: [AccountSummary]) -> [AccountSummary] {
    AccountOrder.sorted(accounts, by: .runway, manualOrder: [])
  }

  /// One row's cells, as the board prints them; the CSV export (8.3) writes the same strings (Q-053).
  static func cells(_ summary: AccountSummary, hideCents: Bool, now: Date) -> [String] {
    let money = { (cents: Int64) in
      Formatters.money(Money(cents: cents, currency: summary.currency), hideCents: hideCents, locale: .current)
    }
    let runway = summary.band == .unknown && summary.needsAnchor ? Strings.setAnchor
      : runway(summary, money: money)
    return [
      summary.label, remaining(summary, hideCents: hideCents), runway,
      summary.burn7dCents.map(money) ?? "\u{2014}",
      summary.todaySpend.map {
        Formatters.spend($0, currency: summary.currency, hideCents: hideCents, locale: .current)
      } ?? "\u{2014}",
      Formatters.freshness(summary.lastSuccessAt, now: now, calendar: .current, stale: summary.isStale),
      summary.band.word
    ]
  }

  /// The board as the Overview's `Export…` writes it (8.3).
  static func csvTable(_ accounts: [AccountSummary], hideCents: Bool, now: Date = Date()) -> CSVTable {
    CSVTable(header: columns, rows: order(accounts).map { cells($0, hideCents: hideCents, now: now) })
  }

  private func row(_ summary: AccountSummary) -> some View {
    let cells = Self.cells(summary, hideCents: hideCents, now: Date())
    return GridRow {
      HStack(spacing: 6) {
        ProviderGlyph(provider: summary.provider, size: 14)
        Text(cells[0])
      }
      Text(cells[1]).monospacedDigit()
      Group {
        if summary.band == .unknown, summary.needsAnchor {
          Button(cells[2]) { setAnchor(summary) }
            .buttonStyle(.link)
            .accessibilityIdentifier("dashboard.runwayBoard.\(summary.provider.rawValue).setAnchor")
        } else {
          Text(cells[2]).monospacedDigit()
        }
      }
      .frame(width: 176, alignment: .leading)
      Text(cells[3]).monospacedDigit()
      Text(cells[4]).monospacedDigit()
      Text(cells[5])
        .monospacedDigit()
        .foregroundStyle(summary.isStale ? Color(.healthLow) : Color.secondary)
        .frame(width: 124, alignment: .leading)
      BandDot(band: summary.band)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("dashboard.runwayBoard.\(summary.provider.rawValue)")
  }

  private static func remaining(_ summary: AccountSummary, hideCents: Bool) -> String {
    guard let cents = summary.remainingCents else { return "\u{2014}" }
    let amount = Money(cents: cents, currency: summary.currency)
    if summary.mode == .anchored, let band = summary.estimateBandCents {
      return Formatters.estimate(amount, bandCents: band, hideCents: hideCents, locale: .current)
    }
    return Formatters.remaining(amount, hideCents: hideCents, locale: .current)
  }

  private static func runway(_ summary: AccountSummary, money: (Int64) -> String) -> String {
    if summary.reloadPending, let reload = summary.autoReload {
      return Strings.reloadsAt(money(reload.belowCents))
    }
    if summary.burn7dCents == nil, summary.lastSuccessAt != nil, summary.mode != .spendOnly {
      return Strings.collecting
    }
    return Formatters.runwayPair(sevenDay: summary.runway7d, today: summary.runwayToday) ?? "\u{2014}"
  }
}
