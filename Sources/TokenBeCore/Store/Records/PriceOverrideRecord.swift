import Foundation
import GRDB

/// A row of `price_override` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct PriceOverrideRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "price_override"

  public var model: String
  /// same keys as price feed entry
  public var json: String
  public var updatedAt: String

  enum CodingKeys: String, CodingKey {
    case model
    case json
    case updatedAt = "updated_at"
  }
}
