import Foundation
import GRDB
import Synchronization
import Testing
@testable import TokenBeCore

/// 11 `DiagnosticsBundleTests` (14 § Stage 9.3; 07 § Diagnostics bundle): the zip holds exactly 07's files and the
/// newest 3 logs; never the database or the test keychain; `poll_state.last_raw` is redacted; no key pattern in any
/// file (SEC-1's grep); `app.diagnostics_exported`; the file name; `ditto`'s failure (Q-057).
@Suite struct DiagnosticsBundleTests {
  static let now = Date(timeIntervalSince1970: 1_795_003_205)
  static let plantedKey = "sk-FIXTURE-" + String(repeating: "Dg9", count: 6)

  struct Fixture {
    let harness: StoreHarness
    let repository: GRDBRepository
    let logs: URL

    init() async throws {
      harness = try StoreHarness()
      repository = GRDBRepository(database: try await harness.open().database)
      try await repository.database.write("seed") { db in
        try FixtureDBBuilder.representativeRows(db)
        // A body stored before the redactor saw it, as if a key slipped through: the bundle must still hide it.
        try db.execute(sql: "UPDATE poll_state SET last_raw = ? WHERE job = 'usage'",
                       arguments: [Data("{\"auth\":\"\(DiagnosticsBundleTests.plantedKey)\"}".utf8)])
      }
      logs = harness.temp.url.appendingPathComponent("Logs", isDirectory: true)
      try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
      for name in ["tokenbe-2026-11-17.ndjson", "tokenbe-2026-11-18.ndjson", "tokenbe-2026-11-18-1.ndjson",
                   "tokenbe-2026-11-18-2.ndjson", "tokenbe-2026-11-18-10.ndjson", "crash-2026-11-18.ndjson",
                   "tokenbe.sqlite", "test-keychain.json"] {
        try Data("{\"file\":\"\(name)\"}\n".utf8).write(to: logs.appendingPathComponent(name))
      }
    }

    func inputs() -> DiagnosticsInputs {
      DiagnosticsInputs(logsDirectory: logs, breadcrumbs: [], settings: ["tb.log.level": "info", "tb.ui.hideCents": true],
                        appVersion: "1.2.3")
    }

    /// Exports, then unzips with `ditto -x -k` into a fresh folder; returns the result and that folder.
    func export(flushed: Flag? = nil) async throws -> (DiagnosticsResult, URL) {
      let zip = harness.temp.url.appendingPathComponent(DiagnosticsBundle.fileName(DiagnosticsBundleTests.now))
      let result = try await DiagnosticsBundle.export(
        store: repository, inputs: inputs(), to: zip, now: DiagnosticsBundleTests.now,
        flush: { flushed?.value.withLock { $0 = true } }, log: EventLog(pipeline: harness.pipeline))
      let out = harness.temp.url.appendingPathComponent("unzipped", isDirectory: true)
      try await DiagnosticsBundle.run(DiagnosticsBundle.ditto, ["-x", "-k", zip.path, out.path])
      return (result, out)
    }
  }

  /// Whether the flush ran.
  final class Flag: Sendable {
    let value = Mutex(false)
  }

  static let expected = ["breadcrumbs.ndjson", "db-stats.json", "environment.json", "poll_state.json",
                         "price-overrides.json", "schema.sql", "settings.json", "tokenbe-2026-11-18-1.ndjson",
                         "tokenbe-2026-11-18-10.ndjson", "tokenbe-2026-11-18-2.ndjson"]

