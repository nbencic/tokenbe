import Foundation
import GRDB

/// What the diagnostics bundle reads from the database (07 § Diagnostics bundle; 14 § Stage 9.3). Never the file
/// itself, and nothing from the Keychain.
public struct DiagnosticsSnapshot: Sendable, Equatable {
  /// `.schema`: every stored `CREATE` statement, tables first, each ended by `;`.
  public var schemaSQL: String
  /// Rows per table (`sqlite_*` tables excluded), by table name.
  public var tableRows: [String: Int]
  public var sizeBytes: Int
  public var pageCount: Int
  public var pageSize: Int
  public var freelistCount: Int
  /// Every `poll_state` row; `last_raw` was redacted before it was stored (12 § R8).
  public var pollStates: [PollStateRecord]
  public var priceOverrides: [PriceOverrideRecord]

  public init(schemaSQL: String = "", tableRows: [String: Int] = [:], sizeBytes: Int = 0, pageCount: Int = 0,
              pageSize: Int = 0, freelistCount: Int = 0, pollStates: [PollStateRecord] = [],
              priceOverrides: [PriceOverrideRecord] = []) {
    self.schemaSQL = schemaSQL
    self.tableRows = tableRows
    self.sizeBytes = sizeBytes
    self.pageCount = pageCount
    self.pageSize = pageSize
    self.freelistCount = freelistCount
    self.pollStates = pollStates
    self.priceOverrides = priceOverrides
  }
}

public protocol DiagnosticsRepository: Sendable {
  /// One read of the schema, the stats, `poll_state` and `price_override`.
  func diagnosticsSnapshot() async throws -> DiagnosticsSnapshot
}

extension GRDBRepository {
  public func diagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
    let size = AppDatabase.fileSize(database.url)
    return try await database.read { db in
      let statements = try String.fetchAll(db, sql: """
        SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'
        ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name
        """)
      var rows: [String: Int] = [:]
      for table in try String.fetchAll(db, sql: """
        SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name
        """) {
        rows[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table)\"") ?? 0
      }
      return DiagnosticsSnapshot(
        schemaSQL: statements.map { $0 + ";" }.joined(separator: "\n") + "\n", tableRows: rows, sizeBytes: size,
        pageCount: try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0,
        pageSize: try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0,
        freelistCount: try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0,
        pollStates: try PollStateRecord.order(Column("account_id"), Column("job")).fetchAll(db),
        priceOverrides: try PriceOverrideRecord.order(Column("model")).fetchAll(db))
    }
  }
}
