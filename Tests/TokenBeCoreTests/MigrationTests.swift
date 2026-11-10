import Foundation
import GRDB
import Synchronization
import Testing
@testable import TokenBeCore

/// A temp support folder, a capturing log, and `DatabaseOpener` pointed at both.
struct StoreHarness {
  let temp: TempDirectory
  let sink = CapturingLogSink()
  let pipeline: LogPipeline

  init() throws {
    temp = try TempDirectory()
    pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
  }

  var directory: URL { temp.url.appendingPathComponent("TokenBe", isDirectory: true) }
  var databaseURL: URL { directory.appendingPathComponent(AppDatabase.fileName) }

  func open(migrations: [Migration]? = nil, now: @escaping @Sendable () -> Date = { Date() }) async throws
    -> OpenedDatabase {
    try await DatabaseOpener.open(directory: directory, migrations: migrations, logPipeline: pipeline, now: now)
  }

  func records(_ evt: Evt) async -> [LogRecord] {
    await pipeline.drain()
    return await sink.records.filter { $0.evt == evt }
  }

  func files() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
  }

  func makeDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
}

/// 03 § Schema, § Migrations, § Durability; 11 `MigrationTests`.
@Suite struct MigrationTests {
  static let tables = [
    "account", "app", "app_binding", "balance_snapshot", "band_state", "cost_bucket", "harness_event", "ingest_file",
    "ledger_event", "poll_state", "price_override", "price_snapshot", "provider_key", "schema_version", "usage_bucket"
  ]

