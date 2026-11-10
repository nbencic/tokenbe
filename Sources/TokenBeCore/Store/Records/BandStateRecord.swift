import Foundation
import GRDB

/// A row of `band_state` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct BandStateRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "band_state"

  public var accountId: String
  /// healthy|watch|low|critical|unknown
  public var band: String
  public var since: String
  /// remaining, burn_7d, burn_today, floor → for log traceability
  public var inputsJson: String

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case band
    case since
    case inputsJson = "inputs_json"
  }
}
