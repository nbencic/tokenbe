import Darwin
import Foundation

/// The 09 settings ingestion follows (`tb.ingest.*`, `tb.retention.hourlyDays`).
public struct IngestSettings: Sendable, Equatable {
  public var enabled: Bool
  public var moveWhenDone: Bool
  /// 06 `ingest.too_old`: older lines are stored without a bucket.
  public var hourlyRetentionDays: Int

  public init(enabled: Bool = true, moveWhenDone: Bool = true, hourlyRetentionDays: Int = 90) {
    self.enabled = enabled
    self.moveWhenDone = moveWhenDone
    self.hourlyRetentionDays = hourlyRetentionDays
  }

  @MainActor public init(_ settings: Settings) {
    self.init(enabled: settings.ingestEnabled, moveWhenDone: settings.ingestMoveWhenDone,
              hourlyRetentionDays: settings.retentionHourlyDays)
  }

  public static let keys: Set<SettingsKey> = [.ingestEnabled, .ingestMoveWhenDone, .retentionHourlyDays]
}

/// What Settings → Sources → Harness reports shows (08): the mode, the files being read, the last line, today's
/// counters, and the files large enough to rotate.
public struct IngestStatus: Sendable, Equatable {
  public enum Mode: String, Sendable {
    case stopped, fsevents, poll, unwritable
  }

  public var mode: Mode = .stopped
  /// Accepted files in the folder (not yet moved).
  public var files = 0
  public var lastLineAt: Date?
  /// The local day the counters belong to (`yyyy-MM-dd`).
  public var day = ""
  public var linesOK = 0
  public var linesDuplicate = 0
  public var linesRejected = 0
  /// Files over 512 MiB (06: recommend rotation).
  public var largeFiles: [String] = []

  public init() {}
}

