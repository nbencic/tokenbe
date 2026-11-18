import Foundation

/// `Export CSV (all tables)…` (03 § Durability "CSV export"; 14 § Stage 9.2): one RFC 4180 file per exported table,
/// named after the table (`usage_bucket.csv`), in a new folder. The header row is the column names; a value is the
/// column's stored text (integers as digits, booleans as `0`/`1`, NULL empty), so the files load back into any tool.
/// Quoting, CRLF and UTF-8 without a BOM are `ViewCSVExporter`'s. Logs `db.export {kind=csv_tables, path, rows}` (07).
public enum TablesCSVExporter {
  /// Writes every table into `folder` (created when missing). Returns Σ data rows. A failure is thrown for the caller.
  @discardableResult
  public static func export(from store: any DataTransferRepository, to folder: URL, log: EventLog = EventLog())
    async throws -> Int {
    let tables = try await store.exportTables()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (table, csv) in tables {
      try ViewCSVExporter.data(csv).write(to: folder.appendingPathComponent(table.table + ".csv"), options: .atomic)
    }
    let rows = tables.reduce(0) { $0 + $1.csv.rows.count }
    log.emit(.info, .dbExport, cat: .db, msg: "tables exported as CSV", ctx: [
      "kind": .string("csv_tables"), "path": .string(folder.path), "rows": .int(rows)
    ])
    return rows
  }

  /// `TokenBe-tables-2026-11-18` (the UTC day).
  public static func folderName(date: String) -> String { "TokenBe-tables-\(date)" }
}
