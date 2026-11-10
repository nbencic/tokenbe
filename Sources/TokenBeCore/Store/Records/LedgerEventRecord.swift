import Foundation
import GRDB

/// A row of `ledger_event` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct LedgerEventRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "ledger_event"

  public var id: String
  public var accountId: String
  public var ts: String
  public var kind: String
  public var amountCents: Int64?
  public var currency: String?
  public var note: String?
  public var source: String

  enum CodingKeys: String, CodingKey {
    case id
    case accountId = "account_id"
    case ts
    case kind
    case amountCents = "amount_cents"
    case currency
    case note
    case source
  }
}