  @Test("exactly 07's files and the newest 3 logs by (day, rotation): no database, no keychain, no strays")
  func contents() async throws {
    let fixture = try await Fixture()
    let (result, out) = try await fixture.export()
    let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
    #expect(names == Self.expected)
    #expect(result.files == Self.expected)
    #expect(!names.contains { $0.contains("sqlite") || $0.contains("keychain") || $0.hasPrefix("__MACOSX") })
    let schema = try String(contentsOf: out.appendingPathComponent("schema.sql"), encoding: .utf8)
    #expect(schema.contains("CREATE TABLE usage_bucket") && schema.contains("CREATE INDEX harness_event_ts"))
    let stats = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("db-stats.json")))
      as? [String: Any]
    #expect((stats?["tables"] as? [String: Int])?["account"] == 1 && (stats?["page_count"] as? Int ?? 0) > 0)
    let settings = try String(contentsOf: out.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(settings.contains("\"tb.log.level\" : \"info\""))
    let environment = try JSONSerialization.jsonObject(
      with: Data(contentsOf: out.appendingPathComponent("environment.json"))) as? [String: Any]
    #expect(Set(environment?.keys.map { $0 } ?? []) == ["macos", "app_version", "low_power", "locale", "timezone",
                                                       "exported_at"])
    #expect(environment?["app_version"] as? String == "1.2.3")
    let overrides = try String(contentsOf: out.appendingPathComponent("price-overrides.json"), encoding: .utf8)
    #expect(overrides.contains("\"model\" : \"gpt-5\""))
  }

  @Test("SEC-1: last_raw is redacted and no file holds a key pattern; the zip never holds a database")
  func noSecrets() async throws {
    let fixture = try await Fixture()
    let (_, out) = try await fixture.export()
    let pollState = try String(contentsOf: out.appendingPathComponent("poll_state.json"), encoding: .utf8)
    #expect(pollState.contains(Redactor.keyMarker), "the planted key is replaced by the marker")
    for name in try FileManager.default.contentsOfDirectory(atPath: out.path) {
      let text = try String(contentsOf: out.appendingPathComponent(name), encoding: .utf8)
      #expect(!text.contains("sk-FIXTURE") && !text.contains("FIXTURE"), "\(name) holds no key")
      #expect(text.firstMatch(of: /sk-[A-Za-z0-9_\-]{8,}/) == nil, "\(name): no OpenAI-style key")
      #expect(!text.hasPrefix("SQLite format"), "\(name) is not a database")
    }
  }

  @Test("the pipeline is drained first; app.diagnostics_exported {path, bytes, files}; an existing zip is replaced")
  func logsAndReplace() async throws {
    let fixture = try await Fixture()
    let flushed = Flag()
    let (first, _) = try await fixture.export(flushed: flushed)
    #expect(flushed.value.withLock { $0 }, "the newest log holds the records up to the click")
    #expect(first.bytes > 0 && first.url.lastPathComponent == "TokenBe-diagnostics-20261118-120005.zip")
    let records = await fixture.harness.records(.appDiagnosticsExported)
    #expect(records.count == 1 && records.first?.lvl == .info && records.first?.cat == .app)
    #expect(records.first?.ctx["path"] == .string(first.url.path) && records.first?.ctx["bytes"] == .int(first.bytes))
    #expect(records.first?.ctx["files"] == .int(Self.expected.count))
    let zip = first.url
    try FileManager.default.removeItem(at: fixture.harness.temp.url.appendingPathComponent("unzipped"))
    let again = try await DiagnosticsBundle.export(store: fixture.repository, inputs: fixture.inputs(), to: zip,
                                                   now: Self.now, flush: {})
    #expect(again.files == Self.expected, "a second export over the same name replaces the zip")
  }

  @Test("07's file name is UTC: TokenBe-diagnostics-YYYYMMDD-HHMMSS.zip")
  func fileName() {
    #expect(DiagnosticsBundle.fileName(Self.now) == "TokenBe-diagnostics-20261118-120005.zip")
  }

  @Test("a tool that exits non-zero throws its status and stderr")
  func dittoFailure() async throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("tokenbe-missing-\(UUID().uuidString)")
    await #expect(throws: DittoFailed.self) {
      try await DiagnosticsBundle.run(DiagnosticsBundle.ditto, ["-c", "-k", "--sequesterRsrc", missing.path,
                                                               missing.path + ".zip"])
    }
  }

  @Test("a tool that cannot start throws; a failed export leaves no staging folder and no zip")
  func failures() async throws {
    let missingTool = URL(fileURLWithPath: "/usr/bin/tokenbe-no-such-tool")
    await #expect(throws: (any Error).self) { try await DiagnosticsBundle.run(missingTool, []) }
    let fixture = try await Fixture()
    let nowhere = fixture.harness.temp.url.appendingPathComponent("no-folder/TokenBe-diagnostics.zip")
    let scratch = fixture.harness.temp.url.appendingPathComponent("scratch", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    await #expect(throws: (any Error).self) {
      try await DiagnosticsBundle.export(store: fixture.repository, inputs: fixture.inputs(), to: nowhere, flush: {},
                                         scratch: scratch)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path) == [],
            "the staging folder is removed after a failure")
    #expect(!FileManager.default.fileExists(atPath: nowhere.path))
    #expect(await fixture.harness.records(.appDiagnosticsExported).isEmpty)
  }

  @Test("values: last_raw that is not text is Base64, NULL columns are null, settings keep their JSON types")
  func values() throws {
    let row = PollStateRecord(accountId: "a", job: "usage", lastAttemptAt: nil, lastSuccessAt: nil, lastErrorClass: nil,
                              lastErrorMessage: nil, consecutiveFailures: 2, circuitOpenUntil: nil, cursor: nil,
                              lastRaw: Data([0xFF, 0xFE]))
    let object = DiagnosticsBundle.pollState(row)
    #expect(object["last_raw"] as? String == "//4=" && object["cursor"] is NSNull)
    #expect(object["consecutive_failures"] as? Int64 == 2)
    #expect(DiagnosticsBundle.any(.double(1.5)) as? Double == 1.5 && DiagnosticsBundle.any(.null) is NSNull)
    #expect(DiagnosticsBundle.any(.int(3)) as? Int == 3 && DiagnosticsBundle.any(.bool(true)) as? Bool == true)
  }
}
