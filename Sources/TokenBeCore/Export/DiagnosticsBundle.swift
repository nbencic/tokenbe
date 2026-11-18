import Foundation

/// What the app hands the bundle: the places and values Core cannot read on its own.
public struct DiagnosticsInputs: Sendable {
  /// `~/Library/Logs/TokenBe` (or the test root's).
  public var logsDirectory: URL
  /// The in-memory ring (07 § Sinks 3), oldest first; records are redacted before they enter it.
  public var breadcrumbs: [LogRecord]
  /// Every `tb.*` key and its value in effect (`Settings.diagnosticsValues()`).
  public var settings: [String: LogValue]
  public var appVersion: String

  public init(logsDirectory: URL, breadcrumbs: [LogRecord], settings: [String: LogValue], appVersion: String) {
    self.logsDirectory = logsDirectory
    self.breadcrumbs = breadcrumbs
    self.settings = settings
    self.appVersion = appVersion
  }
}

/// The bundle written: where, its size, and the file names inside, sorted.
public struct DiagnosticsResult: Sendable, Equatable {
  public var url: URL
  public var bytes: Int
  public var files: [String]
}

/// `ditto` exited non-zero.
public struct DittoFailed: Error, Sendable, Equatable, CustomStringConvertible {
  public let status: Int32
  public let stderr: String
  public var description: String { "ditto exited \(status): \(stderr)" }
}

/// `Export diagnostics…` (07 § Diagnostics bundle; 14 § Stage 9.3). The files 07 lists are staged in a temporary
/// folder and zipped with `/usr/bin/ditto -c -k --sequesterRsrc` (D-ditto-zip):
/// - the last 3 NDJSON log files, as written (each record was redacted before it was written);
/// - `breadcrumbs.ndjson`, `settings.json`, `schema.sql`, `db-stats.json`, `poll_state.json` (`last_raw` as text),
///   `price-overrides.json`, `environment.json`.
///
/// Every text TokenBe writes here passes the Redactor once more. The database file and the Keychain are never read.
/// The pipeline is drained first, so the newest log holds the records up to the click. Logs
/// `app.diagnostics_exported {path, bytes, files}` (07); a failure is thrown for the caller (`ui.error`).
public enum DiagnosticsBundle {
  public static let logFileCount = 3
  public static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
  /// 07's files besides the logs, in its order.
  public static let fixedFiles = ["breadcrumbs.ndjson", "settings.json", "schema.sql", "db-stats.json",
                                  "poll_state.json", "price-overrides.json", "environment.json"]

  /// `TokenBe-diagnostics-20261118-143005.zip` (07), in UTC (Q-057).
  public static func fileName(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let part = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let stamp = String(format: "%04d%02d%02d-%02d%02d%02d", part.year ?? 0, part.month ?? 0, part.day ?? 0,
                       part.hour ?? 0, part.minute ?? 0, part.second ?? 0)
    return "TokenBe-diagnostics-\(stamp).zip"
  }

  /// The newest `count` log files by (day, rotation index); crash files and strays are not logs.
  static func lastLogs(in directory: URL, count: Int = logFileCount) throws -> [URL] {
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    let files = names.compactMap { NDJSONSink.logFile(named: $0, in: directory, calendar: .current) }
    return files.sorted { ($0.day, $0.index) > ($1.day, $1.index) }.prefix(count).map(\.url)
  }

