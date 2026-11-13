import Foundation
import Testing
@testable import TokenBeCore

/// 05 § Price lookup (11 `PriceLookupTests`): each of the 6 steps, `mode != chat` ignored, zero or missing price is
/// unpriced (V5), override precedence, date-suffix strip, `-latest`; plus the rate conversion of Q-038.
@Suite struct PriceLookupTests {
  static func fixtureURL() -> URL {
    (Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent"))
      .appendingPathComponent("Fixtures/prices/litellm.snapshot.json")
  }

  static func feed() throws -> [String: PriceEntry] {
    try PriceTable.parse(Data(contentsOf: fixtureURL())).entries
  }

  static let override = PriceEntry(input: 1_000_000, output: 2_000_000)

  static func find(_ provider: ProviderID, _ model: String,
                   overrides: [String: PriceEntry] = [:]) throws -> Lookup.Hit? {
    Lookup.find(provider: provider, model: model, overrides: overrides, feed: try feed())
  }

  @Test("step 1: an override wins over the feed")
  func overrideWins() throws {
    let hit = try Self.find(.openai, "gpt-4o", overrides: ["gpt-4o": Self.override])
    #expect(hit?.step == .override)
    #expect(hit?.entry == Self.override)
  }

  @Test("step 2: the exact feed key, with every rate converted to picodollars per token")
  func exact() throws {
    let hit = try #require(try Self.find(.anthropic, "claude-sonnet-4-5"))
    #expect(hit.step == .exact)
    #expect(hit.key == "claude-sonnet-4-5")
    #expect(hit.entry == PriceEntry(input: 3_000_000, output: 15_000_000, cacheRead: 300_000, cacheWrite: 3_750_000,
                                    cacheWrite1h: 6_000_000, litellmProvider: "anthropic", mode: "chat"))
  }

  @Test("step 3: the provider prefix (deepseek, xai, openrouter); OpenAI and Anthropic keys are bare",
        arguments: [(ProviderID.deepseek, "deepseek-chat", "deepseek/deepseek-chat"),
                    (.xai, "grok-4", "xai/grok-4"), (.openrouter, "openai/gpt-4o", "openrouter/openai/gpt-4o")])
  func prefixed(_ provider: ProviderID, _ model: String, _ key: String) throws {
    let hit = try Self.find(provider, model)
    #expect(hit?.step == .prefixed)
    #expect(hit?.key == key)
    #expect(Lookup.prefix(.openai) == nil)
    #expect(Lookup.prefix(.anthropic) == nil)
  }

  @Test("step 4: a trailing date suffix is stripped, then steps 2 and 3 apply",
        arguments: [(ProviderID.openai, "gpt-4o-2024-08-06", "gpt-4o"),
                    (.anthropic, "claude-sonnet-4-5-20250929", "claude-sonnet-4-5"),
                    (.deepseek, "deepseek-chat-20250101", "deepseek/deepseek-chat")])
  func dateStripped(_ provider: ProviderID, _ model: String, _ key: String) throws {
    let hit = try Self.find(provider, model)
    #expect(hit?.step == .dateStripped)
    #expect(hit?.key == key)
  }

  @Test("step 5: -latest is appended")
  func latest() throws {
    let hit = try Self.find(.anthropic, "claude-3-5-haiku")
    #expect(hit?.step == .latest)
    #expect(hit?.key == "claude-3-5-haiku-latest")
  }

  @Test("step 6: an unknown model is unpriced")
  func unpriced() throws {
    #expect(try Self.find(.openai, "made-up-model-1") == nil)
    #expect(try Self.find(.openai, "made-up-model-1", overrides: ["other": Self.override]) == nil)
  }

  @Test("entries with mode != chat never match, and the feed's sample_spec is skipped")
  func nonChatIgnored() throws {
    let feed = try Self.feed()
    #expect(feed["text-embedding-3-small"] == nil)
    #expect(feed["sample_spec"] == nil)
    #expect(feed.count == 9)
    #expect(try Self.find(.openai, "text-embedding-3-small") == nil)
  }

  @Test("V5: a hit with a zero or missing input/output rate is unpriced, and stops the search",
        arguments: ["free-zero-model", "input-only-model"])
  func zeroPrice(_ model: String) throws {
    #expect(Lookup.firstHit(provider: .openai, model: model, overrides: [:], feed: try Self.feed()) != nil)
    #expect(try Self.find(.openai, model) == nil)
  }

  @Test("V5 applies to overrides too")
  func zeroOverride() throws {
    #expect(try Self.find(.openai, "gpt-4o", overrides: ["gpt-4o": PriceEntry(input: 0, output: 5)]) == nil)
  }

  @Test("date suffixes: -YYYYMMDD and -YYYY-MM-DD only, at the end, after a name")
  func stripDate() {
    #expect(Lookup.stripDate("gpt-4o-2024-08-06") == "gpt-4o")
    #expect(Lookup.stripDate("claude-3-opus-20240229") == "claude-3-opus")
    #expect(Lookup.stripDate("gpt-4o") == nil)
    #expect(Lookup.stripDate("model-2024080") == nil)
    #expect(Lookup.stripDate("-20240229") == nil)
  }

  // MARK: - Rates (Q-038)

  @Test("USD per token becomes integer picodollars; non-numbers are missing")
  func rates() {
    #expect(PriceEntry.rate(NSNumber(value: 2.5e-06)) == 2_500_000)
    #expect(PriceEntry.rate(NSNumber(value: 7.5e-09)) == 7_500)
    #expect(PriceEntry.rate(NSNumber(value: 1e-05)) == 10_000_000)
    #expect(PriceEntry.rate(NSNumber(value: true)) == nil)
    #expect(PriceEntry.rate("2.5e-06") == nil)
    #expect(PriceEntry.rate(nil) == nil)
    #expect(PriceEntry.rate(NSNumber(value: Double.infinity)) == nil)
    #expect(PriceEntry.rate(NSNumber(value: 1e10)) == nil)
  }

  @Test("an override's JSON uses the feed keys and reads back to the same integers")
  func overrideJSON() throws {
    let entry = PriceEntry(input: 1_250_000, output: 10_000_000, cacheRead: 125_000, cacheWrite: 1_562_500,
                           cacheWrite1h: 2_500_000)
    let json = entry.feedJSON()
    #expect(json.contains("\"input_cost_per_token\":1250000e-12"))
    #expect(json.contains("\"mode\":\"chat\""))
    let back = try PriceEntry(json: json)
    #expect(back == PriceEntry(input: 1_250_000, output: 10_000_000, cacheRead: 125_000, cacheWrite: 1_562_500,
                               cacheWrite1h: 2_500_000, litellmProvider: nil, mode: "chat"))
    #expect(PriceEntry(input: 1, output: 2).feedJSON() == #"{"input_cost_per_token":1e-12,"output_cost_per_token":2e-12,"mode":"chat"}"#)
    #expect(throws: PriceTable.ParseError.notAnObject) { try PriceEntry(json: "not json") }
    #expect(throws: PriceTable.ParseError.notAnObject) { try PriceEntry(json: "[1]") }
  }

  @Test("a document that is not a JSON object does not parse; O-6 shape check")
  func parse() throws {
    #expect(throws: PriceTable.ParseError.notAnObject) { try PriceTable.parse(Data("nope".utf8)) }
    #expect(throws: PriceTable.ParseError.notAnObject) { try PriceTable.parse(Data("[]".utf8)) }
    #expect(try PriceTable.parse(Data("{}".utf8)).shapeChanged)
    let half = #"{"a":{"mode":"chat","input_cost_per_token":1e-6},"b":{"mode":"chat"}}"#
    #expect(try PriceTable.parse(Data(half.utf8)).shapeChanged == false)
    let most = #"{"a":{"mode":"chat","input_cost_per_token":1e-6},"b":{"mode":"chat"},"c":{"mode":"chat"}}"#
    #expect(try PriceTable.parse(Data(most.utf8)).shapeChanged)
    #expect(try PriceTable.parse(Data(contentsOf: Self.fixtureURL())).shapeChanged == false)
  }

  /// The app's bundled snapshot (14 § Stage 5.1 step 1): it parses, passes O-6, and no positive feed rate rounds to
  /// zero picodollars (which V5 would silently turn into "unpriced").
  @Test("the bundled snapshot parses, holds only chat entries, and every positive rate stays positive")
  func bundledSnapshot() throws {
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Sources/TokenBeApp/Resources")
    let data = try Data(contentsOf: resources.appendingPathComponent("prices.bundled.json"))
    let sha = try String(contentsOf: resources.appendingPathComponent("prices.bundled.sha256"), encoding: .utf8)
    #expect(PriceFeedFetcher.sha256(data) == sha.trimmingCharacters(in: .whitespacesAndNewlines))
    let table = try PriceTable.parse(data)
    #expect(table.shapeChanged == false)
    let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
    #expect(raw.count == table.entries.count)
    let keys = [PriceEntry.Key.input, PriceEntry.Key.output, PriceEntry.Key.cacheRead, PriceEntry.Key.cacheWrite,
                PriceEntry.Key.cacheWrite1h]
    var lost: [String] = []
    for (model, fields) in raw {
      for key in keys {
        if let number = fields[key] as? NSNumber, number.doubleValue > 0, (PriceEntry.rate(number) ?? 0) <= 0 {
          lost.append("\(model).\(key)")
        }
      }
    }
    #expect(lost.isEmpty, "rates below one picodollar: \(lost)")
  }
}
