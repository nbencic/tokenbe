import Foundation
import Synchronization

/// Delivers records to the sinks (07). `emit` is synchronous and never blocks: it redacts, truncates, stores a
/// breadcrumb and yields into ONE bounded `AsyncStream` (capacity 4 096). A single consumer task awaits each sink in
/// order, so records reach every sink in emission order. On overflow the record is dropped and counted; the count is
/// reported as `app.log_dropped` every 60 s by the consumer itself, so the report cannot be dropped by a full stream.
/// The NDJSON sink flushes itself after `error`/`fault` records; the timer asks every sink to flush once a second.
public final class LogPipeline: Sendable {
  public static let defaultCapacity = 4096
  public static let flushInterval = Duration.seconds(1)
  public static let dropReportInterval = Duration.seconds(60)

  enum Item: Sendable {
    case record(LogRecord)
    case flush
    case reportDropped
    case barrier(CheckedContinuation<Bool, Never>)
  }

  public let redactor: Redactor
  public let breadcrumbs: Breadcrumbs
  public let crashRing: CrashRing?
  public let version: String
  let sinks: [any LogSink]
  private let now: @Sendable () -> Date
  private let level: Mutex<LogLevel>
  private let dropped = Atomic<Int>(0)
  private let stream: AsyncStream<Item>
  private let continuation: AsyncStream<Item>.Continuation
  private let consumer = Mutex<Task<Void, Never>?>(nil)
  private let timer = Mutex<Task<Void, any Error>?>(nil)

