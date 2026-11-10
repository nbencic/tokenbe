import Foundation
import GRDB

/// A row of `app_binding` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct AppBindingRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "app_binding"

  public var appId: String
  public var accountId: String
  public var kind: String
  /// provider_key_id or harness tag
  public var value: String

  enum CodingKeys: String, CodingKey {
    case appId = "app_id"
    case accountId = "account_id"
    case kind
    case value
  }
}