  static func count(_ database: AppDatabase, _ table: String) async throws -> Int {
    try await database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1 }
  }

  @Test("a fresh launch creates v1 with 03's PRAGMAs on the writer and on readers")
  func freshPragmas() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let expected: [String: String] = [
      "journal_mode": "wal", "synchronous": "1", "foreign_keys": "1", "auto_vacuum": "2", "cache_size": "-2000",
      "mmap_size": "0", "temp_store": "2", "busy_timeout": "5000"
    ]
    let readPragmas: @Sendable (GRDB.Database) throws -> [String: String] = { db in
      var values: [String: String] = [:]
      for name in expected.keys {
        values[name] = try String.fetchOne(db, sql: "PRAGMA \(name)")
      }
      return values
    }
    let writer = try await database.pool.write(readPragmas)
    let reader = try await database.read(readPragmas)
    #expect(writer == expected)
    #expect(reader == expected)
  }

  @Test("v1 has exactly the 15 tables of 03 and its indexes; the seed rows are present")
  func schemaAndSeeds() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let (tables, indexes) = try await database.read { db in
      (
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"),
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name")
      )
    }
    #expect(tables == Self.tables)
    #expect(indexes == ["harness_event_ts", "ledger_event_ts", "usage_bucket_time"])
    let versions = try await database.read { db in
      try Row.fetchAll(db, sql: "SELECT version, applied_at FROM schema_version").map { row -> (Int, String) in
        (row["version"], row["applied_at"])
      }
    }
    #expect(versions.count == 1, "001 seeds its own row; the migrator adds none")
    #expect(versions.first?.0 == 1)
    let appliedAt = try #require(versions.first?.1)
    #expect(DBTime.date(appliedAt) != nil, "RFC3339 with milliseconds: \(appliedAt)")
    let sentinel = try await database.read { db in try AppRecord.fetchOne(db, key: "app_unassigned") }
    #expect(sentinel?.name == "unassigned")
    #expect(sentinel?.displayName == "Unassigned")
    #expect(sentinel?.isAuto == true)
  }

  @Test("launch logs db.open, db.quick_check ok and db.migrate from 0 to 1; a relaunch migrates nothing")
  func launchEvents() async throws {
    let harness = try StoreHarness()
    let first = try await harness.open()
    #expect(first.recovery == nil)
    let open = try #require(await harness.records(.dbOpen).first)
    #expect(open.ctx["path"] == .string(harness.databaseURL.path))
    #expect(open.ctx["journal_mode"] == .string("wal"))
    #expect(open.ctx["page_size"] == .int(4096))
    #expect(open.ctx["size_bytes"] != nil)
    let migrate = await harness.records(.dbMigrate)
    #expect(migrate.count == 1)
    #expect(migrate.first?.ctx["from"] == .int(0))
    #expect(migrate.first?.ctx["to"] == .int(1))
    #expect(migrate.first?.durMs != nil)
    #expect(await harness.records(.dbQuickCheck).first?.ctx["result"] == .string("ok"))
    try first.database.close()

    _ = try await harness.open()
    #expect(await harness.records(.dbOpen).count == 2)
    #expect(await harness.records(.dbMigrate).count == 1, "already at v1")
  }

  @Test("the support folder is private (0700), even when it already existed")
  func privateFolder() async throws {
    let harness = try StoreHarness()
    try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o755])
    _ = try await harness.open()
    let mode = try FileManager.default.attributesOfItem(atPath: harness.directory.path)[.posixPermissions] as? Int
    #expect(mode == 0o700)
  }

  @Test("the committed schema_v1.sqlite opens, is already current, and keeps every row")
  func fixtureOpens() async throws {
    let harness = try StoreHarness()
    try harness.makeDirectory()
    try FixtureDBBuilder.install("schema_v1.sqlite", into: harness.directory)
    let database = try await harness.open().database
    #expect(await harness.records(.dbMigrate).isEmpty)
    for table in Self.tables {
      let expected = switch table {
      case "app": 2
      case "poll_state": 4
      default: 1
      }
      #expect(try await Self.count(database, table) == expected, "\(table)")
    }
    #expect(try await database.quickCheck().isOK)
  }

  @Test("a corrupt file is moved aside with its sidecars, db.corrupt is logged, and a fresh v1 is created")
  func corruptWithoutBackup() async throws {
    let harness = try StoreHarness()
    try harness.makeDirectory()
    try FixtureDBBuilder.install("corrupt.sqlite", into: harness.directory)
    try Data("stale wal".utf8).write(to: URL(fileURLWithPath: harness.databaseURL.path + "-wal"))
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let opened = try await harness.open(now: { date })
    let moved = harness.directory.appendingPathComponent("tokenbe.sqlite.corrupt-\(DBTime.fileStamp(date))")
    #expect(opened.recovery == DatabaseRecovery(corruptCopy: moved, restoredFrom: nil))
    #expect(FileManager.default.fileExists(atPath: moved.path))
    #expect(FileManager.default.fileExists(atPath: moved.path + "-wal"), "the stale WAL went with it")
    let corrupt = try #require(await harness.records(.dbCorrupt).first)
    #expect(corrupt.lvl == .fault)
    #expect(corrupt.ctx["moved_to"] == .string(moved.path))
    #expect(corrupt.ctx["path"] == .string(harness.databaseURL.path))
    #expect(await harness.records(.dbRestore).isEmpty)
    #expect(try await Self.count(opened.database, "account") == 0)
    #expect(try await Self.count(opened.database, "schema_version") == 1)
    #expect(await harness.records(.dbMigrate).first?.ctx["from"] == .int(0))
  }

  @Test("a corrupt file with a backup present is replaced by the backup (db.restore)")
  func corruptRestoresBackup() async throws {
    let harness = try StoreHarness()
    try harness.makeDirectory()
    try FixtureDBBuilder.install("corrupt.sqlite", into: harness.directory)
    try FixtureDBBuilder.install("schema_v1.sqlite", into: harness.directory, as: "tokenbe.sqlite.bak")
    let opened = try await harness.open()
    let backup = harness.directory.appendingPathComponent("tokenbe.sqlite.bak")
    #expect(opened.recovery?.restoredFrom == backup)
    #expect(FileManager.default.fileExists(atPath: backup.path), "the backup itself is kept")
    let restore = try #require(await harness.records(.dbRestore).first)
    #expect(restore.lvl == .warn)
    #expect(restore.ctx["from_backup"] == .string(backup.path))
    #expect(try await Self.count(opened.database, "account") == 1)
    #expect(try await opened.database.read { db in try AccountRecord.fetchOne(db) } == FixtureDBBuilder.account())
  }

  @Test("a failing migration rolls back, logs db.migrate_failed at fault, names itself, and moves nothing")
  func failedMigration() async throws {
    let harness = try StoreHarness()
    try await harness.open().database.close()
    let broken = Migration(version: 2, name: "002_broken.sql", sql: "CREATE TABLE extra (x INTEGER); NOT SQL;")
    let error = await #expect(throws: DatabaseOpenError.self) {
      try await harness.open(migrations: try Migration.bundled() + [broken])
    }
    #expect(error?.migration == "002_broken.sql")
    #expect(error?.databasePath == harness.databaseURL.path)
    #expect(error?.backupPath == harness.databaseURL.path + ".bak")
    #expect(error?.description.contains("002_broken.sql") == true)
    #expect(error.map { LogError($0).desc.contains("002_broken.sql") } == true, "the log names the migration")
    let failed = try #require(await harness.records(.dbMigrateFailed).first)
    #expect(failed.lvl == .fault)
    #expect(failed.ctx["from"] == .int(1))
    #expect(failed.ctx["to"] == .int(2))
    #expect(failed.err != nil)
    #expect(try harness.files().allSatisfy { !$0.contains("corrupt") })
    let database = try await harness.open().database
    #expect(try await database.read { db in try db.tableExists("extra") } == false)
    #expect(try await database.read { db in try Migrator.currentVersion(db) } == 1)
  }

  @Test("a later migration runs once, in order, and appends its schema_version row")
  func laterMigration() async throws {
    let harness = try StoreHarness()
    let added = Migration(version: 2, name: "002_note.sql", sql: "ALTER TABLE app ADD COLUMN note TEXT;")
    let database = try await harness.open(migrations: try Migration.bundled() + [added]).database
    let versions = try await database.read { db in try Int.fetchAll(db, sql: "SELECT version FROM schema_version") }
    #expect(versions == [1, 2])
    let steps = await harness.records(.dbMigrate).map { [$0.ctx["from"], $0.ctx["to"]] }
    #expect(steps == [[.int(0), .int(1)], [.int(1), .int(2)]])
  }

  @Test("only NNN_slug.sql files are migrations; the bundled set is 001_initial.sql")
  func bundledMigrations() throws {
    let bundled = try Migration.bundled()
    #expect(bundled.map(\.name) == ["001_initial.sql"])
    #expect(bundled.first?.version == TokenBeCoreInfo.schemaVersion)
    let temp = try TempDirectory()
    for name in ["002_b.sql", "001_a.sql", "README.md", "3_bad.sql", "004_Upper.sql"] {
      try Data("SELECT 1;".utf8).write(to: temp.url.appendingPathComponent(name))
    }
    #expect(try Migration.load(from: temp.url).map(\.version) == [1, 2])
  }

  @Test("a folder that cannot be created is a DatabaseOpenError, not a corruption")
  func unopenable() async throws {
    let harness = try StoreHarness()
    try Data().write(to: harness.directory)
    let error = await #expect(throws: DatabaseOpenError.self) { try await harness.open() }
    #expect(error?.migration == nil)
    #expect(await harness.records(.dbCorrupt).isEmpty)
  }
}

