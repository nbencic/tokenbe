import Foundation
import GRDB

/// `cost_bucket` rows (03).
public protocol CostRepository: Sendable {
  /// In one transaction: for every day present in `rows`, delete that day's rows and insert the new ones. A
  /// re-fetch replaces a provisional day whole, so a group that disappeared does not linger next to `total` (05).
  func replaceCostDays(accountID: String, rows: [CostBucketRecord]) async throws
  /// By day, then group kind and key.
  func fetchCostBuckets(accountID: String) async throws -> [CostBucketRecord]
}

extension GRDBRepository {
  public func replaceCostDays(accountID: String, rows: [CostBucketRecord]) async throws {
    try await database.write("replaceCostDays") { db in
      for day in Set(rows.map(\.day)) {
        try CostBucketRecord.filter(Column("account_id") == accountID && Column("day") == day).deleteAll(db)
      }
      for row in rows {
        try row.insert(db)
      }
    }
  }

  public func fetchCostBuckets(accountID: String) async throws -> [CostBucketRecord] {
    try await database.read { db in
      try CostBucketRecord.filter(Column("account_id") == accountID)
        .order(Column("day"), Column("group_kind"), Column("group_key")).fetchAll(db)
    }
  }
}
