import Foundation
import GRDB

/// The outcome of `PRAGMA quick_check` or `PRAGMA integrity_check`.
public struct IntegrityResult: Sendable, Equatable {
  /// `ok`, or the first line SQLite reported.
  public let result: String
  /// Where the corrupt file was copied, when the check failed on a running database.
  public let corruptCopy: URL?
  public var isOK: Bool { result == "ok" }
}

/// A finished online backup (03 § Durability).
public struct BackupResult: Sendable, Equatable {
  public let url: URL
  public let bytes: Int
}

/// The database is corrupt: SQLite said so while opening, or a check failed.
struct CorruptDatabase: Error, Sendable {
  /// `quick_check` when the launch check ran and failed; nil when opening itself failed.
  let check: String?
  let detail: String
}

extension AppDatabase {
  /// `PRAGMA quick_check` (launch), logged `db.quick_check {result, dur_ms}`.
  public func quickCheck() async throws -> IntegrityResult {
    try await check("quick_check", evt: .dbQuickCheck, copyOnFailure: true)
  }

  /// `PRAGMA integrity_check` (weekly, or Settings → Advanced), logged `db.integrity_check {result, dur_ms}`.
  public func integrityCheck() async throws -> IntegrityResult {
    try await check("integrity_check", evt: .dbIntegrityCheck, copyOnFailure: true)
  }

  /// Runs `pragma`. On failure, a running database is copied to `tokenbe.sqlite.corrupt-<ts>` and
  /// `db.integrity_failed` is logged; at launch `DatabaseOpener` moves the file aside instead.
  func check(_ pragma: String, evt: Evt, copyOnFailure: Bool, now: Date = Date()) async throws -> IntegrityResult {
    let start = ContinuousClock.now
    let lines = try await read { db in try String.fetchAll(db, sql: "PRAGMA \(pragma)") }
    let result = lines.first ?? "no result"
    log.emit(.info, evt, msg: pragma, dur: ContinuousClock.now - start, ctx: ["result": .string(result)])
    guard result != "ok" else { return IntegrityResult(result: result, corruptCopy: nil) }
    guard copyOnFailure else { return IntegrityResult(result: result, corruptCopy: nil) }
    let copy = Self.corruptURL(for: url, at: now)
    try FileManager.default.copyItem(at: url, to: copy)
    let wal = URL(fileURLWithPath: url.path + "-wal")
    if FileManager.default.fileExists(atPath: wal.path) {
      try FileManager.default.copyItem(at: wal, to: URL(fileURLWithPath: copy.path + "-wal"))
    }
    log.emit(.fault, .dbIntegrityFailed, msg: "integrity check failed", ctx: [
      "check": .string(pragma), "result": .string(result), "corrupt_copy": .string(copy.path)
    ])
    return IntegrityResult(result: result, corruptCopy: copy)
  }