/// 03 § Durability: backup, integrity, vacuum; `db.busy`.
@Suite struct DurabilityTests {
  @Test("backup writes tokenbe.sqlite.bak atomically with every row and logs db.backup")
  func backup() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let repository = GRDBRepository(database: database)
    try await repository.insertAccount(FixtureDBBuilder.account())
    let first = try await repository.backup()
    #expect(first.url == database.backupURL)
    #expect(first.bytes > 0)
    try await repository.insertAccount(FixtureDBBuilder.account(id: "second", provider: "xai", label: "xAI"))
    _ = try await repository.backup()
    #expect(try harness.files().allSatisfy { !$0.contains(".tmp-") })
    let copy = try DatabaseQueue(path: database.backupURL.path)
    #expect(try await copy.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account") } == 2)
    try copy.close()
    let logged = await harness.records(.dbBackup)
    #expect(logged.count == 2)
    #expect(logged.first?.ctx["bytes"] == .int(first.bytes))
    #expect(logged.first?.durMs != nil)
  }

  @Test("a backup that cannot be renamed into place logs db.backup_failed and leaves no temp file")
  func backupFailure() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    try FileManager.default.createDirectory(at: database.backupURL.appendingPathComponent("occupied"),
                                            withIntermediateDirectories: true)
    await #expect(throws: (any Error).self) { try await database.backup() }
    let failed = try #require(await harness.records(.dbBackupFailed).first)
    #expect(failed.lvl == .error)
    #expect(failed.err != nil)
    #expect(try harness.files().allSatisfy { !$0.contains(".tmp-") })
  }

  @Test("integrity_check and quick_check report ok and log their events")
  func checks() async throws {
    let harness = try StoreHarness()
    let repository = GRDBRepository(database: try await harness.open().database)
    let full = try await repository.integrityCheck()
    #expect(full == IntegrityResult(result: "ok", corruptCopy: nil))
    #expect(try await repository.quickCheck().isOK)
    let logged = try #require(await harness.records(.dbIntegrityCheck).first)
    #expect(logged.ctx["result"] == .string("ok"))
    #expect(logged.durMs != nil)
    #expect(await harness.records(.dbQuickCheck).count == 2, "launch and on demand")
  }

  @Test("incremental vacuum returns freed pages and logs db.vacuum")
  func vacuum() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let repository = GRDBRepository(database: database)
    try await repository.insertAccount(FixtureDBBuilder.account())
    let note = String(repeating: "x", count: 2_000)
    try await database.write("fill") { db in
      for index in 0..<500 {
        try db.execute(
          sql: "INSERT INTO ledger_event (id, account_id, ts, kind, note, source) VALUES (?, ?, ?, 'note', ?, 'user')",
          arguments: ["l\(index)", FixtureDBBuilder.accountID, FixtureDBBuilder.stamp, note]
        )
      }
    }
    try await database.write("empty") { db in try db.execute(sql: "DELETE FROM ledger_event") }
    let freed = try await repository.incrementalVacuum()
    #expect(freed > 0)
    #expect(await harness.records(.dbVacuum).first?.ctx["pages_freed"] == .int(freed))
  }

  @Test("a write that waits more than 100 ms for the writer logs db.busy with op and waited_ms")
  func busy() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let started = Atomic<Bool>(false)
    let holder = Task {
      try await database.write("hold") { _ in
        started.store(true, ordering: .sequentiallyConsistent)
        Thread.sleep(forTimeInterval: 0.3)
      }
    }
    await eventually("writer held") { started.load(ordering: .sequentiallyConsistent) }
    try await database.write("waiting") { _ in }
    try await holder.value
    let busy = try #require(await harness.records(.dbBusy).first)
    #expect(busy.lvl == .warn)
    #expect(busy.ctx["op"] == .string("waiting"))
    if case .int(let waited)? = busy.ctx["waited_ms"] {
      #expect(waited >= 100)
    } else {
      Issue.record("waited_ms missing")
    }
    #expect(await harness.records(.dbBusy).count == 1, "the holder itself did not wait")
  }

  @Test("timestamps are RFC3339 UTC with milliseconds and round-trip")
  func timestamps() throws {
    let date = Date(timeIntervalSince1970: 1_768_469_400.1234)
    #expect(DBTime.string(date) == "2026-01-15T09:30:00.123Z")
    let parsed = try #require(DBTime.date("2026-01-15T09:30:00.123Z"))
    #expect(abs(parsed.timeIntervalSince1970 - 1_768_469_400.123) < 0.000_5)
    #expect(DBTime.string(parsed) == "2026-01-15T09:30:00.123Z")
    #expect(DBTime.date("2026-01-15 09:30:00") == nil)
    #expect(DBTime.fileStamp(date) == "20260115T093000Z")
    #expect(DBTime.string(Date(timeIntervalSince1970: 1_768_469_400.9996)) == "2026-01-15T09:30:01.000Z")
    #expect(DBTime.string(Date(timeIntervalSince1970: -0.5)) == "1969-12-31T23:59:59.500Z")
  }
}

