import Foundation
import GRDB

/// One numbered SQL file of `Store/Migrations` (03 § Migrations).
public struct Migration: Sendable, Equatable {
  public let version: Int
  /// The file name, e.g. `001_initial.sql`; named in the fatal alert.
  public let name: String
  public let sql: String

  public init(version: Int, name: String, sql: String) {
    self.version = version
    self.name = name
    self.sql = sql
  }

  /// `NNN_slug.sql`; anything else in the folder (the README) is not a migration.
  static var fileName: Regex<(Substring, Substring)> { /^(\d{3})_[a-z0-9_]+\.sql$/ }

  /// The migrations bundled with TokenBeCore, in version order.
  public static func bundled() throws -> [Migration] {
    guard let folder = Bundle.module.url(forResource: "Migrations", withExtension: nil) else {
      throw StoreError.notFound("Migrations resource folder")
    }
    return try load(from: folder)
  }

  static func load(from folder: URL) throws -> [Migration] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .compactMap { name -> Migration? in
        guard let match = name.wholeMatch(of: fileName), let version = Int(match.1) else { return nil }
        let sql = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        return Migration(version: version, name: name, sql: sql)
      }
      .sorted { $0.version < $1.version }
  }
}

/// Forward-only migrations: each file newer than `MAX(schema_version.version)` runs in its own transaction and
/// appends its `schema_version` row (001 seeds its own). A failure rolls that file back, logs
/// `db.migrate_failed` at fault and stops; nothing is deleted (03).
struct Migrator {
  struct Failure: Error, Sendable {
    let migration: Migration
    let underlying: any Error
  }

  let migrations: [Migration]
  let log: StoreLog

  /// 0 for an empty database.
  static func currentVersion(_ db: GRDB.Database) throws -> Int {
    guard try db.tableExists("schema_version") else { return 0 }
    return try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_version") ?? 0
  }

  /// Returns the schema version after migrating.
  @discardableResult
  func migrate(_ database: AppDatabase) async throws -> Int {
    var current = try await database.read { try Self.currentVersion($0) }
    for migration in migrations where migration.version > current {
      let start = ContinuousClock.now
      let from = current
      do {
        try await database.pool.writeWithoutTransaction { db in
          try db.inTransaction {
            try db.execute(sql: migration.sql)
            let recorded = try Int.fetchOne(
              db, sql: "SELECT COUNT(*) FROM schema_version WHERE version = ?", arguments: [migration.version]
            ) ?? 0
            if recorded == 0 {
              try db.execute(
                sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
                arguments: [migration.version, DBTime.string(Date())]
              )
            }
            return .commit
          }
        }
      } catch {
        log.emit(.fault, .dbMigrateFailed, msg: "migration failed", err: error, ctx: [
          "from": .int(from), "to": .int(migration.version), "migration": .string(migration.name)
        ])
        throw Failure(migration: migration, underlying: error)
      }
      current = migration.version
      log.emit(.info, .dbMigrate, msg: "migrated", dur: ContinuousClock.now - start, ctx: [
        "from": .int(from), "to": .int(current)
      ])
    }
    return current
  }
}
