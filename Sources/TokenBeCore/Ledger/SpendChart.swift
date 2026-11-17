import Foundation

/// One account's spend on one UTC day: one segment of a stacked bar in the Overview's `Spend by day` chart (08 § 3).
public struct ChartSegment: Sendable, Equatable, Identifiable {
  public var day: String
  public var accountId: String
  public var label: String
  /// The account's place in the sidebar, modulo the 8-step palette (O-3).
  public var colorIndex: Int
  public var figure: SpendFigure

  public var id: String { "\(day) \(accountId)" }

  public init(day: String, accountId: String, label: String, colorIndex: Int, figure: SpendFigure) {
    self.day = day
    self.accountId = accountId
    self.label = label
    self.colorIndex = colorIndex
    self.figure = figure
  }
}

/// An account in the chart's legend.
public struct ChartAccount: Sendable, Equatable, Identifiable {
  public var id: String
  public var label: String
  public var colorIndex: Int

  public init(id: String, label: String, colorIndex: Int) {
    self.id = id
    self.label = label
    self.colorIndex = colorIndex
  }
}

/// The `Spend by day` chart over the Dashboard range: USD accounts only, since a stacked money axis cannot add
/// currencies and nothing is converted (05 § Currency, Q-052).
public struct SpendChartData: Sendable, Equatable {
  /// The range's UTC days, oldest first: the x axis, days without spend included.
  public var days: [String]
  public var segments: [ChartSegment]
  /// Σ the day's segments (the tooltip's `Total`).
  public var dayTotals: [String: SpendFigure]
  public var accounts: [ChartAccount]
  /// Accounts in another currency that have spend in the range, left out of the chart (the caption says so).
  public var nonUSD: Int

  public var isEmpty: Bool { segments.isEmpty }

  /// The days that get an axis label: at most 8, evenly spaced, ending on today.
  public var axisDays: [String] {
    let step = max(1, (days.count + 7) / 8)
    return days.enumerated().filter { (days.count - 1 - $0.offset) % step == 0 }.map(\.element)
  }

  /// The segments of `day`, in sidebar order (the tooltip's rows).
  public func segments(on day: String) -> [ChartSegment] {
    segments.filter { $0.day == day }
  }
}

/// 08 § Overview 3 (14 § Stage 8.2): each USD account's `dailySpend` (05's daily rule, the same that sums to
/// `rangeSpend`), stacked per day in sidebar order.
public enum SpendChart {
  public static let paletteSize = 8

  public static func data(_ accounts: [AccountSummary]) -> SpendChartData {
    let days = accounts.lazy.map(\.rangeDays).first { !$0.isEmpty } ?? []
    var segments: [ChartSegment] = []
    var totals: [String: SpendFigure] = [:]
    var legend: [ChartAccount] = []
    var nonUSD = 0
    for (index, account) in accounts.enumerated() {
      let spent = days.compactMap { day in account.dailySpend[day].map { (day, $0) } }.filter { $0.1.cents != 0 }
      guard !spent.isEmpty else { continue }
      guard account.currency == .usd else {
        nonUSD += 1
        continue
      }
      let color = index % paletteSize
      legend.append(ChartAccount(id: account.id, label: account.label, colorIndex: color))
      for (day, figure) in spent {
        segments.append(ChartSegment(day: day, accountId: account.id, label: account.label, colorIndex: color,
                                     figure: figure))
        totals[day] = Spend.sum([totals[day], figure].compactMap { $0 })
      }
    }
    return SpendChartData(days: days, segments: segments, dayTotals: totals, accounts: legend, nonUSD: nonUSD)
  }
}
