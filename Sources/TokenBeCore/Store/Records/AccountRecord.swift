import Foundation
import GRDB

/// A row of `account` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct AccountRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "account"

  public var id: String
  public var provider: String
  public var label: String
  /// Keychain account name; never the secret
  public var keychainRef: String
  public var balanceMode: String
  public var currency: String
  /// JSON Capabilities (04)
  public var capabilities: String
  public var orgId: String?
  public var orgName: String?
  public var autoReloadEnabled: Bool
  public var autoReloadToCents: Int64?
  public var autoReloadBelowCents: Int64?
  /// 1 = scheduler skips every job for this account (09)
  public var paused: Bool
  /// JSON {usage?,cost?,balance?,keys?} seconds; NULL = globals (09)
  public var intervalOverrideJson: String?
  public var createdAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case provider
    case label
    case keychainRef = "keychain_ref"
    case balanceMode = "balance_mode"
    case currency
    case capabilities
    case orgId = "org_id"
    case orgName = "org_name"
    case autoReloadEnabled = "auto_reload_enabled"
    case autoReloadToCents = "auto_reload_to_cents"
    case autoReloadBelowCents = "auto_reload_below_cents"
    case paused
    case intervalOverrideJson = "interval_override_json"
    case createdAt = "created_at"
  }
}
