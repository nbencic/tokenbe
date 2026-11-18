import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 11 `RetentionTests` (14 § Stage 9.1; 03 § Retention tiers): hourly → daily and daily → monthly preserve Σ cents
/// and Σ tokens exactly; re-running changes nothing; the harness purge runs only after the roll-ups; the balance
/// thinning keeps each day's first and last snapshot; the readers skip monthly rows (Q-055). On the real database.
@Suite struct RetentionTests {
  /// 2026-11-18 12:00 UTC: hourly cut-off 2026-08-20 (90 d), monthly 2025-10-01 (400 d → 2025-10-14's month),
  /// harness 2026-10-19 (30 d), balance 2026-11-11 (7 d).
  static let now = Date(timeIntervalSince1970: 1_795_003_200)
  static let policy = RetentionPolicy(hourlyDays: 90, rawHarnessDays: 30)
  static let acct = OpenAIHarness.account.id
  static let fetched = "2026-11-18T00:00:00.000Z"

  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository

    init() async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      try await repository.insertAccount(OpenAIHarness.account)
    }

    func run() async throws -> [RollupCount] {
      try await Rollup(store: repository, logPipeline: store.pipeline).run(RetentionTests.policy, now: RetentionTests.now)
    }

    func seed(_ body: @escaping @Sendable (GRDB.Database) throws -> Void) async throws {
      try await repository.database.write("seed") { db in try body(db) }
    }

    func buckets() async throws -> [UsageBucketRecord] {
      try await repository.database.read { db in
        try UsageBucketRecord.order(Column("bucket_width"), Column("bucket_start"), Column("model"),
                                    Column("provider_key_id"), Column("source")).fetchAll(db)
      }
    }

    /// Σ cents (05: unpriced counts 0) and Σ of every token column over the rows `filter` selects.
    func sums(_ filter: String) async throws -> [Int64] {
      try await repository.database.read { db in
        let row = try Row.fetchOne(db, sql: """
          SELECT SUM(COALESCE(est_cost_cents, 0)), SUM(input_uncached), SUM(cache_write_5m), SUM(cache_write_1h),
                 SUM(cache_read), SUM(output), SUM(reasoning), SUM(requests) FROM usage_bucket WHERE \(filter)
          """)
        guard let row else { return [] }
        return (0..<8).map { (row[$0] as Int64?) ?? 0 }
      }
    }
  }

  static func bucket(_ start: String, width: String = "1h", model: String = "gpt-x", key: String = "key_a",
                     source: String = "provider", est: Int64? = 7, unpriced: Bool = false, base: Int64 = 10)
    -> UsageBucketRecord {
    UsageBucketRecord(accountId: acct, bucketStart: start, bucketWidth: width, model: model, providerKeyId: key,
                      serviceTier: "default", source: source, inputUncached: base, cacheWrite5m: base + 1,
                      cacheWrite1h: base + 2, cacheRead: base + 3, output: base + 4, reasoning: base + 5,
                      requests: 1, estCostCents: est, unpriced: unpriced, provisional: false, fetchedAt: fetched)
  }

  /// 08-18 and 08-19 are past the 90 d horizon; 08-20 is inside it.
  static let hourlyRows: [UsageBucketRecord] = [
    bucket("2026-08-18T01:00:00.000Z"), bucket("2026-08-18T02:00:00.000Z", base: 20),
    bucket("2026-08-18T02:00:00.000Z", key: "key_b", est: 11),
    bucket("2026-08-18T03:00:00.000Z", model: "free-x", est: nil, unpriced: true),
    bucket("2026-08-18T04:00:00.000Z", model: "free-x", est: nil, unpriced: true, base: 30),
    bucket("2026-08-19T05:00:00.000Z", model: "mixed-x", est: 5),
    bucket("2026-08-19T06:00:00.000Z", model: "mixed-x", est: nil, unpriced: true),
    bucket("2026-08-18T01:00:00.000Z", source: "harness", est: 3), bucket("2026-08-18T09:00:00.000Z", source: "harness"),
    bucket("2026-08-20T00:00:00.000Z"), bucket("2026-08-20T00:00:00.000Z", source: "harness")
  ]

  @Test("hourly → daily: Σ cents and Σ tokens exact per counted source; provider → rollup, harness stays harness")
  func hourlyPreservesSums() async throws {
    let harness = try await Harness()
    try await harness.seed { db in for row in Self.hourlyRows { try row.insert(db) } }
    let provider = try await harness.sums("source IN ('provider', 'rollup')")
    let lines = try await harness.sums("source = 'harness'")
    let counts = try await harness.run()
    #expect(try await harness.sums("source IN ('provider', 'rollup')") == provider)
    #expect(try await harness.sums("source = 'harness'") == lines)
    #expect(counts.first == RollupCount(tier: "hourly", rowsIn: 9, rowsOut: 5))
    let rows = try await harness.buckets()
    #expect(!rows.contains { $0.bucketWidth == "1h" && $0.bucketStart < "2026-08-20" }, "past the horizon: no hour left")
    #expect(rows.filter { $0.bucketWidth == "1h" }.count == 2, "08-20 is inside the horizon and stays hourly")
    let daily = rows.filter { $0.bucketWidth == "1d" }
    #expect(Set(daily.map(\.source)) == ["rollup", "harness"])
    let keyA = try #require(daily.first { $0.model == "gpt-x" && $0.providerKeyId == "key_a" && $0.source == "rollup" })
    #expect(keyA.bucketStart == "2026-08-18T00:00:00.000Z" && keyA.estCostCents == 14 && keyA.inputUncached == 30)
    #expect(keyA.requests == 2 && keyA.fetchedAt == Self.fetched && !keyA.provisional)
    let free = try #require(daily.first { $0.model == "free-x" })
    #expect(free.estCostCents == nil && free.unpriced, "every hour unpriced: the day stays unpriced")
    let mixed = try #require(daily.first { $0.model == "mixed-x" })
    #expect(mixed.estCostCents == 5 && !mixed.unpriced, "a priced hour keeps its cents (Σ cents exact, Q-055)")
    let lineDay = try #require(daily.first { $0.source == "harness" })
    #expect(lineDay.estCostCents == 10 && lineDay.requests == 2)
  }

  @Test("idempotent: a second run writes nothing and every row is identical")
  func idempotent() async throws {
    let harness = try await Harness()
    try await harness.seed { db in
      for row in Self.hourlyRows { try row.insert(db) }
      for day in ["2025-09-03", "2025-09-20", "2025-10-02"] {
        try Self.bucket(day + "T00:00:00.000Z", width: "1d", source: "rollup").insert(db)
      }
      try Self.snapshots(db)
    }
    _ = try await harness.run()
    let first = try await harness.buckets()
    let counts = try await harness.run()
    #expect(try await harness.buckets() == first)
    #expect(counts.map(\.rowsOut) == [0, 0, 0, 0], "hourly, monthly, purge and thinning all no-ops")
  }

  @Test("a late hour of a day already rolled up is added to its daily row")
  func lateHourAdds() async throws {
    let harness = try await Harness()
    try await harness.seed { db in try Self.bucket("2026-08-18T01:00:00.000Z").insert(db) }
    _ = try await harness.run()
    try await harness.seed { db in try Self.bucket("2026-08-18T05:00:00.000Z", est: 4, base: 100).insert(db) }
    _ = try await harness.run()
    let daily = try await harness.buckets().filter { $0.bucketWidth == "1d" }
    #expect(daily.count == 1 && daily.first?.estCostCents == 11 && daily.first?.inputUncached == 110)
  }

  @Test("the day of an anchor stays hourly: spend since the anchor reads the hours after it (05)")
  func anchorDayStaysHourly() async throws {
    let harness = try await Harness()
    try await harness.seed { db in
      try Self.bucket("2026-08-17T10:00:00.000Z").insert(db)
      try Self.bucket("2026-08-18T10:00:00.000Z").insert(db)
      try LedgerEventRecord(id: "anchor-1", accountId: Self.acct, ts: "2026-08-18T09:30:00.000Z", kind: "anchor",
                            amountCents: 5_000, currency: "USD", note: nil, source: "user").insert(db)
    }
    _ = try await harness.run()
    let rows = try await harness.buckets()
    #expect(rows.map { "\($0.bucketWidth) \($0.bucketStart.prefix(10))" } == ["1d 2026-08-17", "1h 2026-08-18"])
  }

  @Test("daily → monthly: whole months older than 400 d, Σ exact, daily rows kept; recomputed, never added twice")
  func monthly() async throws {
    let harness = try await Harness()
    try await harness.seed { db in
      try Self.bucket("2025-08-31T00:00:00.000Z", width: "1d", source: "rollup", est: 1).insert(db)
      try Self.bucket("2025-09-01T00:00:00.000Z", width: "1d", source: "rollup", est: 2).insert(db)
      try Self.bucket("2025-09-30T00:00:00.000Z", width: "1d", source: "rollup", est: 3, base: 40).insert(db)
      try Self.bucket("2025-09-15T00:00:00.000Z", width: "1d", source: "harness", est: 4).insert(db)
      try Self.bucket("2025-10-01T00:00:00.000Z", width: "1d", source: "rollup", est: 5).insert(db)
    }
    let daily = try await harness.sums("bucket_width = '1d' AND bucket_start < '2025-10-01'")
    let counts = try await harness.run()
    #expect(counts[1] == RollupCount(tier: "monthly", rowsIn: 4, rowsOut: 3))
    #expect(try await harness.sums("bucket_width = '1mo'") == daily)
    let months = try await harness.buckets().filter { $0.bucketWidth == "1mo" }
    #expect(months.map { "\($0.bucketStart.prefix(7)) \($0.source) \($0.estCostCents ?? -1)" }
            == ["2025-08 rollup 1", "2025-09 harness 4", "2025-09 rollup 5"], "October is not over 400 days old yet")
    #expect(try await harness.buckets().filter { $0.bucketWidth == "1d" }.count == 5, "03: kept alongside")
    try await harness.seed { db in
      try db.execute(sql: "UPDATE usage_bucket SET est_cost_cents = 9 WHERE bucket_width = '1d' AND est_cost_cents = 2")
    }
    _ = try await harness.run()
    #expect(try await harness.buckets().first { $0.bucketWidth == "1mo" && $0.source == "rollup"
      && $0.bucketStart.hasPrefix("2025-09") }?.estCostCents == 12, "recomputed from the daily rows: 9 + 3")
  }

  @Test("the summary's readers skip monthly rows, so a window back to an old anchor counts each day once")
  func readersSkipMonthly() async throws {
    let harness = try await Harness()
    try await harness.seed { db in
      try LedgerEventRecord(id: "anchor-old", accountId: Self.acct, ts: "2025-07-01T00:00:00.000Z", kind: "anchor",
                            amountCents: 100_000, currency: "USD", note: nil, source: "user").insert(db)
      for day in ["2025-07-02", "2025-08-10", "2025-09-01"] {
        try Self.bucket(day + "T00:00:00.000Z", width: "1d", source: "rollup").insert(db)
      }
    }
    let before = try await harness.repository.database.read { try SummaryInputs.fetch($0) }
    _ = try await harness.run()
    #expect(try await harness.buckets().filter { $0.bucketWidth == "1mo" }.count == 3)
    let after = try await harness.repository.database.read { try SummaryInputs.fetch($0) }
    #expect(after.usageDays == before.usageDays && after.keyUsageDays == before.keyUsageDays)
    #expect(after.modelUsageDays == before.modelUsageDays && after.pricedModels == before.pricedModels)
    #expect(before.usageDays.count == 3)
  }

  static func event(_ id: String, ts: String) -> HarnessEventRecord {
    HarnessEventRecord(provider: "openai", requestId: id, accountId: acct, appTag: "weather", providerKeyId: nil,
                       keyHint: nil, ts: ts, futureTs: false, model: "gpt-x", status: 1, usageJson: "{}",
                       classesJson: nil, estCostCents: 1, sourceFile: "a.jsonl", sourceLine: 1, ingestedAt: ts)
  }

  @Test("harness_event older than tb.retention.rawHarnessDays is deleted; newer lines stay")
  func purge() async throws {
    let harness = try await Harness()
    try await harness.seed { db in
      try Self.event("old", ts: "2026-10-18T23:59:59.999Z").insert(db)
      try Self.event("edge", ts: "2026-10-19T00:00:00.000Z").insert(db)
      try Self.event("new", ts: "2026-11-17T08:00:00.000Z").insert(db)
    }
    let counts = try await harness.run()
    #expect(counts[2] == RollupCount(tier: "harness_event", rowsIn: 3, rowsOut: 1))
    let left = try await harness.repository.database.read { db in
      try String.fetchAll(db, sql: "SELECT request_id FROM harness_event ORDER BY request_id")
    }
    #expect(left == ["edge", "new"])
  }

  @Test("purge after roll-up only: a failed roll-up throws before any raw event is deleted")
  func purgeAfterRollupOnly() async throws {
    let store = FailingRollup()
    await #expect(throws: RollupBroken.self) {
      try await Rollup(store: store).run(Self.policy, now: Self.now)
    }
    #expect(await store.calls == ["hourly"])
  }

  static func snapshot(_ ts: String, _ currency: String, _ cents: Int64) -> BalanceSnapshotRecord {
    BalanceSnapshotRecord(accountId: acct, ts: ts, currency: currency, amountCents: cents, grantedCents: nil,
                          toppedUpCents: nil, isAvailable: true)
  }

  /// 11-01 (past the 7 d window) four polls in two currencies; 11-12 (inside) three polls.
  static func snapshots(_ db: GRDB.Database) throws {
    for (index, time) in ["00:00:30", "06:00:00", "12:00:00", "23:59:00"].enumerated() {
      try snapshot("2026-11-01T\(time).000Z", "USD", 1_000 - Int64(index) * 10).insert(db)
      try snapshot("2026-11-01T\(time).000Z", "CNY", 7_000 - Int64(index) * 70).insert(db)
    }
    for time in ["01:00:00", "02:00:00", "03:00:00"] { try snapshot("2026-11-12T\(time).000Z", "USD", 500).insert(db) }
  }

  @Test("balance thinning: past 7 d, each day keeps its first and last snapshot per currency; recent days untouched")
  func balanceThinning() async throws {
    let harness = try await Harness()
    try await harness.seed { db in try Self.snapshots(db) }
    let lastOfDay = try await harness.repository.database.read { try BalanceDay.fetch($0, since: "2026-10-01") }
    let counts = try await harness.run()
    #expect(counts[3] == RollupCount(tier: "balance_snapshot", rowsIn: 8, rowsOut: 4))
    let kept = try await harness.repository.fetchBalanceSnapshots(accountID: Self.acct).map { "\($0.ts) \($0.currency)" }
    #expect(kept == ["2026-11-01T00:00:30.000Z CNY", "2026-11-01T00:00:30.000Z USD", "2026-11-01T23:59:00.000Z CNY",
                     "2026-11-01T23:59:00.000Z USD", "2026-11-12T01:00:00.000Z USD", "2026-11-12T02:00:00.000Z USD",
                     "2026-11-12T03:00:00.000Z USD"])
    #expect(try await harness.repository.database.read { try BalanceDay.fetch($0, since: "2026-10-01") } == lastOfDay,
            "the day's last balance (the deltas' input) is kept")
  }

  @Test("one db.rollup {tier, rows_in, rows_out} per tier, in order")
  func logs() async throws {
    let harness = try await Harness()
    try await harness.seed { db in for row in Self.hourlyRows { try row.insert(db) } }
    _ = try await harness.run()
    let records = await harness.store.records(.dbRollup)
    #expect(records.map(\.ctx["tier"]) == ["hourly", "monthly", "harness_event", "balance_snapshot"])
    #expect(records.first?.ctx["rows_in"] == .int(9) && records.first?.ctx["rows_out"] == .int(5))
    #expect(records.allSatisfy { $0.lvl == .info && $0.cat == .db })
  }

  @Test("cut-offs are UTC day starts; the monthly one is the first of the month 400 days back")
  func cutoffs() {
    let cut = Rollup.Cutoffs(Self.policy, now: Self.now)
    #expect(cut.hourly == "2026-08-20T00:00:00.000Z" && cut.monthly == "2025-10-01T00:00:00.000Z")
    #expect(cut.harness == "2026-10-19T00:00:00.000Z" && cut.balance == "2026-11-11T00:00:00.000Z")
  }
}

/// A store whose hourly roll-up fails: nothing after it may run.
actor FailingRollup: RetentionRepository, AccountRepository {
  var calls: [String] = []
  func insertAccount(_ account: AccountRecord) async throws {}
  func updateAccount(_ account: AccountRecord) async throws {}
  func deleteAccount(id: String) async throws {}
  func fetchAccounts() async throws -> [AccountRecord] { [OpenAIHarness.account] }
  func rollupHourly(accountID: String, before: String) async throws -> RollupCount {
    calls.append("hourly")
    throw RollupBroken()
  }
  func rollupMonthly(accountID: String, before: String) async throws -> RollupCount {
    calls.append("monthly")
    return RollupCount(tier: "monthly")
  }
  func purgeHarnessEvents(before: String) async throws -> RollupCount {
    calls.append("purge")
    return RollupCount(tier: "harness_event")
  }
  func thinBalanceSnapshots(accountID: String, before: String) async throws -> RollupCount {
    calls.append("thin")
    return RollupCount(tier: "balance_snapshot")
  }
}

struct RollupBroken: Error {}
