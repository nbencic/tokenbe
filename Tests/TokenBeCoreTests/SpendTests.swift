import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 05 § Spend definitions for the numbers strip and the Overview subline (14 § Stage 5.2 step 4, Q-040): range days,
/// truth for closed days with a cost row, estimates otherwise, `unpriced_cents` at the median input rate, the
/// USD-only total; and the observation that feeds them.
@Suite struct SpendTests {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00:00Z
  static let account = "acct"
  static let withCost = Capabilities(usage: true, cost: true, balance: false, perKeyUsage: true, keyNames: true,
                                     balanceModeDefault: .anchored, usageLag: .seconds(300), currencyHint: .usd)

  static let usage = [
    UsageDay(accountId: account, day: "2026-11-08", source: "provider", estCents: 100, unpricedTokens: 0),
    UsageDay(accountId: account, day: "2026-11-09", source: "provider", estCents: 200, unpricedTokens: 1_000_000),
    UsageDay(accountId: account, day: "2026-11-10", source: "provider", estCents: 50, unpricedTokens: 0),
    UsageDay(accountId: account, day: "2026-11-10", source: "harness", estCents: 7, unpricedTokens: 0),
    UsageDay(accountId: "other", day: "2026-11-10", source: "provider", estCents: 999, unpricedTokens: 0)
  ]
  static let costs = [
    CostDay(accountId: account, day: "2026-11-08", amountCents: 120),
    CostDay(accountId: account, day: "2026-11-10", amountCents: 70)
  ]

  static func summary(_ capabilities: Capabilities?) -> AccountSummary {
    AccountSummary(id: account, provider: .openai, label: "OpenAI", mode: .anchored, capabilities: capabilities)
  }

  static func spend(_ days: [String], costs: [CostDay] = SpendTests.costs,
                    capabilities: Capabilities? = SpendTests.withCost) -> SpendFigure {
    Spend.spend(summary(capabilities), days: days, today: "2026-11-10",
                inputs: SummaryInputs(accounts: [], usageDays: usage, costDays: costs))
  }

  static func unpriced(_ days: [String], models: [PricedModelDay], pricer: Pricer) -> UnpricedFigure {
    Spend.unpriced(summary(withCost), days: days, inputs: SummaryInputs(accounts: [], usageDays: usage,
                                                                         pricedModels: models), pricer: pricer)
  }

  @Test("range days are UTC days ending today")
  func days() {
    #expect(Spend.days(.today, now: Self.now) == ["2026-11-10"])
    #expect(Spend.days(.sevenDays, now: Self.now).first == "2026-11-04")
    #expect(Spend.days(.sevenDays, now: Self.now).last == "2026-11-10")
    #expect(Spend.days(.thirtyDays, now: Self.now).count == 30)
    #expect(Spend.days(.ninetyDays, now: Self.now).count == 90)
  }

  @Test("closed days with a cost row use the cost; the open day and days without one use the estimate")
  func truthThenEstimate() {
    let days = Spend.days(.sevenDays, now: Self.now)
    let figure = Self.spend(days)
    // 11-08: cost 120; 11-09: estimate 200; 11-10 (open): estimate 50; harness rows do not count with a usage API.
    #expect(figure == SpendFigure(cents: 370, isEstimate: true))
    let today = Self.spend(["2026-11-10"])
    #expect(today == SpendFigure(cents: 50, isEstimate: true))
    let closed = Self.spend(["2026-11-08"])
    #expect(closed == SpendFigure(cents: 120, isEstimate: false))
  }

  @Test("without a cost API every day is estimated; without a usage API harness rows count")
  func capabilities() {
    var noCost = Self.withCost
    noCost.cost = false
    #expect(Self.spend(["2026-11-08"], capabilities: noCost) == SpendFigure(cents: 100, isEstimate: true))
    var harnessOnly = noCost
    harnessOnly.usage = false
    #expect(Self.spend(["2026-11-10"], costs: [], capabilities: harnessOnly) == SpendFigure(cents: 57, isEstimate: true))
    #expect(Self.spend(["2026-11-01"], costs: [], capabilities: nil) == SpendFigure(cents: 0, isEstimate: false))
  }

