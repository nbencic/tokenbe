import Foundation
import Testing
@testable import TokenBeCore

/// 11 `CSVExporterTests` (14 § Stage 8.3, O-4): RFC 4180 quoting, the header row, CRLF records, UTF-8 without a BOM,
/// the written file and its `db.export` line, and a safe default file name (Q-053).
@Suite struct CSVExporterTests {
  static let table = CSVTable(header: ["App", "Key", "Spend"], rows: [
    ["news-digest", "…a9f2", "≈ $1,234.50"],
    ["say \"hi\"", "—", "$0.30"],
    ["two\nlines", "", "CN¥ 12.00"]
  ])

  @Test("fields with a comma, quote, CR or LF are quoted, quotes doubled; others are bare")
  func quoting() {
    #expect(ViewCSVExporter.field("plain text") == "plain text")
    #expect(ViewCSVExporter.field("≈ $1,234.50") == "\"≈ $1,234.50\"")
    #expect(ViewCSVExporter.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
    #expect(ViewCSVExporter.field("a\nb") == "\"a\nb\"")
    #expect(ViewCSVExporter.field("a\rb") == "\"a\rb\"")
    #expect(ViewCSVExporter.field("a\r\nb") == "\"a\r\nb\"", "CRLF is one Character in Swift")
    #expect(ViewCSVExporter.field("") == "")
  }

  @Test("the header row comes first and every record ends with CRLF")
  func layout() {
    let text = ViewCSVExporter.csv(Self.table)
    #expect(text == "App,Key,Spend\r\n"
      + "news-digest,…a9f2,\"≈ $1,234.50\"\r\n"
      + "\"say \"\"hi\"\"\",—,$0.30\r\n"
      + "\"two\nlines\",,CN¥ 12.00\r\n")
    #expect(ViewCSVExporter.csv(CSVTable(header: ["A"], rows: [])) == "A\r\n", "an empty view is its header")
  }

  @Test("UTF-8 without a byte-order mark")
  func encoding() throws {
    let data = ViewCSVExporter.data(Self.table)
    #expect(Array(data.prefix(3)) != [0xEF, 0xBB, 0xBF])
    #expect(String(data: data, encoding: .utf8) == ViewCSVExporter.csv(Self.table))
    #expect(Array(data.prefix(3)) == Array("App".utf8))
  }

  @Test("write: the file holds the bytes; db.export logs kind, path and rows")
  func write() async throws {
    let harness = try StoreHarness()
    let temp = try TempDirectory()
    let folder = temp.url
    let url = folder.appendingPathComponent("view.csv")
    try ViewCSVExporter.write(Self.table, to: url, log: EventLog(pipeline: harness.pipeline))
    let written = try Data(contentsOf: url)
    #expect(written == ViewCSVExporter.data(Self.table))
    let record = try #require(await harness.records(.dbExport).first)
    #expect(record.lvl == .info && record.ctx["kind"] == "csv_view" && record.ctx["rows"] == 3)
    if case .string(let path) = record.ctx["path"] { #expect(path.hasSuffix("view.csv")) } else { Issue.record("path") }
    let missing = folder.appendingPathComponent("no-such-folder/view.csv")
    #expect(throws: (any Error).self) { try ViewCSVExporter.write(Self.table, to: missing) }
    #expect(await harness.records(.dbExport).count == 1, "a failed write logs no export")
  }

  @Test("the default file name: page, label and range, with path characters made safe")
  func fileName() {
    #expect(ViewCSVExporter.fileName(["Overview", "7 d"], date: "2026-11-17") == "TokenBe-Overview-7-d-2026-11-17.csv")
    #expect(ViewCSVExporter.fileName(["Work/Main: OpenAI", "By app", "30 d"], date: "2026-11-17")
      == "TokenBe-Work-Main-OpenAI-By-app-30-d-2026-11-17.csv")
    #expect(ViewCSVExporter.fileName(["a\u{0007}b"], date: "x") == "TokenBe-a-b-x.csv")
  }
}
