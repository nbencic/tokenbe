import Foundation
import GRDB

/// A row of `provider_key` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct ProviderKeyRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "provider_key"

  public var accountId: String
  /// OpenAI key_…, Anthropic apikey_…, OpenRouter hash
  public var providerKeyId: String
  public var name: String?
  public var redacted: String?
  public var projectId: String?
  public var workspaceId: String?
  public var status: String
  public var firstSeenAt: String
  public var lastSeenAt: String

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case providerKeyId = "provider_key_id"
    case name
    case redacted
    case projectId = "project_id"
    case workspaceId = "workspace_id"
    case status
    case firstSeenAt = "first_seen_at"
    case lastSeenAt = "last_seen_at"
  }
}
