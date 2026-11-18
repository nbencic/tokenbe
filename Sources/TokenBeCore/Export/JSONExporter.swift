import Foundation

/// `Export data (JSON)…` (03 § Durability, O-5; 14 § Stage 9.2): the document with its keys in 03's order
/// (`schema_version`, `exported_at`, then the tables), each record's keys sorted, UTF-8, written atomically. Secrets are
/// never in it: the database holds none (R8). Logs `db.export {kind=json, path, rows}` (07).
public enum JSONExporter {
  /// The document's bytes. One line per top-level key, so a diff of two exports reads table by table.
  public static func data(_ document: ExportDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    func part<T: Encodable>(_ key: ExportDocument.CodingKeys, _ value: T) throws -> Data {
      Data("\"\(key.rawValue)\":".utf8) + (try encoder.encode(value))
    }
    let parts = [
      try part(.schemaVersion, document.schemaVersion), try part(.exportedAt, document.exportedAt),
      try part(.accounts, document.accounts), try part(.providerKeys, document.providerKeys),
      try part(.apps, document.apps), try part(.appBindings, document.appBindings),
      try part(.usageBuckets, document.usageBuckets), try part(.costBuckets, document.costBuckets),
      try part(.balanceSnapshots, document.balanceSnapshots), try part(.ledgerEvents, document.ledgerEvents),
      try part(.priceOverrides, document.priceOverrides)
    ]
    return Data("{\n".utf8) + parts.joined(separator: Data(",\n".utf8)) + Data("\n}\n".utf8)
  }

  /// Reads the database, writes the file, logs. Returns the rows written. A failure is thrown for the caller to show.
  @discardableResult
  public static func export(from store: any DataTransferRepository, to url: URL, now: Date = Date(),
                            log: EventLog = EventLog()) async throws -> Int {
    let document = try await store.exportDocument(exportedAt: DBTime.string(now))
    try data(document).write(to: url, options: .atomic)
    log.emit(.info, .dbExport, cat: .db, msg: "data exported as JSON", ctx: [
      "kind": .string("json"), "path": .string(url.path), "rows": .int(document.rows)
    ])
    return document.rows
  }

  /// `TokenBe-export-2026-11-18.json` (the UTC day).
  public static func fileName(date: String) -> String { "TokenBe-export-\(date).json" }
}