  @discardableResult
  public static func export(
    store: any DiagnosticsRepository, inputs: DiagnosticsInputs, to url: URL, now: Date = Date(),
    redactor: Redactor = Log.redactor, flush: @Sendable () async -> Void = { await Log.current?.drain() },
    log: EventLog = EventLog(), scratch: URL = FileManager.default.temporaryDirectory
  ) async throws -> DiagnosticsResult {
    await flush()
    let snapshot = try await store.diagnosticsSnapshot()
    let manager = FileManager.default
    let work = scratch.appendingPathComponent("tokenbe-diagnostics-\(UUID().uuidString)")
    let staging = work.appendingPathComponent("bundle", isDirectory: true)
    do {
      try manager.createDirectory(at: staging, withIntermediateDirectories: true)
      let files = try stage(snapshot, inputs: inputs, now: now, redactor: redactor, into: staging)
      let zip = work.appendingPathComponent("bundle.zip")
      try await run(ditto, ["-c", "-k", "--sequesterRsrc", staging.path, zip.path])
      if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
      try manager.moveItem(at: zip, to: url)
      try manager.removeItem(at: work)
      let bytes = (try manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
      log.emit(.info, .appDiagnosticsExported, cat: .app, msg: "diagnostics exported", ctx: [
        "path": .string(url.path), "bytes": .int(bytes), "files": .int(files.count)
      ])
      return DiagnosticsResult(url: url, bytes: bytes, files: files)
    } catch {
      removeStaging(work, log: log)
      throw error
    }
  }

  /// Writes every file into `folder`; returns their names, sorted.
  static func stage(_ snapshot: DiagnosticsSnapshot, inputs: DiagnosticsInputs, now: Date, redactor: Redactor,
                    into folder: URL) throws -> [String] {
    func write(_ name: String, _ text: String) throws {
      try Data(redactor.redact(text).utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
    }
    func json(_ object: Any) throws -> String {
      let data = try JSONSerialization.data(withJSONObject: object,
                                            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
      return (String(bytes: data, encoding: .utf8) ?? "") + "\n"
    }
    var names: [String] = []
    for log in try lastLogs(in: inputs.logsDirectory) {
      try FileManager.default.copyItem(at: log, to: folder.appendingPathComponent(log.lastPathComponent))
      names.append(log.lastPathComponent)
    }
    try write("breadcrumbs.ndjson", inputs.breadcrumbs.map { $0.jsonLine() + "\n" }.joined())
    try write("settings.json", try json(inputs.settings.mapValues(any)))
    try write("schema.sql", snapshot.schemaSQL)
    try write("db-stats.json", try json([
      "tables": snapshot.tableRows, "size_bytes": snapshot.sizeBytes, "page_count": snapshot.pageCount,
      "page_size": snapshot.pageSize, "freelist_count": snapshot.freelistCount
    ] as [String: Any]))
    try write("poll_state.json", try json(snapshot.pollStates.map(pollState)))
    try write("price-overrides.json", try json(snapshot.priceOverrides.map {
      ["model": $0.model, "json": $0.json, "updated_at": $0.updatedAt]
    }))
    try write("environment.json", try json(environment(appVersion: inputs.appVersion, now: now)))
    return (names + fixedFiles).sorted()
  }

  /// A `poll_state` row with its columns; `last_raw` as text (Base64 when it is not UTF-8), redacted again on write.
  static func pollState(_ row: PollStateRecord) -> [String: Any] {
    let raw: Any = row.lastRaw.map { String(data: $0, encoding: .utf8) ?? $0.base64EncodedString() } ?? NSNull()
    return [
      "account_id": row.accountId, "job": row.job, "last_attempt_at": row.lastAttemptAt ?? NSNull(),
      "last_success_at": row.lastSuccessAt ?? NSNull(), "last_error_class": row.lastErrorClass ?? NSNull(),
      "last_error_message": row.lastErrorMessage ?? NSNull(), "consecutive_failures": row.consecutiveFailures,
      "circuit_open_until": row.circuitOpenUntil ?? NSNull(), "cursor": row.cursor ?? NSNull(), "last_raw": raw
    ]
  }

  /// 07: macOS, app version, Low Power Mode, locale, time zone.
  static func environment(appVersion: String, now: Date) -> [String: Any] {
    let info = ProcessInfo.processInfo
    return [
      "macos": info.operatingSystemVersionString, "app_version": appVersion, "low_power": info.isLowPowerModeEnabled,
      "locale": Locale.current.identifier, "timezone": TimeZone.current.identifier,
      "exported_at": DBTime.string(now)
    ]
  }

  static func any(_ value: LogValue) -> Any {
    switch value {
    case .string(let text): text
    case .int(let number): number
    case .double(let number): number
    case .bool(let flag): flag
    case .null: NSNull()
    }
  }

  /// Runs a tool and waits for it without blocking a thread; a non-zero exit throws `DittoFailed` with its stderr.
  static func run(_ tool: URL, _ arguments: [String]) async throws {
    let process = Process()
    process.executableURL = tool
    process.arguments = arguments
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
    guard status == 0 else {
      let text = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw DittoFailed(status: status, stderr: text)
    }
  }

  /// A failed export leaves no staging folder behind; if even that fails, it is logged.
  static func removeStaging(_ folder: URL, log: EventLog) {
    guard FileManager.default.fileExists(atPath: folder.path) else { return }
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      log.emit(.error, .uiError, cat: .ui, msg: "diagnostics staging folder not removed", err: error, ctx: [
        "view": "settings.advanced", "path": .string(folder.path)
      ])
    }
  }
}
