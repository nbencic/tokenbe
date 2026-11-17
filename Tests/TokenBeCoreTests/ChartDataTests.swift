import Foundation
import Testing
@testable import TokenBeCore

/// 11 `ChartDataTests` (14 § Stage 8.2): the Overview's `Spend by day` stacks sum to the totals: each account's
/// segments to its `rangeSpend`, each day's segments to the day's total. USD accounts only (Q-052), sidebar order,
/// the O-3 palette's 8 steps, the x axis.
@Suite struct ChartDataTests {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00Z

  static func record(_ id: String, provider: String, currency: String = "USD") -> AccountRecord {
    var record = FixtureDBBuilder.account(id: id, provider: provider, label: id.capitalized)
    record.currency = currency
    return record
  }

  /// `a` (OpenAI, cost API): a truth day and estimates; `b`: estimates only; `c` (CN¥) and `quiet` (no spend).
  static var inputs: SummaryInputs {
    var inputs = SummaryInputs(accounts: [record("a", provider: "openai"), record("b", provider: "anthropic"),
                                          record("c", provider: "deepseek", currency: "CNY"),
                                          record("quiet", provider: "xai")])
    inputs.pollStates = ["a", "b", "c", "quiet"].map {
      PollStateSummary(accountId: $0, job: "usage", lastSuccessAt: "2026-11-10T11:59:00.000Z")
    }
    inputs.usageDays = [
      UsageDay(accountId: "a", day: "2026-11-08", source: "provider", estCents: 999),
      UsageDay(accountId: "a", day: "2026-11-09", source: "provider", estCents: 120),
      UsageDay(accountId: "a", day: "2026-11-10", source: "provider", estCents: 45),
      UsageDay(accountId: "a", day: "2026-10-01", source: "provider", estCents: 5_000),
      UsageDay(accountId: "b", day: "2026-11-09", source: "provider", estCents: 80),
      UsageDay(accountId: "b", day: "2026-11-10", source: "provider", estCents: 0),
      UsageDay(accountId: "c", day: "2026-11-09", source: "provider", estCents: 300)
    ]
    inputs.costDays = [CostDay(accountId: "a", day: "2026-11-08", amountCents: 1_000)]
    return inputs
  }

  static func summaries(_ range: DashboardRange = .sevenDays) -> [AccountSummary] {
    AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: range, now: now))
  }

  @Test("each account's segments sum to its rangeSpend; each day's to the day's total")
  func stacksSumToTotals() throws {
    for range in DashboardRange.allCases {
      let accounts = Self.summaries(range)
      let chart = SpendChart.data(accounts)
      for account in accounts where account.currency == .usd {
        let cents = chart.segments.filter { $0.accountId == account.id }.reduce(Int64(0)) { $0 + $1.figure.cents }
        #expect(cents == (account.rangeSpend?.cents ?? 0), "\(account.id) over \(range)")
      }
      for day in chart.days {
        let cents = chart.segments(on: day).reduce(Int64(0)) { $0 + $1.figure.cents }
        #expect(cents == (chart.dayTotals[day]?.cents ?? 0), "\(day) over \(range)")
      }
    }
  }

  @Test("the 7 d stacks: truth on a closed day with a cost row, ≈ on estimates, zero days and other currencies left out")
  func sevenDays() {
    let chart = SpendChart.data(Self.summaries())
    #expect(chart.days.count == 7 && chart.days.first == "2026-11-04" && chart.days.last == "2026-11-10")
    #expect(chart.segments.map(\.id) == ["2026-11-08 a", "2026-11-09 a", "2026-11-10 a", "2026-11-09 b"])
    #expect(chart.segments.first?.figure == SpendFigure(cents: 1_000, isEstimate: false), "the provider's cost")
    #expect(chart.dayTotals["2026-11-09"] == SpendFigure(cents: 200, isEstimate: true))
    #expect(chart.dayTotals["2026-11-10"] == SpendFigure(cents: 45, isEstimate: true), "b's $0 day adds no segment")
    #expect(chart.segments(on: "2026-11-09").map(\.label) == ["A", "B"], "sidebar order")
    #expect(chart.accounts.map(\.id) == ["a", "b"], "the legend: USD accounts with spend")
    #expect(chart.nonUSD == 1, "c's CN¥ spend is not stacked on dollars; quiet has no spend")
    #expect(!chart.isEmpty)
  }

  @Test("no spend in the range is the empty state; the axis still has the range's days")
  func empty() {
    var inputs = Self.inputs
    inputs.usageDays = []
    inputs.costDays = []
    let chart = SpendChart.data(AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: Self.now)))
    #expect(chart.isEmpty && chart.nonUSD == 0 && chart.days.count == 7)
    #expect(SpendChart.data([]).days.isEmpty)
  }

  @Test("colors follow the sidebar's order and cycle after O-3's 8 steps")
  func palette() {
    let accounts = (0..<10).map { index in
      var summary = AccountSummary(id: "id\(index)", provider: .openai, label: "L\(index)", mode: .anchored,
                                   currency: .usd)
      summary.rangeDays = ["2026-11-10"]
      summary.dailySpend = ["2026-11-10": SpendFigure(cents: 1, isEstimate: true)]
      return summary
    }
    #expect(SpendChart.data(accounts).segments.map(\.colorIndex) == [0, 1, 2, 3, 4, 5, 6, 7, 0, 1])
  }

  @Test("at most 8 axis labels, evenly spaced, ending on today")
  func axisDays() {
    let week = SpendChart.data(Self.summaries(.sevenDays))
    #expect(week.axisDays == week.days)
    let month = SpendChart.data(Self.summaries(.thirtyDays))
    #expect(month.axisDays.count <= 8 && month.axisDays.last == "2026-11-10")
    let quarter = SpendChart.data(Self.summaries(.ninetyDays))
    #expect(quarter.axisDays.count <= 8 && quarter.axisDays.last == "2026-11-10")
    #expect(SpendChart.data(Self.summaries(.today)).axisDays == ["2026-11-10"])
  }
}
