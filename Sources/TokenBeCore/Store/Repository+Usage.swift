import Foundation
import GRDB

/// One usage page to store (14 § Stage 3.4 step 5): its rows, the results' sum for V2, and where the page sequence
/// stands.
public struct UsagePageWrite: Sendable {
  public var accountID: String
  public var job: Job
  public var rows: [UsageBucketRecord]
  /// Σ of the page's normalized results before they became rows (04 V2).
  public var expected: TokenClasses
  /// The next page's cursor; nil when this was the last page.
  public var cursor: String?
  /// The page's body, already redacted (R8).
  public var lastRaw: String

  public init(accountID: String, job: Job = .usage, rows: [UsageBucketRecord], expected: TokenClasses,
              cursor: String?, lastRaw: String) {
    self.accountID = accountID
    self.job = job
    self.rows = rows
    self.expected = expected
    self.cursor = cursor
    self.lastRaw = lastRaw
  }
}

/// `usage_bucket` rows (03).
public protocol UsageRepository: Sendable {
  /// In ONE transaction: upsert the rows (a row with the same primary key is replaced), check V2 — the rows now
  /// stored under the page's keys add up to `expected` — and save `poll_state.cursor` and `last_raw`. A V2
  /// mismatch rolls everything back and throws `StoreError.writeIncomplete` (04 § Invariants, Q-029).
  func writeUsagePage(_ page: UsagePageWrite) async throws
  /// Oldest bucket first.
  func fetchUsageBuckets(accountID: String) async throws -> [UsageBucketRecord]
}

extension GRDBRepository {
  public func writeUsagePage(_ page: UsagePageWrite) async throws {
    try await database.write("writeUsagePage") { db in
      for row in page.rows {
        try row.insert(db, onConflict: .replace)
      }
      var written = TokenClasses()
      var seen = Set<[String]>()
      for row in page.rows {
        let key = [row.bucketStart, row.bucketWidth, row.model, row.providerKeyId, row.serviceTier, row.source]
        guard seen.insert(key).inserted else { continue }
        let stored = try UsageBucketRecord.fetchOne(db, key: [
          "account_id": row.accountId, "bucket_start": row.bucketStart, "bucket_width": row.bucketWidth,
          "model": row.model, "provider_key_id": row.providerKeyId, "service_tier": row.serviceTier,
          "source": row.source
        ])
        if let stored { written += stored.classes }
      }
      guard written == page.expected else {
        throw StoreError.writeIncomplete(expected: page.expected.tokens, written: written.tokens)
      }
      try PollStateRecord.save(db, accountID: page.accountID, job: page.job, cursor: page.cursor,
                               lastRaw: page.lastRaw)
    }
  }

  public func fetchUsageBuckets(accountID: String) async throws -> [UsageBucketRecord] {
    try await database.read { db in
      try UsageBucketRecord.filter(Column("account_id") == accountID)
        .order(Column("bucket_start"), Column("model"), Column("provider_key_id"), Column("service_tier"))
        .fetchAll(db)
    }
  }
}

extension PollStateRecord {
  /// Saves the paging position and the last body in the same transaction as the page's rows.
  static func save(_ db: GRDB.Database, accountID: String, job: Job, cursor: String?, lastRaw: String) throws {
    try db.execute(
      sql: "UPDATE poll_state SET cursor = ?, last_raw = ? WHERE account_id = ? AND job = ?",
      arguments: [cursor, Data(lastRaw.utf8), accountID, job.rawValue]
    )
  }
}