/// `Tests/Fixtures/db` is what `FixtureDBBuilder` produces (03: every migration ships with a fixture DB).
@Suite struct FixtureDBTests {
  @Test("a freshly built fixture has the same rows as the committed schema_v1.sqlite; corrupt.sqlite is its first 4 KiB")
  func committedFixtureIsCurrent() async throws {
    let temp = try TempDirectory()
    let built = try await FixtureDBBuilder.build(in: temp.url)
    let dump: @Sendable (URL) async throws -> [String: [[DatabaseValue]]] = { url in
      var config = Configuration()
      config.readonly = true
      let queue = try DatabaseQueue(path: url.path, configuration: config)
      let rows = try await queue.read { db in
        var rows: [String: [[DatabaseValue]]] = [:]
        for table in MigrationTests.tables where table != "schema_version" {
          rows[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid").map { Array($0.databaseValues) }
        }
        return rows
      }
      try queue.close()
      return rows
    }
    let committed = try FixtureDBBuilder.bundled("schema_v1.sqlite")
    #expect(try await dump(built) == dump(committed))
    let corrupt = try Data(contentsOf: FixtureDBBuilder.bundled("corrupt.sqlite"))
    #expect(corrupt == (try Data(contentsOf: committed)).prefix(4096))
  }

  @Test("regenerates Tests/Fixtures/db when TOKENBE_WRITE_FIXTURES=1",
        .enabled(if: ProcessInfo.processInfo.environment["TOKENBE_WRITE_FIXTURES"] == "1"))
  func regenerate() async throws {
    let temp = try TempDirectory()
    let built = try await FixtureDBBuilder.build(in: temp.url)
    let target = FixtureDBBuilder.sourceDirectory()
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let schema = target.appendingPathComponent("schema_v1.sqlite")
    let data = try Data(contentsOf: built)
    try data.write(to: schema)
    try data.prefix(4096).write(to: target.appendingPathComponent("corrupt.sqlite"))
  }
}
