import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 14 § Stage 5.2 steps 2–3 (11 `RepriceTests`): a usage poll prices every row; a snapshot or override change
/// reprices the last 90 days (`price.repriced`); unpriced flips when a price appears; `price.unpriced` and
/// `price.fallback_multiplier` are logged once per model per UTC day. On the real database.
@Suite struct RepriceTests {
  typealias Harness = OpenAIHarness

  static func usageRow(model: String, start: String = "2026-11-10T10:00:00.000Z",
                       classes: TokenClasses = TokenClasses(inputUncached: 1_000_000)) -> UsageBucketRecord {
    UsageBucketRecord(
      accountId: Harness.account.id, bucketStart: start, bucketWidth: "1h", model: model, providerKeyId: "",
      serviceTier: "", source: "provider", inputUncached: classes.inputUncached, cacheWrite5m: classes.cacheWrite5m,
      cacheWrite1h: classes.cacheWrite1h, cacheRead: classes.cacheRead, output: classes.output,
      reasoning: classes.reasoning, requests: 1, estCostCents: nil, unpriced: false, provisional: false,
      fetchedAt: "2026-11-10T12:00:00.000Z"
    )
  }

  static func write(_ harness: Harness, _ rows: [UsageBucketRecord]) async throws {
    let priced = await harness.prices.price(rows, provider: .openai)
    try await harness.repository.writeUsagePage(UsagePageWrite(
      accountID: Harness.account.id, rows: priced, expected: rows.reduce(TokenClasses()) { $0 + $1.classes },
      cursor: nil, lastRaw: "{}"
    ))
  }

  static func rows(_ harness: Harness) async throws -> [String: UsageBucketRecord] {
    let rows = try await harness.repository.fetchUsageBuckets(accountID: Harness.account.id)
    return Dictionary(rows.map { ($0.model, $0) }) { first, _ in first }
  }

  @Test("14 Verify: after a usage poll no row has est_cost_cents NULL with unpriced = 0")
  func pollPricesEveryRow() async throws {
    let harness = try await Harness()
    await harness.on(Harness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await harness.run(.usage) == .succeeded(rows: 4))
    let count = try await harness.database.read { db in
      try Int.fetchOne(db, sql: "SELECT count(*) FROM usage_bucket WHERE est_cost_cents IS NULL AND unpriced = 0")
    }
    #expect(count == 0)
    #expect(try await harness.repository.fetchUsageBuckets(accountID: Harness.account.id) == OpenAITests.usageRows)
    // gpt-4o-mini has no cache-write rate: the 1.25 fallback is logged once for the day.
    let fallbacks = await harness.records(.priceFallbackMultiplier)
    #expect(fallbacks.count == 1)
    #expect(fallbacks.first?.ctx["model"] == "gpt-4o-mini")
    #expect(fallbacks.first?.ctx["field"] == .string(PriceEntry.Key.cacheWrite))
  }

  @Test("a poller without a price book writes every row unpriced (05)")
  func noPriceBook() async throws {
    let harness = try await Harness()
    let bare = Poller(store: harness.repository, keyStore: harness.keys,
                      registry: ProviderRegistry(adapters: [harness.adapter]), transport: harness.transport,
                      clock: harness.clock, logPipeline: harness.store.pipeline, now: harness.date.provider)
    await harness.on(Harness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await bare.runOnce(account: Harness.account, job: .usage) == .succeeded(rows: 4))
    let rows = try await harness.repository.fetchUsageBuckets(accountID: Harness.account.id)
    #expect(rows.allSatisfy { $0.unpriced && $0.estCostCents == nil })
  }

  @Test("price.unpriced once per model per UTC day; the snapshot line counts the model")
  func unpricedOncePerDay() async throws {
    let harness = try await Harness()
    try await Self.write(harness, [Self.usageRow(model: "made-up-model-1")])
    try await Self.write(harness, [Self.usageRow(model: "made-up-model-1", start: "2026-11-10T11:00:00.000Z")])
    #expect(await harness.records(.priceUnpriced).count == 1)
    #expect(await harness.prices.status.unpricedModels == 1)
    harness.date.set(Harness.now.addingTimeInterval(86_400))
    try await Self.write(harness, [Self.usageRow(model: "made-up-model-1", start: "2026-11-11T10:00:00.000Z")])
    let records = await harness.records(.priceUnpriced)
    #expect(records.count == 2)
    #expect(records.first?.ctx["provider"] == "openai")
    #expect(records.first?.ctx["model"] == "made-up-model-1")
  }

