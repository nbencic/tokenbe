import Foundation
import GRDB

/// A row of `cost_bucket` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct CostBucketRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "cost_bucket"

  public var accountId: String
  /// YYYY-MM-DD UTC
  public var day: String
  public var groupKind: String
  public var groupKey: String
  public var amountCents: Int64
  public var currency: String
  public var provisional: Bool
  public var fetchedAt: String

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case day
    case groupKind = "group_kind"
    case groupKey = "group_key"
    case amountCents = "amount_cents"
    case currency
    case provisional
    case fetchedAt = "fetched_at"
  }
}
