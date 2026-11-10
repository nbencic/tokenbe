import Foundation
import GRDB

/// A row of `app` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct AppRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "app"

  public var id: String
  /// immutable harness tag / slug (06 regex)
  public var name: String
  /// editable; defaults to name
  public var displayName: String
  public var createdAt: String
  /// 1 = created from an unknown harness tag
  public var isAuto: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case displayName = "display_name"
    case createdAt = "created_at"
    case isAuto = "is_auto"
  }
}
