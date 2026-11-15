import Foundation
import Testing
@testable import TokenBeCore

/// 05 § Cost formula (11 `CostFormulaTests`, 14 § Stage 5.2 step 1): every row of `expected/pricing.csv`, whose cents
/// were computed by hand from `prices/litellm.snapshot.json`; the fallback multipliers, half-up rounding once, tiers
/// priced as standard, and V5.
@Suite struct CostFormulaTests {
  struct Row: Sendable, CustomTestStringConvertible {
    var provider: ProviderID
    var model: String
    var classes: TokenClasses
    var cents: Int64?
    var unpriced: Bool
    var testDescription: String { "\(provider.rawValue) \(model) \(classes.tokens) tokens" }
  }

  static func rows() throws -> [Row] {
    let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
    let text = try String(contentsOf: root.appendingPathComponent("Fixtures/expected/pricing.csv"), encoding: .utf8)
    return try text.split(separator: "\n").dropFirst().map { line in
      let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 10, let provider = ProviderID(rawValue: fields[0]) else {
        throw StoreError.notFound("bad pricing.csv line: \(line)")
      }
      let numbers = fields[2...7].compactMap { Int64($0) }
      guard numbers.count == 6 else { throw StoreError.notFound("bad classes: \(line)") }
      return Row(provider: provider, model: fields[1], classes: TokenClasses(
        inputUncached: numbers[0], cacheWrite5m: numbers[1], cacheWrite1h: numbers[2], cacheRead: numbers[3],
        output: numbers[4], reasoning: numbers[5]
      ), cents: Int64(fields[8]), unpriced: fields[9] == "1")
    }
  }

  static func pricer() throws -> Pricer { Pricer(feed: try PriceLookupTests.feed()) }

  @Test("pricing.csv has every case kind")
  func coverage() throws {
    let rows = try Self.rows()
    #expect(rows.count == 16)
    #expect(rows.filter(\.unpriced).count == 3)
    #expect(Set(rows.map(\.provider)) == [.openai, .anthropic, .deepseek, .openrouter])
  }

  @Test("each pricing.csv row prices to its hand-computed cents", arguments: try CostFormulaTests.rows())
  func csvRow(_ row: Row) throws {
    let entry = try Self.pricer().lookup(provider: row.provider, model: row.model)?.entry
    let estimate = CostEstimator.estimate(row.classes, entry: entry)
    #expect(estimate.cents == row.cents)
    #expect(estimate.isUnpriced == row.unpriced)
  }

  @Test("fallback multipliers are reported only for classes with tokens")
  func fallbackFields() {
    let entry = PriceEntry(input: 2_500_000, output: 10_000_000)
    let none = CostEstimator.estimate(TokenClasses(inputUncached: 10, output: 5), entry: entry)
    #expect(none.fallbackFields.isEmpty)
    let all = CostEstimator.estimate(TokenClasses(cacheWrite5m: 1, cacheWrite1h: 1, cacheRead: 1), entry: entry)
    #expect(all.fallbackFields == [PriceEntry.Key.cacheWrite, PriceEntry.Key.cacheWrite1h, PriceEntry.Key.cacheRead])
  }

  @Test("the 1h write uses the 5m write rate before the 2.0 fallback")
  func oneHourChain() {
    let entry = PriceEntry(input: 1_000_000, output: 1_000_000, cacheWrite: 3_000_000)
    // 1,000,000 tokens × 3 µ$ = $3 = 300 cents; no fallback for the 1h class.
    let estimate = CostEstimator.estimate(TokenClasses(cacheWrite1h: 1_000_000), entry: entry)
    #expect(estimate.cents == 300)
    #expect(estimate.fallbackFields.isEmpty)
  }

  @Test("priority and batch are priced as standard and flagged; other tiers are not flagged")
  func tiers() {
    let entry = PriceEntry(input: 2_500_000, output: 10_000_000)
    let classes = TokenClasses(inputUncached: 1_000_000)
    for tier in ["priority", "batch"] {
      let estimate = CostEstimator.estimate(classes, entry: entry, serviceTier: tier)
      #expect(estimate.cents == 250)
      #expect(estimate.tierPricedAsStandard)
    }
    for tier in ["", "default", "flex"] {
      #expect(!CostEstimator.estimate(classes, entry: entry, serviceTier: tier).tierPricedAsStandard)
    }
  }

  @Test("V5: no entry, or a zero rate, is unpriced; priced rows get est_cost_cents and unpriced = 0")
  func unpricedRows() {
    let row = OpenAITests.usageRows[0]
    let (none, _) = CostEstimator.priced(row, entry: nil)
    #expect(none.estCostCents == nil)
    #expect(none.unpriced)
    let (zero, _) = CostEstimator.priced(row, entry: PriceEntry(input: 0, output: 1))
    #expect(zero.unpriced)
    let (priced, _) = CostEstimator.priced(row, entry: PriceEntry(input: 2_500_000, output: 10_000_000,
                                                                   cacheRead: 1_250_000))
    #expect(priced.estCostCents == 1)
    #expect(!priced.unpriced)
  }

  @Test("absurd counts or rates saturate instead of trapping; the result clamps to Int64")
  func overflow() {
    let entry = PriceEntry(input: Int64.max / 2, output: Int64.max / 2)
    let estimate = CostEstimator.estimate(TokenClasses(inputUncached: Int64.max / 2, output: Int64.max / 2,
                                                       reasoning: Int64.max / 2), entry: entry)
    #expect(estimate.cents == Int64.max)
    let big = CostEstimator.estimate(TokenClasses(inputUncached: 1_000_000_000_000_000),
                                     entry: PriceEntry(input: 1_000_000_000_000, output: 1))
    #expect(big.cents == 100_000_000_000_000_000)   // 10^18 tokens × $1 = $10^18
    #expect(CostEstimator.product(-2, 3, 20) == -120)
    #expect(CostEstimator.product(Int64.min, Int64.max, 40) == .min)
    #expect(CostEstimator.sum(.min, -1) == .min)
    #expect(CostEstimator.roundHalfUp(-CostEstimator.divisor * 3 / 2) == -2)
    #expect(CostEstimator.roundHalfUp(.min) == Int64.min)
  }
}
