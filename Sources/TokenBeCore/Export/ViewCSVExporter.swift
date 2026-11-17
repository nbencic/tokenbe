import Foundation

/// The table a Dashboard page shows, as the cells it prints: the header row of 08's column titles, then one row of
/// strings per table row (O-4: "exactly the visible columns"). The App builds it with the same cell function the
/// view draws from, so the file and the screen cannot disagree (14 § Stage 8.3, Q-053).
public struct CSVTable: Sendable, Equatable {
  public var header: [String]
  public var rows: [[String]]

  public init(header: [String], rows: [[String]]) {
    self.header = header
    self.rows = rows
  }
}

/// 14 § Stage 8.3 (O-4): the toolbar's `Export…` writes the current view as RFC 4180 CSV: a header row, fields
/// quoted when they hold a comma, a double quote, CR or LF (a quote doubled inside), records ended by CRLF, UTF-8
/// without a byte-order mark. Each export logs `db.export {kind=csv_view, path, rows}` (07).
public enum ViewCSVExporter {
  /// The file's text. Every record, the header included, ends with CRLF (RFC 4180 § 2.1–2.2).
  public static func csv(_ table: CSVTable) -> String {
    ([table.header] + table.rows).map { $0.map(field).joined(separator: ",") + "\r\n" }.joined()
  }

  /// One field (RFC 4180 § 2.5–2.7): quoted only when it must be.
  static func field(_ value: String) -> String {
    guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" || $0 == "\r\n" }) else {
      return value
    }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  /// The file's bytes: UTF-8, no BOM.
  public static func data(_ table: CSVTable) -> Data {
    Data(csv(table).utf8)
  }

  /// Writes the file atomically and logs `db.export`. A failure is thrown for the caller to show (`ui.error`).
  public static func write(_ table: CSVTable, to url: URL, log: EventLog = EventLog()) throws {
    try data(table).write(to: url, options: .atomic)
    log.emit(.info, .dbExport, cat: .db, msg: "view exported as CSV", ctx: [
      "kind": .string("csv_view"), "path": .string(url.path), "rows": .int(table.rows.count)
    ])
  }

  /// A file name from page and label parts: characters a path or Finder would reject or misread (`/`, `:`, control
  /// characters, a leading dot) become `-`, and runs of `-` and spaces collapse (labels are user-typed).
  public static func fileName(_ parts: [String], date: String) -> String {
    let joined = (["TokenBe"] + parts + [date]).joined(separator: " ")
    var name = ""
    for scalar in joined.unicodeScalars {
      let unsafe = scalar == "/" || scalar == ":" || scalar == "\\" || CharacterSet.controlCharacters.contains(scalar)
      let next: Character = unsafe || scalar == " " ? "-" : Character(scalar)
      if next == "-", name.hasSuffix("-") { continue }
      name.append(next)
    }
    let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    return (trimmed.isEmpty ? "TokenBe" : trimmed) + ".csv"
  }
}
