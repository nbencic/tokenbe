import Foundation
import Testing
@testable import TokenBeCore

/// 11 `CacheSavingsTests` (14 § Stage 8.2): 05 § Cache savings, net of write premiums, with `CostEstimator`'s rates
/// and fallbacks and one rounding; the source each provider counts; OpenAI and OpenRouter not computed; unpriced
/// models left out; the builder and the tile's total (Q-052).
@Suite struct CacheSavingsTests {
  static let days = ["2026-11-08", "2026-11-09", "2026-11-10"]
  /// $3 / M input, $15 / M output, $0.30 / M cache read, $3.75 / M 5 m write, $6 / M 1 h write (picodollars per token).
  static let full = PriceEntry(input: 3_000_000, output: 15_000_000, cacheRead: 300_000, cacheWrite: 3_750_000,
                               cacheWrite1h: 6_000_000)
  /// 1 M cache reads, 100 k 5 m writes, 10 k 1 h writes, and plain input and output that never count.
  static let classes = TokenClasses(inputUncached: 5_000, cacheWrite5m: 100_000, cacheWrite1h: 10_000,
                                    cacheRead: 1_000_000, output: 2_000, reasoning: 300, requests: 4)

  static func account(_ provider: ProviderID, id: String = "acct", currency: Currency = .usd) -> AccountSummary {
    AccountSummary(id: id, provider: provider, label: provider.displayName, mode: .anchored, currency: currency)
  }

  static func row(_ model: String, source: String, day: String = "2026-11-09", account: String = "acct",
                  classes: TokenClasses = classes) -> ModelUsageDay {
    ModelUsageDay(accountId: account, day: day, model: model, source: source, estCents: 1, classes: classes)
  }

  static func inputs(_ rows: [ModelUsageDay]) -> SummaryInputs {
    var inputs = SummaryInputs(accounts: [])
    inputs.modelUsageDays = rows
    return inputs
  }

  static func figure(_ provider: ProviderID, _ rows: [ModelUsageDay], entry: PriceEntry = full,
                     model: String = "claude-x") -> CacheSavingsFigure {
    CacheSavings.figure(account(provider), days: days, inputs: inputs(rows), pricer: Pricer(overrides: [model: entry]))
  }

  @Test("05's formula: 1 M × (3 − 0.3) − 100 k × (3.75 − 3) − 10 k × (6 − 3) = $25.95, rounded once")
  func formula() {
    // 2.7e12 − 7.5e10 − 3e10 picodollars = 259.5 ¢ → 260 ¢ (half up, once over the range, not per row).
    #expect(Self.figure(.anthropic, [Self.row("claude-x", source: "provider")]) == .saved(cents: 260))
    let halves = TokenClasses(cacheWrite5m: 50_000, cacheWrite1h: 5_000, cacheRead: 500_000)
    let split = [Self.row("claude-x", source: "provider", day: "2026-11-08", classes: halves),
                 Self.row("claude-x", source: "provider", day: "2026-11-09", classes: halves)]
    #expect(Self.figure(.anthropic, split) == .saved(cents: 260), "two 129.75 ¢ halves round once to 260 ¢, not 2 × 130")
  }

  @Test("missing cache rates take the estimate's fallbacks: read 0.1 ×, 5 m write 1.25 ×, 1 h write the 5 m rate, then 2 ×")
  func fallbacks() {
    let bare = PriceEntry(input: 3_000_000, output: 15_000_000)
    #expect(Self.figure(.anthropic, [Self.row("claude-x", source: "provider")], entry: bare) == .saved(cents: 260))
    let noOneHour = PriceEntry(input: 3_000_000, output: 15_000_000, cacheRead: 300_000, cacheWrite: 3_750_000)
    // The 1 h write at the 5 m rate: 2.7e12 − 7.5e10 − 7.5e9 = 261.75 ¢ → 262 ¢.
    #expect(Self.figure(.anthropic, [Self.row("claude-x", source: "provider")], entry: noOneHour) == .saved(cents: 262))
  }

  @Test("the savings equal the estimate of the cached tokens as plain input minus their estimate")
  func matchesEstimator() throws {
    let plain = TokenClasses(inputUncached: 1_115_000, output: 2_000, reasoning: 300)
    let withCache = try #require(CostEstimator.estimate(Self.classes, entry: Self.full).cents)
    let without = try #require(CostEstimator.estimate(plain, entry: Self.full).cents)
    let saved = try #require(Self.figure(.anthropic, [Self.row("claude-x", source: "provider")]).cents)
    #expect(abs(saved - (without - withCache)) <= 1)
  }