  public init(
    sinks: [any LogSink],
    redactor: Redactor = Redactor(),
    breadcrumbs: Breadcrumbs = Breadcrumbs(),
    crashRing: CrashRing? = nil,
    minimumLevel: LogLevel = .info,
    capacity: Int = LogPipeline.defaultCapacity,
    version: String = LogPipeline.bundleVersion(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.sinks = sinks
    self.redactor = redactor
    self.breadcrumbs = breadcrumbs
    self.crashRing = crashRing
    self.version = version
    self.now = now
    self.level = Mutex(minimumLevel)
    (stream, continuation) = AsyncStream.makeStream(of: Item.self, bufferingPolicy: .bufferingOldest(max(1, capacity)))
  }

  /// `CFBundleShortVersionString (CFBundleVersion)` of the running bundle, or `dev` outside an app bundle.
  public static func bundleVersion() -> String {
    let info = Bundle.main.infoDictionary
    guard let short = info?["CFBundleShortVersionString"] as? String else { return "dev" }
    return "\(short) (\(info?["CFBundleVersion"] as? String ?? "0"))"
  }

  /// Records below this level are not delivered to sinks (they still become breadcrumbs). `tb.log.level`, 09.
  public var minimumLevel: LogLevel {
    get { level.withLock { $0 } }
    set { level.withLock { $0 = newValue } }
  }

  /// Records dropped since the last `app.log_dropped` report.
  public var droppedCount: Int { dropped.load(ordering: .relaxed) }

  // MARK: - Lifecycle

  /// Starts the consumer only (no timers). Idempotent.
  public func startConsumer() {
    consumer.withLock { task in
      guard task == nil else { return }
      task = Task { [self] in
        for await item in stream { await handle(item) }
      }
    }
  }

  /// Starts the consumer and the 1 s flush / 60 s drop-report timer on `clock` (`ContinuousClock` in the app).
  public func start<C: Clock>(clock: C) where C.Duration == Duration {
    startConsumer()
    timer.withLock { task in
      guard task == nil else { return }
      task = Task { [self] in
        var lastReport = clock.now
        while true {
          try await clock.sleep(until: clock.now.advanced(by: LogPipeline.flushInterval), tolerance: nil)
          continuation.yield(.flush)
          if lastReport.duration(to: clock.now) >= LogPipeline.dropReportInterval {
            // Retries while the stream is full, so the report is never itself dropped (07: on the 60 s tick).
            await reportDroppedNow()
            lastReport = clock.now
          }
        }
      }
    }
  }

  /// Waits until every record emitted before this call has been written and all sinks have flushed.
  /// Requires a started consumer. While the stream is full it retries until the consumer makes room.
  public func drain() async {
    while true {
      let accepted = await withCheckedContinuation { (resume: CheckedContinuation<Bool, Never>) in
        switch continuation.yield(.barrier(resume)) {
        case .enqueued: break
        case .terminated: resume.resume(returning: true)
        case .dropped: resume.resume(returning: false)
        @unknown default: resume.resume(returning: true)
        }
      }
      if accepted { return }
      await Task.yield()
    }
  }

  /// Reports dropped records now instead of at the next 60 s tick.
  public func reportDroppedNow() async {
    while case .dropped = continuation.yield(.reportDropped) {
      await Task.yield()
    }
    await drain()
  }

  /// Drains, then stops the timer and the consumer (`applicationWillTerminate`, 07).
  public func shutdown() async {
    await drain()
    timer.withLock { $0?.cancel() }
    continuation.finish()
    let task = consumer.withLock { $0 }
    await task?.value
  }

  private func handle(_ item: Item) async {
    switch item {
    case .record(let record):
      for sink in sinks { await sink.write(record) }
    case .flush:
      for sink in sinks { await sink.flush() }
    case .reportDropped:
      let count = dropped.exchange(0, ordering: .relaxed)
      guard count > 0 else { return }
      let record = makeRecord(
        .warn, .appLogDropped, cat: .app, msg: "log records dropped", acct: nil, job: nil, attempt: nil,
        err: nil, dur: nil, ctx: ["count": .int(count)]
      )
      remember(record)
      guard record.lvl >= minimumLevel else { return }
      for sink in sinks { await sink.write(record) }
    case .barrier(let resume):
      for sink in sinks { await sink.flush() }
      resume.resume(returning: true)
    }
  }

  // MARK: - Emitting

  public func emit(
    _ lvl: LogLevel, _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil,
    attempt: Int? = nil, err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    let record = makeRecord(lvl, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt,
                            err: err, dur: dur, ctx: ctx)
    remember(record)
    guard lvl >= minimumLevel else { return }
    if case .dropped = continuation.yield(.record(record)) {
      dropped.add(1, ordering: .relaxed)
    }
  }

  /// `app.log_sink_failed`: to every sink except the NDJSON sink, plus breadcrumbs (07).
  public func reportSinkFailure(op: String, path: String, error: any Error) {
    let record = makeRecord(
      .error, .appLogSinkFailed, cat: .app, msg: "log sink failed", acct: nil, job: nil, attempt: nil,
      err: error, dur: nil, ctx: ["op": .string(op), "path": .string(path)]
    )
    remember(record)
    let targets = sinks.filter { !($0 is NDJSONSink) }
    guard !targets.isEmpty else { return }
    Task {
      for sink in targets { await sink.write(record) }
    }
  }

  private func remember(_ record: LogRecord) {
    breadcrumbs.append(record)
    crashRing?.record(line: record.jsonLine())
  }

  // swiftlint:disable:next function_parameter_count
  private func makeRecord(
    _ lvl: LogLevel, _ evt: Evt, cat: Cat, msg: String, acct: String?, job: String?, attempt: Int?,
    err: (any Error)?, dur: Duration?, ctx: [String: LogValue]
  ) -> LogRecord {
    LogRecord.sanitized(
      ts: now(), lvl: lvl, cat: cat, evt: evt, msg: msg, acct: acct, job: job, attempt: attempt,
      err: err.map { LogError($0) }, durMs: dur.map(LogPipeline.milliseconds), ctx: ctx,
      pid: getpid(), thr: LogPipeline.threadLabel(), v: version, redactor: redactor
    )
  }

  static func milliseconds(_ duration: Duration) -> Int {
    let parts = duration.components
    return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
  }

  /// `main`, or `thread:<id>` for any other thread.
  static func threadLabel() -> String {
    if Thread.isMainThread { return "main" }
    var id: UInt64 = 0
    pthread_threadid_np(nil, &id)
    return "thread:\(id)"
  }
}

/// The logging API every module uses (07, 12 § R5): `Log.error(.pollFailed, cat: .poll("openai"), msg: …)`.
/// `configure` installs the process-wide pipeline; until then records are kept as breadcrumbs only.
public enum Log {
  /// Shared by every pipeline configured here; secrets in flight are registered on it (R8).
  public static let redactor = Redactor()
  public static let breadcrumbs = Breadcrumbs()