  /// Online backup into a temp file, then an atomic rename to `tokenbe.sqlite.bak` (03 § Durability).
  /// Logged `db.backup {bytes, dur_ms}`; a failure logs `db.backup_failed {err}` and leaves the old backup.
  @discardableResult
  public func backup() async throws -> BackupResult {
    let start = ContinuousClock.now
    let target = backupURL
    let temp = url.deletingLastPathComponent()
      .appendingPathComponent("\(Self.fileName).bak.tmp-\(UUID().uuidString)")
    do {
      let destination = try DatabaseQueue(path: temp.path)
      try pool.backup(to: destination)
      try destination.close()
      guard rename(temp.path, target.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    } catch {
      unlink(temp.path)
      log.emit(.error, .dbBackupFailed, msg: "backup failed", err: error)
      throw error
    }
    let bytes = Self.fileSize(target)
    log.emit(.info, .dbBackup, msg: "backup written", dur: ContinuousClock.now - start, ctx: ["bytes": .int(bytes)])
    return BackupResult(url: target, bytes: bytes)
  }

  /// `PRAGMA incremental_vacuum` (after roll-ups, 03), logged `db.vacuum {pages_freed}`. Returns the pages freed.
  @discardableResult
  public func incrementalVacuum() async throws -> Int {
    let freed = try await pool.writeWithoutTransaction { db in
      let before = try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
      try db.execute(sql: "PRAGMA incremental_vacuum")
      let after = try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
      return before - after
    }
    log.emit(.info, .dbVacuum, msg: "incremental vacuum", ctx: ["pages_freed": .int(freed)])
    return freed
  }

  static func corruptURL(for url: URL, at date: Date) -> URL {
    URL(fileURLWithPath: url.path + ".corrupt-\(DBTime.fileStamp(date))")
  }
}

/// A database ready for use after launch step 2, and the repair done on the way, if any.
public struct OpenedDatabase: Sendable {
  public let database: AppDatabase
  public let recovery: DatabaseRecovery?
}

/// 04 startup step 2: open with 03's PRAGMAs, `quick_check`, migrate.
/// - Corrupt (`SQLITE_CORRUPT`, `SQLITE_NOTADB`, or `quick_check` not `ok`): the file and its `-wal`/`-shm` are moved
///   to `tokenbe.sqlite.corrupt-<ts>` (`db.corrupt`), then `tokenbe.sqlite.bak` is restored if present
///   (`db.restore`), else a fresh database is created.
/// - Anything else (permissions, a failed migration, corruption again after the repair) throws
///   `DatabaseOpenError` and leaves the files as they are.
public enum DatabaseOpener {
  public static func open(
    directory: URL, migrations: [Migration]? = nil, logPipeline: LogPipeline? = nil,
    now: @Sendable () -> Date = { Date() }
  ) async throws -> OpenedDatabase {
    let log = StoreLog(pipeline: logPipeline)
    let url = directory.appendingPathComponent(AppDatabase.fileName)
    let failure = { (migration: String?, error: any Error) in
      DatabaseOpenError(migration: migration, message: String(describing: error), databasePath: url.path,
                        backupPath: AppDatabase.backupURL(for: url).path)
    }
    let database: AppDatabase
    var recovery: DatabaseRecovery?
    do {
      try makePrivateDirectory(directory)
      do {
        database = try await openChecked(url, log: log)
      } catch let corrupt as CorruptDatabase {
        recovery = try recover(url, corrupt: corrupt, log: log, at: now())
        database = try await openChecked(url, log: log)
      }
    } catch {
      throw failure(nil, error)
    }
    do {
      try await Migrator(migrations: migrations ?? Migration.bundled(), log: log).migrate(database)
    } catch let failed as Migrator.Failure {
      throw failure(failed.migration.name, failed.underlying)
    } catch {
      throw failure(nil, error)
    }
    return OpenedDatabase(database: database, recovery: recovery)
  }

  /// The support folder is created `0700` (14 § Stage 2.1); an existing folder is tightened too.
  static func makePrivateDirectory(_ directory: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  /// Opens and runs `quick_check`; any sign of corruption becomes `CorruptDatabase` with every connection closed.
  static func openChecked(_ url: URL, log: StoreLog) async throws -> AppDatabase {
    let database: AppDatabase
    do {
      database = try AppDatabase(url: url, log: log)
    } catch let error as DatabaseError where isCorruption(error) {
      throw CorruptDatabase(check: nil, detail: String(describing: error))
    }
    let result: IntegrityResult
    do {
      result = try await database.check("quick_check", evt: .dbQuickCheck, copyOnFailure: false)
    } catch let error as DatabaseError where isCorruption(error) {
      try database.close()
      throw CorruptDatabase(check: "quick_check", detail: String(describing: error))
    }
    guard result.isOK else {
      try database.close()
      throw CorruptDatabase(check: "quick_check", detail: result.result)
    }
    return database
  }

  static func isCorruption(_ error: DatabaseError) -> Bool {
    error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB
  }

  /// Moves the corrupt file and its sidecars aside, then restores the backup if there is one.
  static func recover(_ url: URL, corrupt: CorruptDatabase, log: StoreLog, at date: Date) throws -> DatabaseRecovery {
    let manager = FileManager.default
    let moved = AppDatabase.corruptURL(for: url, at: date)
    if let check = corrupt.check {
      log.emit(.fault, .dbIntegrityFailed, msg: "integrity check failed", ctx: [
        "check": .string(check), "result": .string(corrupt.detail), "corrupt_copy": .string(moved.path)
      ])
    }
    try manager.moveItem(at: url, to: moved)
    for suffix in ["-wal", "-shm"] where manager.fileExists(atPath: url.path + suffix) {
      try manager.moveItem(atPath: url.path + suffix, toPath: moved.path + suffix)
    }
    log.emit(.fault, .dbCorrupt, msg: "database corrupt; moved aside", ctx: [
      "path": .string(url.path), "moved_to": .string(moved.path), "detail": .string(corrupt.detail)
    ])
    let backup = AppDatabase.backupURL(for: url)
    guard manager.fileExists(atPath: backup.path) else {
      return DatabaseRecovery(corruptCopy: moved, restoredFrom: nil)
    }
    try manager.copyItem(at: backup, to: url)
    log.emit(.warn, .dbRestore, msg: "restored from backup", ctx: ["from_backup": .string(backup.path)])
    return DatabaseRecovery(corruptCopy: moved, restoredFrom: backup)
  }
}
