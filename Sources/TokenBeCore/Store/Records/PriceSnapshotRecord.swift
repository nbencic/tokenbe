import Foundation
import GRDB

/// A row of `price_snapshot` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct PriceSnapshotRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "price_snapshot"

  /// YYYY-MM-DD of fetch, or 'bundled-<appversion>'
  public var version: String
  public var fetchedAt: String
  public var etag: String?
  public var sha256: String
  public var json: Data
  public var isCurrent: Bool

  enum CodingKeys: String, CodingKey {
    case version
    case fetchedAt = "fetched_at"
    case etag
    case sha256
    case json
    case isCurrent = "is_current"
  }
}
