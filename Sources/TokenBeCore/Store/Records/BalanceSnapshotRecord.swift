import Foundation
import GRDB

/// A row of `balance_snapshot` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct BalanceSnapshotRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "balance_snapshot"

  public var accountId: String
  public var ts: String
  public var currency: String
  public var amountCents: Int64
  public var grantedCents: Int64?
  public var toppedUpCents: Int64?
  public var isAvailable: Bool?

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case ts
    case currency
    case amountCents = "amount_cents"
    case grantedCents = "granted_cents"
    case toppedUpCents = "topped_up_cents"
    case isAvailable = "is_available"
  }
}
