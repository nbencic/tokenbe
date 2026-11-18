import Foundation

/// `Import…` (03 § Durability, O-17; 14 § Stage 9.2): reads a document written by `JSONExporter` and inserts it into
/// an empty database in one transaction. A refusal (`ImportRefusal`: not empty, another schema version), an unreadable
/// file or a document that does not decode writes nothing and logs `db.import_failed {path, err}`; a success logs
/// `db.import {path, rows}` (07).
public enum JSONImporter {
  /// Decodes 03's document. Unknown keys are ignored; a missing table or column is a decoding error.
  public static func document(_ data: Data) throws -> ExportDocument {
    try JSONDecoder().decode(ExportDocument.self, from: data)
  }

  /// Returns the document's rows. Throws whatever stopped the import, after logging it.
  @discardableResult
  public static func run(_ url: URL, into store: any DataTransferRepository, log: EventLog = EventLog()) async throws
    -> Int {
    do {
      let rows = try await store.importDocument(document(Data(contentsOf: url)))
      log.emit(.info, .dbImport, cat: .db, msg: "data imported", ctx: ["path": .string(url.path), "rows": .int(rows)])
      return rows
    } catch {
      log.emit(.error, .dbImportFailed, cat: .db, msg: "import failed", err: error, ctx: ["path": .string(url.path)])
      throw error
    }
  }
}