  @Test("net of writes: writes with no reads are a negative saving, not —")
  func negative() {
    let writes = TokenClasses(inputUncached: 10, cacheWrite5m: 1_000_000)
    #expect(Self.figure(.anthropic, [Self.row("claude-x", source: "provider", classes: writes)]) == .saved(cents: -75))
  }

  @Test("each provider counts its own source; OpenAI and OpenRouter are not computed (05, D-openai-cache-savings-off)")
  func sources() {
    let both = [Self.row("claude-x", source: "provider"), Self.row("claude-x", source: "harness")]
    #expect(Self.figure(.anthropic, both) == .saved(cents: 260), "Anthropic: provider buckets only")
    #expect(Self.figure(.deepseek, both) == .saved(cents: 260), "DeepSeek: harness buckets only")
    #expect(Self.figure(.xai, both) == .saved(cents: 260), "xAI: harness buckets only")
    #expect(Self.figure(.openai, both) == .notComputed(.openAIAggregate), "even with harness cache counts")
    #expect(Self.figure(.openrouter, both) == .notComputed(.noCacheCounts))
    #expect(Self.figure(.deepseek, [Self.row("claude-x", source: "provider")]) == .notComputed(.noHarnessReports))
    #expect(Self.figure(.anthropic, [Self.row("claude-x", source: "harness")]) == .notComputed(.noUsage))
  }

  @Test("only the account's rows in the range count")
  func range() {
    let rows = [Self.row("claude-x", source: "provider"),
                Self.row("claude-x", source: "provider", day: "2026-11-01"),
                Self.row("claude-x", source: "provider", account: "other")]
    #expect(Self.figure(.anthropic, rows) == .saved(cents: 260))
    #expect(Self.figure(.anthropic, Array(rows.dropFirst())) == .notComputed(.noUsage))
  }

  @Test("an unpriced model is left out; an account with only unpriced usage saved $0")
  func unpriced() {
    let rows = [Self.row("claude-x", source: "provider"), Self.row("made-up-model-1", source: "provider")]
    #expect(Self.figure(.anthropic, rows) == .saved(cents: 260))
    #expect(Self.figure(.anthropic, [Self.row("made-up-model-1", source: "provider")]) == .saved(cents: 0))
    let rejected = PriceEntry(input: 0, output: 0)
    #expect(Self.figure(.anthropic, [Self.row("claude-x", source: "provider")], entry: rejected) == .saved(cents: 0),
            "a zero-priced entry is unpriced (V5)")
  }

  @Test("the builder fills cacheSavings over the Dashboard range; the tile sums the computed figures")
  func builderAndTotal() {
    let now = Date(timeIntervalSince1970: 1_794_312_000)   // 2026-11-10T12:00Z
    var inputs = Self.inputs([Self.row("claude-x", source: "provider", account: "a"),
                              Self.row("claude-x", source: "provider", day: "2026-11-01", account: "a")])
    inputs.accounts = [FixtureDBBuilder.account(id: "a", provider: "anthropic", label: "Anthropic"),
                       FixtureDBBuilder.account(id: "o", provider: "openai")]
    inputs.pollStates = ["a", "o"].map {
      PollStateSummary(accountId: $0, job: "usage", lastSuccessAt: "2026-11-10T11:59:00.000Z")
    }
    let pricer = Pricer(overrides: ["claude-x": Self.full])
    let week = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .sevenDays, now: now, pricer: pricer))
    #expect(week.map(\.cacheSavings) == [.saved(cents: 260), .notComputed(.openAIAggregate)])
    #expect(CacheSavings.total(week) == 260)
    let quarter = AccountSummaryBuilder.summaries(from: inputs, spend: .init(range: .thirtyDays, now: now, pricer: pricer))
    #expect(CacheSavings.total(quarter) == 519, "2 × 259.5 ¢ rounded once over the range")
    inputs.pollStates = []
    #expect(AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: now, pricer: pricer)).first?.cacheSavings
            == nil, "before the first poll the account has no figures (08 `No data yet`)")
    #expect(CacheSavings.total([Self.account(.openai)]) == nil, "no figure before the builder runs")
    var openai = Self.account(.openai)
    openai.cacheSavings = .notComputed(.openAIAggregate)
    #expect(CacheSavings.total([openai]) == nil, "nothing computed: the headline reads —")
  }
}
