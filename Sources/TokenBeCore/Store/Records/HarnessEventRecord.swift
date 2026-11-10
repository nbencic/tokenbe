import Foundation
import GRDB

/// A row of `harness_event` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct HarnessEventRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "harness_event"

  public var provider: String
  public var requestId: String
  public var accountId: String?
  public var appTag: String
  /// resolved from key_hint when a provider_key.redacted ends with the same 4 chars
  public var providerKeyId: String?
  /// last 4 chars only, never more
  public var keyHint: String?
  public var ts: String
  /// 1 when ts > ingested_at + 5 min (06)
  public var futureTs: Bool
  public var model: String
  /// 1 = ok, 0 = error (06 status field)
  public var status: Int64
  /// verbatim provider usage object
  public var usageJson: String
  /// normalized TokenClasses, NULL if normalization failed
  public var classesJson: String?
  public var estCostCents: Int64?
  public var sourceFile: String
  public var sourceLine: Int64
  public var ingestedAt: String

  enum CodingKeys: String, CodingKey {
    case provider
    case requestId = "request_id"
    case accountId = "account_id"
    case appTag = "app_tag"
    case providerKeyId = "provider_key_id"
    case keyHint = "key_hint"
    case ts
    case futureTs = "future_ts"
    case model
    case status
    case usageJson = "usage_json"
    case classesJson = "classes_json"
    case estCostCents = "est_cost_cents"
    case sourceFile = "source_file"
    case sourceLine = "source_line"
    case ingestedAt = "ingested_at"
  }
}