  @Test("an override reprices: unpriced flips to priced, price.repriced counts the changed rows")
  func overrideReprices() async throws {
    let harness = try await Harness()
    try await Self.write(harness, [Self.usageRow(model: "made-up-model-1"), Self.usageRow(model: "gpt-4o")])
    #expect(try await Self.rows(harness)["made-up-model-1"]?.unpriced == true)

    try await harness.prices.setOverride(model: "made-up-model-1", entry: PriceEntry(input: 1_000_000, output: 2_000_000))
    var rows = try await Self.rows(harness)
    #expect(rows["made-up-model-1"]?.unpriced == false)
    #expect(rows["made-up-model-1"]?.estCostCents == 100)   // 1,000,000 × 1 µ$ = $1
    #expect(rows["gpt-4o"]?.estCostCents == 250)
    var repriced = await harness.records(.priceRepriced)
    #expect(repriced.count == 1)
    #expect(repriced.last?.ctx["rows"] == 1)
    #expect(repriced.last?.acct == "openai")
    #expect(repriced.last?.ctx["snapshot_version"] == "bundled-test")
    #expect(await harness.prices.status.unpricedModels == 0)

    try await harness.prices.removeOverride(model: "made-up-model-1")
    rows = try await Self.rows(harness)
    #expect(rows["made-up-model-1"]?.unpriced == true)
    #expect(rows["made-up-model-1"]?.estCostCents == nil)
    repriced = await harness.records(.priceRepriced)
    #expect(repriced.last?.ctx["rows"] == 1)

    try await harness.prices.setOverride(model: "gpt-4o", entry: PriceEntry(input: 5_000_000, output: 10_000_000))
    #expect(try await Self.rows(harness)["gpt-4o"]?.estCostCents == 500)
    try await harness.prices.resetToFeed()
    #expect(try await Self.rows(harness)["gpt-4o"]?.estCostCents == 250)
  }

  @Test("a new feed snapshot reprices; rows older than 90 days are left alone")
  func snapshotReprices() async throws {
    let harness = try await Harness()
    let old = Self.usageRow(model: "gpt-4o", start: "2026-08-01T10:00:00.000Z")
    try await Self.write(harness, [Self.usageRow(model: "gpt-4o"), old])
    let feed = Data(#"{"gpt-4o":{"mode":"chat","input_cost_per_token":5e-6,"output_cost_per_token":1e-5}}"#.utf8)
    await harness.transport.on("GET", PriceFeedTests.path, PriceFeedTests.ok(feed))
    let fetcher = PriceFeedFetcher(transport: harness.transport, logPipeline: harness.store.pipeline)
    let outcome = try await harness.prices.refresh(fetcher: fetcher, url: PriceFeedTests.feedURL, feedEnabled: true,
                                                   staleAfterDays: 7)
    guard case .new = outcome else {
      Issue.record("expected a new snapshot, got \(String(describing: outcome))")
      return
    }
    let rows = try await harness.repository.fetchUsageBuckets(accountID: Harness.account.id)
    #expect(rows.first { $0.bucketStart == "2026-11-10T10:00:00.000Z" }?.estCostCents == 500)
    #expect(rows.first { $0.bucketStart == "2026-08-01T10:00:00.000Z" }?.estCostCents == 250)
    let repriced = await harness.records(.priceRepriced)
    #expect(repriced.last?.ctx["snapshot_version"] == "2026-11-10")
  }

  @Test("priority-tier rows log tier_priced_as_standard once per model per day")
  func tierLogged() async throws {
    let harness = try await Harness()
    var row = Self.usageRow(model: "gpt-4o")
    row.serviceTier = "priority"
    try await Self.write(harness, [row])
    let records = await harness.records(.priceFallbackMultiplier)
    #expect(records.count == 1)
    #expect(records.first?.ctx["tier_priced_as_standard"] == true)
    #expect(records.first?.ctx["field"] == "service_tier")
  }

  @Test("the memory repository reprices like the database")
  func memoryRepository() async throws {
    let memory = MemoryRepository()
    try await memory.insertAccount(Harness.account)
    try await memory.writeUsagePage(UsagePageWrite(accountID: Harness.account.id,
                                                   rows: [Self.usageRow(model: "made-up-model-1")],
                                                   expected: TokenClasses(), cursor: nil, lastRaw: ""))
    let changed = try await memory.repriceUsage(accountID: Harness.account.id, since: "2026-01-01") {
      CostEstimator.priced($0, entry: nil).0
    }
    #expect(changed == 1)
    #expect(try await memory.fetchUnpricedModels(since: "2026-01-01") == ["made-up-model-1"])
  }
}
