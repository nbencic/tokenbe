import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// 14 § Stage 10.0.3 Tests (Q-062): migration 002 rebuilds `account` with the wider provider list. The committed
/// `schema_v1.sqlite` (one row in every table) is the version-1 database it runs on (03: every migration ships with a
/// fixture produced by the previous version).
@Suite struct Migration002Tests {
  static let providers = ["openai", "anthropic", "openrouter", "deepseek", "xai", "moonshot", "novita", "stepfun",
                          "siliconflow", "deepinfra"]

  /// The v1 fixture, opened (and so migrated to v2).
  static func migratedFixture() async throws -> (StoreHarness, AppDatabase) {
    let harness = try StoreHarness()
    try harness.makeDirectory()
    try FixtureDBBuilder.install("schema_v1.sqlite", into: harness.directory)
    return (harness, try await harness.open().database)
  }

  @Test("no referencing row is lost: every table keeps its count, foreign_key_check is empty, foreign keys are on")
  func keepsRows() async throws {
    let (harness, database) = try await Self.migratedFixture()
    defer { withExtendedLifetime(harness) {} }
    for table in MigrationTests.tables where table != "schema_version" {
      let expected = switch table {
      case "app": 2
      case "poll_state": 4
      default: 1
      }
      #expect(try await MigrationTests.count(database, table) == expected, "\(table)")
    }
    let violations = try await database.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count }
    #expect(violations == 0)
    #expect(try await database.pool.write { db in try Int.fetchOne(db, sql: "PRAGMA foreign_keys") } == 1)
    #expect(try await database.read { db in try AccountRecord.fetchOne(db) } == FixtureDBBuilder.account())
  }

  @Test("the rebuilt account keeps 001's columns, types, defaults and keys; only the provider list grows")
  func sameShape() async throws {
    let (harness, database) = try await Self.migratedFixture()
    defer { withExtendedLifetime(harness) {} }
    let columns = try await database.read { db in
      try Row.fetchAll(db, sql: "SELECT name, type, \"notnull\", dflt_value, pk FROM pragma_table_info('account')")
        .map { "\($0["name"] as String) \($0["type"] as String) \($0["notnull"] as Int) \($0["dflt_value"] as String? ?? "-") \($0["pk"] as Int)" }
    }
    #expect(columns == [
      "id TEXT 0 - 1", "provider TEXT 1 - 0", "label TEXT 1 - 0", "keychain_ref TEXT 1 - 0", "balance_mode TEXT 1 - 0",
      "currency TEXT 1 'USD' 0", "capabilities TEXT 1 - 0", "org_id TEXT 0 - 0", "org_name TEXT 0 - 0",
      "auto_reload_enabled INTEGER 1 0 0", "auto_reload_to_cents INTEGER 0 - 0", "auto_reload_below_cents INTEGER 0 - 0",
      "paused INTEGER 1 0 0", "interval_override_json TEXT 0 - 0", "created_at TEXT 1 - 0"
    ])
    let tables = try await database.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    }
    #expect(tables == MigrationTests.tables, "no account_new left behind")
    // Every child table still names `account` (the rename kept the references).
    let references = try await database.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE sql LIKE '%REFERENCES account(id)%'")
    }
    #expect(references == 9)
  }

  @Test("each of the ten providers can be stored, an unknown one cannot, and UNIQUE (provider) still holds")
  func providerCheck() async throws {
    let (harness, database) = try await Self.migratedFixture()
    defer { withExtendedLifetime(harness) {} }
    for (index, provider) in Self.providers.enumerated() where provider != "openai" {
      try await database.pool.write { db in
        try FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-0000000002\(String(format: "%02d", index))",
                                     provider: provider, label: provider).insert(db)
      }
    }
    #expect(try await MigrationTests.count(database, "account") == 10)
    await #expect(throws: DatabaseError.self) {
      try await database.pool.write { db in
        try FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-000000000299", provider: "gemini").insert(db)
      }
    }
    await #expect(throws: DatabaseError.self) {
      try await database.pool.write { db in
        try FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-000000000298", provider: "moonshot").insert(db)
      }
    }
  }

  @Test("a migration that would leave a dangling reference rolls back (foreign_key_check); foreign keys stay on")
  func danglingReference() async throws {
    let harness = try StoreHarness()
    try await harness.open().database.close()
    let dangling = Migration(version: 3, name: "003_dangling.sql", sql: """
      INSERT INTO poll_state (account_id, job) VALUES ('0190f0a0-0000-7000-8000-00000000dead', 'usage');
      """)
    let error = await #expect(throws: DatabaseOpenError.self) {
      try await harness.open(migrations: try Migration.bundled() + [dangling])
    }
    #expect(error?.migration == "003_dangling.sql")
    #expect(error.map { LogError($0).desc.contains("foreign_key_check: 1 row") } == true)
    let database = try await harness.open().database
    #expect(try await MigrationTests.count(database, "poll_state") == 0)
    #expect(try await database.read { db in try Migrator.currentVersion(db) } == 2)
    #expect(try await database.pool.write { db in try Int.fetchOne(db, sql: "PRAGMA foreign_keys") } == 1)
  }

  @Test("an export from schema 1 imports into schema 2; a newer document is refused (Q-063)")
  func importsOlderExport() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let repository = GRDBRepository(database: database)
    let older = ExportDocument(schemaVersion: 1, exportedAt: "2026-11-18T00:00:00.000Z",
                               accounts: [FixtureDBBuilder.account()])
    #expect(try await repository.importDocument(older) >= 1)
    #expect(try await MigrationTests.count(database, "account") == 1)
    let newer = ExportDocument(schemaVersion: 3, exportedAt: "2026-11-18T00:00:00.000Z")
    await #expect(throws: ImportRefusal.schemaVersion(found: 3, expected: 2)) {
      try await repository.importDocument(newer)
    }
  }
}
