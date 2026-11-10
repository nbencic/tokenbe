import Foundation
import GRDB

/// A row of `usage_bucket` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct UsageBucketRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "usage_bucket"

  public var accountId: String
  /// RFC3339 UTC, aligned to width
  public var bucketStart: String
  public var bucketWidth: String
  /// '*' when unknown (OpenRouter per-key rows)
  public var model: String
  /// '' when not grouped
  public var providerKeyId: String
  public var serviceTier: String
  public var source: String
  public var inputUncached: Int64
  public var cacheWrite5m: Int64
  public var cacheWrite1h: Int64
  public var cacheRead: Int64
  public var output: Int64
  public var reasoning: Int64
  public var requests: Int64
  /// NULL when any class is unpriced
  public var estCostCents: Int64?
  /// 1 when est_cost_cents is NULL because of price book
  public var unpriced: Bool
  /// 1 until bucket_end + usageLag < fetched_at
  public var provisional: Bool
  public var fetchedAt: String

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case bucketStart = "bucket_start"
    case bucketWidth = "bucket_width"
    case model
    case providerKeyId = "provider_key_id"
    case serviceTier = "service_tier"
    case source
    case inputUncached = "input_uncached"
    case cacheWrite5m = "cache_write_5m"
    case cacheWrite1h = "cache_write_1h"
    case cacheRead = "cache_read"
    case output
    case reasoning
    case requests
    case estCostCents = "est_cost_cents"
    case unpriced
    case provisional
    case fetchedAt = "fetched_at"
  }
}