/// 06 § Tailing algorithm and § processLine (14 § Stage 7.2 step 3): one actor owns the drop folder. Every change
/// rescans it; each accepted file is read from its stored offset in 64 KiB chunks, its complete lines parsed,
/// normalized and priced, and applied in 1 000-line transactions with the file's new offset (V7). A file quiet for
/// 2 s is moved to `ingested/` when `tb.ingest.moveWhenDone` is on and nobody holds it; a file whose first line is
/// not v1 JSON goes to `rejected/`.
public actor IngestService {
  public let folder: URL
  var ingestedFolder: URL { folder.appendingPathComponent("ingested", isDirectory: true) }
  var rejectedFolder: URL { folder.appendingPathComponent("rejected", isDirectory: true) }

  static let largeFileBytes: Int64 = 512 * 1024 * 1024
  static let burstLines = 10_000
  static let batchLines = 1_000
  static let futureSkew: TimeInterval = 300
  static let maxReadAttempts = 5
  static let fallbackPollSeconds = 30

  let store: any IngestRepository
  let watcher: any FileWatcher
  let fallback: any FileWatcher
  let clock: any Clock<Duration>
  let quiescence: Duration
  let pricer: @Sendable () async -> Pricer
  let now: @Sendable () -> Date
  let log: EventLog
  private(set) var settings: IngestSettings
  private(set) var status = IngestStatus()

  var files: [String: IngestFileRecord] = [:]
  var watchTask: Task<Void, Never>?
  var quiet: [String: Task<Void, Never>] = [:]
  var scanning = false
  var rescanRequested = false
  var skipped: Set<String> = []
  var notes: Set<String> = []
  var readAttempts: [String: Int] = [:]
  let unknownKeysOnce = DailyOnce()
  private var observers: [UUID: AsyncStream<IngestStatus>.Continuation] = [:]

  public init(folder: URL, store: any IngestRepository, watcher: any FileWatcher, fallback: any FileWatcher,
              clock: any Clock<Duration> = ContinuousClock(), quiescence: Duration = .seconds(2),
              settings: IngestSettings, pricer: @escaping @Sendable () async -> Pricer = { Pricer() },
              now: @escaping @Sendable () -> Date = { Date() }, logPipeline: LogPipeline? = nil) {
    self.folder = folder
    self.store = store
    self.watcher = watcher
    self.fallback = fallback
    self.clock = clock
    self.quiescence = quiescence
    self.settings = settings
    self.pricer = pricer
    self.now = now
    log = EventLog(pipeline: logPipeline)
  }

  // MARK: - Lifecycle

  /// 04 startup step 5: make the folders, resume the stored offsets, scan, then watch. `expectFolder` is true when
  /// the folder existed before (not the first launch): its absence is then logged `ingest.folder_recreated`.
  public func start(expectFolder: Bool) async {
    guard prepareFolders(expectFolder: expectFolder) else { return }
    do {
      for file in try await store.loadIngestFiles() { files[file.path] = file }
    } catch {
      log.emit(.error, .ingestReadFailed, cat: .ingest, msg: "ingest_file rows not loaded", err: error, ctx: [
        "file": "ingest_file", "attempt": 1
      ])
    }
    if settings.enabled { await begin() }
  }

  /// 09 `tb.ingest.*`: the watch starts and stops with `enabled`; `moveWhenDone` is read when a file goes quiet.
  public func apply(_ next: IngestSettings) async {
    let wasEnabled = settings.enabled
    settings = next
    guard wasEnabled != next.enabled, status.mode != .unwritable else { return }
    if next.enabled { await begin() } else { stop(reason: "disabled") }
  }

  /// `ingest.stop {reason}`: `disabled` (09) or `quit`.
  public func stop(reason: String) {
    guard watchTask != nil else { return }
    watchTask?.cancel()
    watchTask = nil
    for task in quiet.values { task.cancel() }
    quiet = [:]
    update { $0.mode = .stopped }
    log.emit(.info, .ingestStop, cat: .ingest, msg: "ingest stopped", ctx: ["reason": .string(reason)])
  }

  /// The current status, then every change (Settings → Sources).
  public nonisolated func statusUpdates() -> AsyncStream<IngestStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: IngestStatus.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    Task { await self.register(id, continuation) }
    continuation.onTermination = { _ in Task { await self.unregister(id) } }
    return stream
  }

  private func register(_ id: UUID, _ continuation: AsyncStream<IngestStatus>.Continuation) {
    observers[id] = continuation
    continuation.yield(status)
  }

  private func unregister(_ id: UUID) { observers[id] = nil }

  func update(_ change: (inout IngestStatus) -> Void) {
    var next = status
    change(&next)
    guard next != status else { return }
    status = next
    for observer in observers.values { observer.yield(next) }
  }

  /// Creates `ingest/`, `ingested/`, `rejected/`. An unwritable folder disables ingestion (06 failure table).
  func prepareFolders(expectFolder: Bool) -> Bool {
    let manager = FileManager.default
    let missing = !manager.fileExists(atPath: folder.path)
    do {
      for url in [folder, ingestedFolder, rejectedFolder] {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
      }
    } catch {
      unwritable(error)
      return false
    }
    if missing && expectFolder {
      log.emit(.warn, .ingestFolderRecreated, cat: .ingest, msg: "ingest folder recreated", ctx: [
        "path": .string(folder.path)
      ])
    }
    guard manager.isWritableFile(atPath: folder.path) else {
      unwritable(CocoaError(.fileWriteNoPermission))
      return false
    }
    return true
  }

  private func unwritable(_ error: any Error) {
    update { $0.mode = .unwritable }
    log.emit(.error, .ingestFolderUnwritable, cat: .ingest, msg: "ingest folder not writable", err: error, ctx: [
      "path": .string(folder.path)
    ])
  }

  /// FSEvents, or the 30 s poll when FSEvents cannot start (`ingest.fsevents_failed`); then a first scan.
  private func begin() async {
    guard watchTask == nil else { return }
    let stream: AsyncStream<[String]>
    var mode = IngestStatus.Mode.fsevents
    do {
      stream = try watcher.changes(in: folder)
    } catch {
      log.emit(.error, .ingestFseventsFailed, cat: .ingest, msg: "FSEvents unavailable; polling the folder",
               err: error, ctx: ["fallback_poll_s": .int(Self.fallbackPollSeconds)])
      do {
        stream = try fallback.changes(in: folder)
        mode = .poll
      } catch {
        log.emit(.error, .ingestFseventsFailed, cat: .ingest, msg: "folder poll unavailable; ingest stopped",
                 err: error, ctx: ["fallback_poll_s": .int(Self.fallbackPollSeconds)])
        return
      }
    }
    watchTask = Task { [weak self] in
      for await _ in stream {
        await self?.scan()
      }
    }
    update { $0.mode = mode }
    await scan()
    log.emit(.info, .ingestStart, cat: .ingest, msg: "ingest started", ctx: [
      "files": .int(status.files), "mode": .string(mode.rawValue)
    ])
  }
}
