import Foundation
import GRDB

/// A row of `poll_state` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct PollStateRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "poll_state"

  public var accountId: String
  /// 'usage'|'cost'|'balance'|'keys'
  public var job: String
  public var lastAttemptAt: String?
  public var lastSuccessAt: String?
  public var lastErrorClass: String?
  public var lastErrorMessage: String?
  public var consecutiveFailures: Int64
  public var circuitOpenUntil: String?
  /// provider paging cursor if a page sequence was interrupted
  public var cursor: String?
  /// ≤ 64 KB, redacted
  public var lastRaw: Data?

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case job
    case lastAttemptAt = "last_attempt_at"
    case lastSuccessAt = "last_success_at"
    case lastErrorClass = "last_error_class"
    case lastErrorMessage = "last_error_message"
    case consecutiveFailures = "consecutive_failures"
    case circuitOpenUntil = "circuit_open_until"
    case cursor
    case lastRaw = "last_raw"
  }
}
