import Foundation
import Testing
@testable import TokenBeCore

/// 05 § Burn (11 `BurnTests`, 14 § Stage 5.3): `burn_7d` over the 7 closed UTC days, nil below 2 days with data;
/// `burn_today`'s 2 h and $1 gates; half-up rounding.
@Suite struct BurnTests {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00:00Z

  static func figure(_ cents: Int64, estimate: Bool = false) -> SpendFigure {
    SpendFigure(cents: cents, isEstimate: estimate)
  }

  @Test("the 7 closed days are the ones before today")
  func closedDays() {
    #expect(Burn.closedDays(now: Self.now) == ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06",
                                               "2026-11-07", "2026-11-08", "2026-11-09"])
  }

  @Test("burn_7d: nil with fewer than 2 closed days of data; Σ ÷ 7 half-up; today does not count")
  func sevenDay() {
    #expect(Burn.sevenDay(daily: ["2026-11-09": Self.figure(700)], now: Self.now) == nil)
    #expect(Burn.sevenDay(daily: ["2026-11-10": Self.figure(9_999), "2026-11-09": Self.figure(700)],
                          now: Self.now) == nil)
    #expect(Burn.sevenDay(daily: ["2026-11-08": Self.figure(300), "2026-11-09": Self.figure(400)],
                          now: Self.now) == 100)
    // 25 / 7 = 3.57 → 4; 24 / 7 = 3.43 → 3.
    #expect(Burn.sevenDay(daily: ["2026-11-08": Self.figure(20), "2026-11-09": Self.figure(5)], now: Self.now) == 4)
    #expect(Burn.sevenDay(daily: ["2026-11-08": Self.figure(20), "2026-11-09": Self.figure(4)], now: Self.now) == 3)
    #expect(Burn.sevenDay(daily: ["2026-11-02": Self.figure(500), "2026-11-09": Self.figure(4)], now: Self.now) == nil)
  }

  @Test("burn_today: from 2 h into the UTC day and $1 estimated; scaled to 24 h")
  func today() {
    let daily = ["2026-11-10": Self.figure(600, estimate: true)]
    // 12:00 UTC: 600 × 86400 / 43200 = 1200.
    #expect(Burn.today(daily: daily, now: Self.now) == 1_200)
    let early = Self.now.addingTimeInterval(-10 * 3600 - 1)   // 01:59:59
    #expect(Burn.today(daily: daily, now: early) == nil)
    let atTwo = Self.now.addingTimeInterval(-10 * 3600)       // 02:00:00
    #expect(Burn.today(daily: daily, now: atTwo) == 7_200)
    #expect(Burn.today(daily: ["2026-11-10": Self.figure(99, estimate: true)], now: Self.now) == nil)
    #expect(Burn.today(daily: [:], now: Self.now) == nil)
  }

  @Test("half-up division, both signs")
  func divide() {
    #expect(Burn.divideHalfUp(7, by: 2) == 4)
    #expect(Burn.divideHalfUp(5, by: 2) == 3)
    #expect(Burn.divideHalfUp(-7, by: 2) == -4)
    #expect(Burn.divideHalfUp(-5, by: 3) == -2)
    #expect(Burn.secondsSinceUTCMidnight(Self.now) == 43_200)
  }

  @Test("the summary's burn follows the daily rule (truth for closed days with a cost row)")
  func summaryBurn() {
    let poll = PollStateSummary(accountId: OpenAIHarness.account.id, job: "usage",
                                lastSuccessAt: "2026-11-10T11:00:00.000Z")
    let id = OpenAIHarness.account.id
    let inputs = SummaryInputs(
      accounts: [OpenAIHarness.account], pollStates: [poll],
      usageDays: [UsageDay(accountId: id, day: "2026-11-08", source: "provider", estCents: 999),
                  UsageDay(accountId: id, day: "2026-11-09", source: "provider", estCents: 700),
                  UsageDay(accountId: id, day: "2026-11-10", source: "provider", estCents: 300)],
      costDays: [CostDay(accountId: id, day: "2026-11-08", amountCents: 700)]
    )
    let summary = AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: Self.now)).first
    #expect(summary?.burn7dCents == 200)    // (700 truth + 700 estimate) / 7
    #expect(summary?.burnTodayCents == 600)  // 300 × 2
  }
}
