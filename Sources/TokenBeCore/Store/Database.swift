import Foundation
import GRDB

/// Errors the store reports to callers. The app never sees GRDB's own error types (04).
public enum StoreError: Error, Sendable, Equatable {
  /// A primary-key or UNIQUE constraint refused the row (e.g. a second account for one provider, 03).
  case duplicate(String)
  /// The row to update or delete does not exist.
  case notFound(String)
}

/// The database could not be opened or migrated. Launch stops with an alert that names the migration, the error and
/// the backup path (03 § Migrations, 04 startup step 2). The database file is left as it was.
public struct DatabaseOpenError: LocalizedError, Sendable, CustomStringConvertible {
  /// `001_initial.sql` when a migration failed; nil when opening failed.
  public let migration: String?
  public let message: String
  public let databasePath: String
  public let backupPath: String

  public init(migration: String?, message: String, databasePath: String, backupPath: String) {
    self.migration = migration
    self.message = message
    self.databasePath = databasePath
    self.backupPath = backupPath
  }

  /// What `app.launch`'s `err.desc` shows.
  public var errorDescription: String? { description }

  public var description: String {
    "\(migration.map { "migration \($0): " } ?? "")\(message) (database \(databasePath), backup \(backupPath))"
  }
}

/// The repair done at launch when the database was corrupt (03 § Durability); the user is told both paths.
public struct DatabaseRecovery: Sendable, Equatable {
  /// Where the corrupt file was moved.
  public let corruptCopy: URL
  /// The backup that was restored, or nil when a fresh database was created.
  public let restoredFrom: URL?
}

/// Logs through the given pipeline (tests) or the process-wide `Log` (app).
struct StoreLog: Sendable {
  let pipeline: LogPipeline?

  func emit(_ lvl: LogLevel, _ evt: Evt, msg: String, err: (any Error)? = nil, dur: Duration? = nil,
            ctx: [String: LogValue] = [:]) {
    if let pipeline {
      pipeline.emit(lvl, evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
      return
    }
    switch lvl {
    case .debug: Log.debug(evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
    case .info: Log.info(evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
    case .notice: Log.notice(evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
    case .warn: Log.warn(evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
    case .error: Log.error(evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
    case .fault: Log.fault(evt, cat: .db, msg: msg, err: err, dur: dur, ctx: ctx)
    }
  }
}

/// RFC3339 UTC with milliseconds, the only timestamp format in the database (03).
public enum DBTime {
  /// Rounded to the nearest millisecond. `ISO8601FormatStyle` truncates the binary fraction (`.123` can print as
  /// `.122`), which would make a read-then-write drift, so the milliseconds are formatted from an integer.
  public static func string(_ date: Date) -> String {
    let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
    let seconds = millis.quotientAndRemainder(dividingBy: 1000)
    let (whole, fraction) = seconds.remainder < 0 ? (seconds.quotient - 1, seconds.remainder + 1000)
                                                  : (seconds.quotient, seconds.remainder)
    let base = Date(timeIntervalSince1970: TimeInterval(whole)).formatted(Date.ISO8601FormatStyle())
    return base.dropLast() + "." + String(String(fraction + 1000).dropFirst()) + "Z"
  }

  /// Nil when `text` is not in that format.
  public static func date(_ text: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: text)
  }

  /// `20261110T081530Z`, for file names such as `tokenbe.sqlite.corrupt-<ts>`.
  static func fileStamp(_ date: Date) -> String {
    date.formatted(
      Date.ISO8601FormatStyle(dateSeparator: .omitted, dateTimeSeparator: .standard, timeSeparator: .omitted)
    )
  }
}

/// `tokenbe.sqlite` (03): a GRDB `DatabasePool` with 03's PRAGMAs on every connection.
public final class AppDatabase: Sendable {
  public static let fileName = "tokenbe.sqlite"
  /// A write that waited longer than this for the writer logs `db.busy` (14 § Stage 2.1).
  static let busyThreshold = Duration.milliseconds(100)

  public let url: URL
  let pool: DatabasePool
  let log: StoreLog

  /// `tokenbe.sqlite.bak` in the same folder (03 § Durability).
  public var backupURL: URL { Self.backupURL(for: url) }

  static func backupURL(for url: URL) -> URL {
    url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
  }

  /// Opens (creating if needed) the database at `url` and logs `db.open`. Does not migrate or check integrity;
  /// `DatabaseOpener` does that in launch order.
  init(url: URL, log: StoreLog) throws {
    self.url = url
    self.log = log
    pool = try DatabasePool(path: url.path, configuration: Self.configuration())
    let info = try pool.read { db in
      (try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "", try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0)
    }
    log.emit(.info, .dbOpen, msg: "database open", ctx: [
      "path": .string(url.path), "size_bytes": .int(Self.fileSize(url)),
      "journal_mode": .string(info.0), "page_size": .int(info.1)
    ])
  }

  /// 03 § PRAGMAs. GRDB itself sets `journal_mode = WAL` on the writer and `foreign_keys = ON` on every
  /// connection. `auto_vacuum` must be set before any table exists, and GRDB's WAL setup creates a scratch table,
  /// so it is the first statement on the writer (Q-024). GRDB gives pool readers a 10 s busy timeout; 03 says
  /// 5000 ms on every connection, so `busy_timeout` is set again here, after GRDB's own setup.
  static func configuration() -> Configuration {
    var config = Configuration()
    config.foreignKeysEnabled = true
    config.busyMode = .timeout(5)
    config.prepareDatabase { db in
      if !db.configuration.readonly {
        try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
      }
      try db.execute(sql: """
        PRAGMA synchronous = NORMAL;
        PRAGMA cache_size = -2000;
        PRAGMA mmap_size = 0;
        PRAGMA temp_store = MEMORY;
        PRAGMA busy_timeout = 5000;
        """)
    }
    return config
  }

  /// Every write goes through here (04 I2). A wait for the writer above 100 ms logs `db.busy {op, waited_ms}`.
  func write<T: Sendable>(_ op: String, _ body: @escaping @Sendable (GRDB.Database) throws -> T) async throws -> T {
    let requested = ContinuousClock.now
    let log = log
    return try await pool.write { db in
      let waited = ContinuousClock.now - requested
      if waited > Self.busyThreshold {
        log.emit(.warn, .dbBusy, msg: "waited for the database writer", ctx: [
          "op": .string(op), "waited_ms": .int(LogPipeline.milliseconds(waited))
        ])
      }
      return try body(db)
    }
  }

  func read<T: Sendable>(_ body: @escaping @Sendable (GRDB.Database) throws -> T) async throws -> T {
    try await pool.read(body)
  }

  /// Closes every connection. Required before the file is moved or replaced.
  func close() throws {
    try pool.close()
  }

  /// Bytes on disk, 0 when the file does not exist.
  static func fileSize(_ url: URL) -> Int {
    var info = stat()
    return stat(url.path, &info) == 0 ? Int(info.st_size) : 0
  }
}
