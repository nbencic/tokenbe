import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 11 `ExportImportTests` (14 § Stage 9.2; 03 § Durability, O-5, O-17): export → fresh database → import gives the
/// same rows in every exported table (per `usage_bucket` width too, PM-9.1-2) and the same Remaining; no key in the
/// output; an import only into an empty database, all or nothing; the CSV of all tables (Q-056).
@Suite struct ExportImportTests {
  static let now = Date(timeIntervalSince1970: 1_795_003_200)
  static let acct = FixtureDBBuilder.accountID

  struct Store {
    let harness: StoreHarness
    let repository: GRDBRepository

    init(seeded: Bool) async throws {
      harness = try StoreHarness()
      repository = GRDBRepository(database: try await harness.open().database)
      guard seeded else { return }
      try await repository.database.write("seed") { db in
        try FixtureDBBuilder.representativeRows(db)
        // A 9.1 monthly roll-up beside its daily row, and a key whose provider value carries its prefix.
        for width in ["1d", "1mo"] {
          try UsageBucketRecord(
            accountId: ExportImportTests.acct, bucketStart: "2025-01-01T00:00:00.000Z", bucketWidth: width,
            model: "gpt-5", providerKeyId: "", serviceTier: "", source: "rollup", inputUncached: 5, cacheWrite5m: 0,
            cacheWrite1h: 0, cacheRead: 0, output: 1, reasoning: 0, requests: 1, estCostCents: nil, unpriced: true,
            provisional: false, fetchedAt: FixtureDBBuilder.stamp).insert(db)
        }
        try ProviderKeyRecord(
          accountId: ExportImportTests.acct, providerKeyId: "key_fixture2", name: nil, redacted: "sk-FIXTURE-openai-a1b2",
          projectId: nil, workspaceId: nil, status: "active", firstSeenAt: FixtureDBBuilder.stamp,
          lastSeenAt: FixtureDBBuilder.stamp).insert(db)
      }
    }

    func count(_ sql: String) async throws -> Int {
      try await repository.database.read { db in try Int.fetchOne(db, sql: sql) ?? -1 }
    }

    /// Rows per exported table, and per `usage_bucket` width.
    func counts() async throws -> [String: Int] {
      var result: [String: Int] = [:]
      for table in ExportedTable.allCases { result[table.table] = try await count("SELECT COUNT(*) FROM \(table.table)") }
      for width in ["1h", "1d", "1mo"] {
        result["usage_bucket \(width)"] = try await count("SELECT COUNT(*) FROM usage_bucket WHERE bucket_width = '\(width)'")
      }
      return result
    }

    func inputs() async throws -> SummaryInputs {
      try await repository.database.read { try SummaryInputs.fetch($0) }
    }

