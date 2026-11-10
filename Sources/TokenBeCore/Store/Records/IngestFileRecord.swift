import Foundation
import GRDB

/// A row of `ingest_file` (03 § Schema, migration 001). Timestamps are RFC3339 UTC strings (`DBTime`); money is
/// integer cents.
public struct IngestFileRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "ingest_file"

  public var path: String
  public var inode: Int64
  /// bytes fully processed
  public var offset: Int64
  public var lastSize: Int64
  public var lastMtime: String
  public var state: String
  public var linesOk: Int64
  public var linesBad: Int64
  public var linesDup: Int64

  enum CodingKeys: String, CodingKey {
    case path
    case inode
    case offset
    case lastSize = "last_size"
    case lastMtime = "last_mtime"
    case state
    case linesOk = "lines_ok"
    case linesBad = "lines_bad"
    case linesDup = "lines_dup"
  }
}