  @Test("unpriced tokens are valued at the median input rate of the window's priced models")
  func unpricedMedian() {
    let pricer = Pricer(feed: [
      "a": PriceEntry(input: 1_000_000, output: 1), "b": PriceEntry(input: 3_000_000, output: 1),
      "c": PriceEntry(input: 10_000_000, output: 1)
    ])
    let models = ["a", "b", "c"].map { PricedModelDay(accountId: Self.account, day: "2026-11-09", model: $0) }
    let days = Spend.days(.sevenDays, now: Self.now)
    let figure = Self.unpriced(days, models: models, pricer: pricer)
    // 1,000,000 tokens × 3 µ$ (median of 1, 3, 10) = $3.
    #expect(figure == UnpricedFigure(tokens: 1_000_000, cents: 300))
    let even = Self.unpriced(days, models: Array(models.prefix(2)), pricer: pricer)
    #expect(even.cents == 200)
    let noRate = Self.unpriced(days, models: [], pricer: pricer)
    #expect(noRate == UnpricedFigure(tokens: 1_000_000, cents: nil))
    let none = Self.unpriced(["2026-11-10"], models: models, pricer: pricer)
    #expect(none == UnpricedFigure(tokens: 0, cents: 0))
  }

  @Test("the Overview total sums USD accounts and counts the others")
  func totalUSD() {
    var usd = AccountSummary(id: "a", provider: .openai, label: "A", mode: .anchored)
    usd.rangeSpend = SpendFigure(cents: 300, isEstimate: false)
    var usd2 = AccountSummary(id: "b", provider: .anthropic, label: "B", mode: .anchored)
    usd2.rangeSpend = SpendFigure(cents: 45, isEstimate: true)
    var cny = AccountSummary(id: "c", provider: .deepseek, label: "C", mode: .direct, currency: .cny)
    cny.rangeSpend = SpendFigure(cents: 1_000, isEstimate: false)
    let total = Spend.totalUSD([usd, usd2, cny])
    #expect(total.spend == SpendFigure(cents: 345, isEstimate: true))
    #expect(total.nonUSD == 1)
  }

  @Test("the summary builder fills spend once the account has polled, from observed inputs")
  func builderFromObservation() async throws {
    let harness = try await OpenAIHarness()
    await harness.on(OpenAIHarness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await harness.run(.usage) == .succeeded(rows: 4))
    var stream = harness.repository.observeSummaryInputs().makeAsyncIterator()
    let inputs = try #require(await stream.next())
    #expect(inputs.usageDays.reduce(0) { $0 + $1.estCents } == 1)
    #expect(Set(inputs.pricedModels.map(\.model)) == ["gpt-4o-2024-08-06", "gpt-4o-mini"])
    let context = AccountSummaryBuilder.SpendContext(range: .sevenDays, now: OpenAIHarness.now,
                                                    pricer: await harness.prices.pricer)
    let summary = try #require(AccountSummaryBuilder.summaries(from: inputs, spend: context).first)
    #expect(summary.rangeSpend == SpendFigure(cents: 1, isEstimate: true))
    #expect(summary.todaySpend == SpendFigure(cents: 0, isEstimate: true))
    #expect(summary.todaySpendCents == 0)
    #expect(summary.unpriced == UnpricedFigure(tokens: 0, cents: 0))

    let never = AccountSummaryBuilder.summaries(from: SummaryInputs(accounts: inputs.accounts)).first
    #expect(never?.todaySpend == nil)
    #expect(never?.rangeSpend == nil)
  }

  @Test("the observation reads cost totals per day")
  func costDays() async throws {
    let harness = try await OpenAIHarness()
    await harness.on(OpenAIHarness.costs, "costs.ok")
    #expect(await harness.run(.cost) != .failed("store"))
    var stream = harness.repository.observeSummaryInputs().makeAsyncIterator()
    let inputs = try #require(await stream.next())
    let stored = try await harness.repository.fetchCostBuckets(accountID: OpenAIHarness.account.id)
      .filter { $0.groupKind == "total" }
    #expect(inputs.costDays.count == stored.count)
    #expect(inputs.costDays.reduce(0) { $0 + $1.amountCents } == stored.reduce(0) { $0 + $1.amountCents })
  }
}