    func remaining() async throws -> [String: Int64?] {
      let inputs = try await inputs()
      let summaries = AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: ExportImportTests.now))
      return Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.remainingCents) })
    }
  }

  static func exportFile(_ store: Store) async throws -> URL {
    let url = store.harness.temp.url.appendingPathComponent(JSONExporter.fileName(date: "2026-11-18"))
    try await JSONExporter.export(from: store.repository, to: url, now: now, log: EventLog(pipeline: store.harness.pipeline))
    return url
  }

  @Test("round trip: export, import into a fresh database → identical rows per table and width, identical Remaining")
  func roundTrip() async throws {
    let source = try await Store(seeded: true)
    let url = try await Self.exportFile(source)
    let target = try await Store(seeded: false)
    let rows = try await JSONImporter.run(url, into: target.repository, log: EventLog(pipeline: target.harness.pipeline))
    #expect(try await target.counts() == source.counts())
    #expect(try await target.counts()["usage_bucket 1mo"] == 1, "PM-9.1-2: the monthly row comes back as it was")
    let (sourceInputs, targetInputs) = (try await source.inputs(), try await target.inputs())
    #expect(targetInputs.usageDays == sourceInputs.usageDays, "\(targetInputs.usageDays) vs \(sourceInputs.usageDays)")
    #expect(targetInputs.costDays == sourceInputs.costDays, "\(targetInputs.costDays) vs \(sourceInputs.costDays)")
    #expect(targetInputs.anchorDayUsage == sourceInputs.anchorDayUsage)
    #expect(targetInputs.ledgerEvents == sourceInputs.ledgerEvents && targetInputs.balances == sourceInputs.balances)
    // Fresh poll_state: until the first poll the card reads `No data yet` (08), so Remaining waits for it.
    let pending = try await target.remaining()
    let original = try await source.remaining()
    #expect(pending.keys.sorted() == [Self.acct] && pending[Self.acct] == .some(nil),
            "no Remaining before the imported account's first poll: \(pending), source \(original)")
    try await target.repository.database.write("first poll") { db in
      try db.execute(sql: "UPDATE poll_state SET last_success_at = ? WHERE job = 'usage'", arguments: [FixtureDBBuilder.stamp])
    }
    let (before, after) = (try await source.remaining(), try await target.remaining())
    #expect(after == before && before[Self.acct] != nil, "Remaining \(after) vs \(before)")
    #expect(try await target.count("SELECT COUNT(*) FROM poll_state") == 4, "the account's four poll_state rows (03)")
    #expect(try await target.count("SELECT COUNT(*) FROM poll_state WHERE last_attempt_at IS NOT NULL") == 0)
    #expect(try await target.count("SELECT COUNT(*) FROM harness_event") == 0, "not in 03's document (Q-056)")
    let exported = try await source.repository.exportDocument(exportedAt: "x")
    var copy = try await target.repository.exportDocument(exportedAt: "x")
    #expect(copy.usageBuckets == exported.usageBuckets && copy.ledgerEvents == exported.ledgerEvents)
    // Each database seeds its own `Unassigned` app; the import skips the document's.
    var seeded = exported
    seeded.apps.removeAll { $0.id == Attribution.unassignedID }
    copy.apps.removeAll { $0.id == Attribution.unassignedID }
    #expect(copy == seeded, "every exported row, field by field (keys as their hint, Q-056)")
    #expect(rows == exported.rows)
    let imported = await target.harness.records(.dbImport)
    #expect(imported.count == 1 && imported.first?.ctx["rows"] == .int(rows) && imported.first?.ctx["path"] == .string(url.path))
  }

  @Test("the file: 03's key order, no key, the key hint only; db.export {kind: json, path, rows}")
  func document() async throws {
    let source = try await Store(seeded: true)
    let url = try await Self.exportFile(source)
    let text = try String(contentsOf: url, encoding: .utf8)
    let keys = text.split(separator: "\n").compactMap { line in line.split(separator: ":").first.map(String.init) }
      .filter { $0.hasPrefix("\"") }
    #expect(keys == ["\"schema_version\"", "\"exported_at\"", "\"accounts\"", "\"provider_keys\"", "\"apps\"",
                     "\"app_bindings\"", "\"usage_buckets\"", "\"cost_buckets\"", "\"balance_snapshots\"",
                     "\"ledger_events\"", "\"price_overrides\""])
    #expect(!text.contains("sk-") && !text.contains("FIXTURE"), "E2E-7 / SEC-1: no key, not even a prefix")
    #expect(text.contains("\"redacted\":\"\u{2026}a1b2\"") && text.contains("\"redacted\":\"\u{2026}abcd\""))
    #expect(!text.contains("poll_state") && !text.contains("last_raw") && !text.contains("ingest_file"))
    #expect(text.contains("\"exported_at\":\"2026-11-18T12:00:00.000Z\""))
    let records = await source.harness.records(.dbExport)
    #expect(records.count == 1 && records.first?.ctx["kind"] == "json" && records.first?.ctx["path"] == .string(url.path))
    #expect(records.first?.ctx["rows"] == .int(try JSONImporter.document(Data(contentsOf: url)).rows))
  }

  @Test("O-17: a database with an account, a price override or an app is refused; nothing is written")
  func refusesNonEmpty() async throws {
    let source = try await Store(seeded: true)
    let url = try await Self.exportFile(source)
    let before = try await source.counts()
    await #expect(throws: ImportRefusal.notEmpty) {
      try await JSONImporter.run(url, into: source.repository, log: EventLog(pipeline: source.harness.pipeline))
    }
    #expect(try await source.counts() == before)
    let failed = await source.harness.records(.dbImportFailed)
    #expect(failed.count == 1 && failed.first?.lvl == .error && failed.first?.err?.desc == "not_empty"
            && failed.first?.err?.type == "ImportRefusal.not_empty")
    let other = try await Store(seeded: false)
    try await other.repository.database.write("app") { db in
      try AppRecord(id: "app_x", name: "x", displayName: "x", createdAt: "", isAuto: true).insert(db)
    }
    await #expect(throws: ImportRefusal.notEmpty) { try await JSONImporter.run(url, into: other.repository) }
  }

  @Test("a document of another schema version is refused; a broken one rolls back whole")
  func versionAndAtomicity() async throws {
    let target = try await Store(seeded: false)
    let current = try await target.repository.exportDocument(exportedAt: "x")
    var future = ExportDocument(schemaVersion: current.schemaVersion + 1, exportedAt: "x")
    await #expect(throws: ImportRefusal.schemaVersion(found: current.schemaVersion + 1, expected: current.schemaVersion)) {
      try await target.repository.importDocument(future)
    }
    future.schemaVersion = current.schemaVersion
    future.accounts = [FixtureDBBuilder.account()]
    future.appBindings = [AppBindingRecord(appId: "app_missing", accountId: Self.acct, kind: "provider_key", value: "k")]
    await #expect(throws: (any Error).self) { try await target.repository.importDocument(future) }
    #expect(try await target.count("SELECT COUNT(*) FROM account") == 0, "the account insert rolled back with the binding")
    #expect(try await target.count("SELECT COUNT(*) FROM poll_state") == 0)
    let bad = target.harness.temp.url.appendingPathComponent("bad.json")
    try Data("{\"schema_version\":1}".utf8).write(to: bad)
    await #expect(throws: DecodingError.self) {
      try await JSONImporter.run(bad, into: target.repository, log: EventLog(pipeline: target.harness.pipeline))
    }
    #expect(await target.harness.records(.dbImportFailed).first?.ctx["path"] == .string(bad.path))
  }

  @Test("CSV of all tables: one RFC 4180 file per table, column-name header, raw values, NULL empty, CRLF, no key")
  func tablesCSV() async throws {
    let source = try await Store(seeded: true)
    let folder = source.harness.temp.url.appendingPathComponent(TablesCSVExporter.folderName(date: "2026-11-18"))
    let rows = try await TablesCSVExporter.export(from: source.repository, to: folder,
                                                  log: EventLog(pipeline: source.harness.pipeline))
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(files == ExportedTable.allCases.map { $0.table + ".csv" }.sorted())
    let counts = try await source.counts()
    #expect(rows == ExportedTable.allCases.reduce(0) { $0 + (counts[$1.table] ?? 0) })
    let keys = try String(contentsOf: folder.appendingPathComponent("provider_key.csv"), encoding: .utf8)
    #expect(keys.hasPrefix("account_id,provider_key_id,name,redacted,project_id,workspace_id,status,first_seen_at,last_seen_at\r\n"))
    #expect(!keys.contains("sk-") && keys.contains(",\u{2026}a1b2,"))
    #expect(keys.contains("key_fixture2,,\u{2026}a1b2,,,active,"), "NULL columns are empty fields")
    let usage = try String(contentsOf: folder.appendingPathComponent("usage_bucket.csv"), encoding: .utf8)
    #expect(usage.split(separator: "\r\n").count == 1 + (counts["usage_bucket"] ?? 0))
    #expect(usage.contains(",1mo,gpt-5,,,rollup,5,0,0,0,1,0,1,,1,0,"), "integers as digits, booleans 0/1, NULL est empty")
    let overrides = try String(contentsOf: folder.appendingPathComponent("price_override.csv"), encoding: .utf8)
    #expect(overrides.contains("gpt-5,\"{\"\"input\"\":1.25,\"\"output\"\":10}\","), "a JSON value is quoted, quotes doubled")
    let records = await source.harness.records(.dbExport)
    #expect(records.first?.ctx["kind"] == "csv_tables" && records.first?.ctx["rows"] == .int(rows))
  }
}