  private static let pipeline = Mutex<LogPipeline?>(nil)
  private static let pendingLevel = Mutex(LogLevel.info)

  /// Installs the pipeline with `sinks` and starts its timers on `clock`. A previous pipeline is drained and stopped.
  @discardableResult
  public static func configure<C: Clock>(
    sinks: [any LogSink], clock: C, crashRing: CrashRing? = nil, version: String = LogPipeline.bundleVersion()
  ) -> LogPipeline where C.Duration == Duration {
    let configured = LogPipeline(
      sinks: sinks, redactor: redactor, breadcrumbs: breadcrumbs, crashRing: crashRing,
      minimumLevel: pendingLevel.withLock { $0 }, version: version
    )
    configured.start(clock: clock)
    let previous = pipeline.withLock { current in
      defer { current = configured }
      return current
    }
    if let previous {
      Task { await previous.shutdown() }
    }
    return configured
  }

  /// The installed pipeline, if any.
  public static var current: LogPipeline? { pipeline.withLock { $0 } }

  /// Default `.info` (`tb.log.level`, 09).
  public static var minimumLevel: LogLevel {
    get { current?.minimumLevel ?? pendingLevel.withLock { $0 } }
    set {
      pendingLevel.withLock { $0 = newValue }
      current?.minimumLevel = newValue
    }
  }

  public static func debug(
    _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil, attempt: Int? = nil,
    err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    emit(.debug, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
  }

  public static func info(
    _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil, attempt: Int? = nil,
    err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    emit(.info, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
  }

  public static func notice(
    _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil, attempt: Int? = nil,
    err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    emit(.notice, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
  }

  public static func warn(
    _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil, attempt: Int? = nil,
    err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    emit(.warn, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
  }

  public static func error(
    _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil, attempt: Int? = nil,
    err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    emit(.error, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
  }

  public static func fault(
    _ evt: Evt, cat: Cat, msg: String, acct: String? = nil, job: String? = nil, attempt: Int? = nil,
    err: (any Error)? = nil, dur: Duration? = nil, ctx: [String: LogValue] = [:]
  ) {
    emit(.fault, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
  }

  /// Called by `NDJSONSink` when it cannot write (`app.log_sink_failed`).
  public static func reportSinkFailure(op: String, path: String, error: any Error) {
    current?.reportSinkFailure(op: op, path: path, error: error)
  }

  // swiftlint:disable:next function_parameter_count
  private static func emit(
    _ lvl: LogLevel, _ evt: Evt, cat: Cat, msg: String, acct: String?, job: String?, attempt: Int?,
    err: (any Error)?, dur: Duration?, ctx: [String: LogValue]
  ) {
    if let installed = current {
      installed.emit(lvl, evt, cat: cat, msg: msg, acct: acct, job: job, attempt: attempt, err: err, dur: dur, ctx: ctx)
      return
    }
    breadcrumbs.append(
      LogRecord.sanitized(
        ts: Date(), lvl: lvl, cat: cat, evt: evt, msg: msg, acct: acct, job: job, attempt: attempt,
        err: err.map { LogError($0) }, durMs: dur.map(LogPipeline.milliseconds), ctx: ctx, pid: getpid(),
        thr: LogPipeline.threadLabel(), v: LogPipeline.bundleVersion(), redactor: redactor
      )
    )
  }
}
