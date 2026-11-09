import Foundation
import Synchronization
import Testing
@testable import TokenBeCore

/// 07 § Sinks: NDJSON parseable with key order; rotation (50 KiB test override) and midnight; retention; total cap;
/// flush rules; overflow → `app.log_dropped`; sink failures → `app.log_sink_failed` once per streak.
@Suite struct LogSinkTests {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zagreb") ?? .gmt
    return calendar
  }()

  static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
      ?? Date(timeIntervalSince1970: 0)
  }

  static func record(_ msg: String = "message", lvl: LogLevel = .info, evt: Evt = .pollOk) -> LogRecord {
    LogRecord(ts: Date(), lvl: lvl, cat: .poll("openai"), evt: evt, msg: msg, acct: "openai", job: "usage",
              ctx: ["rows": 3], pid: 1, thr: "main", v: "test")
  }

  static func read(_ url: URL) throws -> [String] {
    try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
  }

  /// Records failures reported by a sink.
  final class Failures: Sendable {
    private let items = Mutex<[String]>([])
    var ops: [String] { items.withLock { $0 } }
    var handler: NDJSONSink.FailureHandler { { [self] op, _, _ in items.withLock { $0.append(op) } } }
  }

  @Test("pipeline → NDJSON: one parseable line per record, keys in 07 order")
  func parseableAndOrdered() async throws {
    let dir = try TempDirectory()
    let sink = NDJSONSink(directory: dir.url, onFailure: { _, _, _ in })
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    for index in 0..<3 {
      pipeline.emit(.info, .pollOk, cat: .poll("openai"), msg: "ok \(index)", acct: "openai", job: "usage",
                    dur: .milliseconds(12), ctx: ["rows": .int(index)])
    }
    await pipeline.drain()
    let url = try #require(await sink.currentFileURL())
    #expect(url.lastPathComponent.wholeMatch(of: /tokenbe-\d{4}-\d{2}-\d{2}\.ndjson/) != nil)
    let lines = try Self.read(url)
    #expect(lines.count == 3)
    for (index, line) in lines.enumerated() {
      let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
      #expect(object["msg"] as? String == "ok \(index)")
      #expect(object["dur_ms"] as? Int == 12)
      #expect(LogRecordTests.keyPositions(line) == ["ts", "lvl", "cat", "evt", "msg", "acct", "job", "dur_ms", "ctx", "pid", "thr", "v"])
    }
  }

  @Test("rotates before a line would exceed the size limit (50 KiB override): -1, -2, …")
  func rotationBySize() async throws {
    let dir = try TempDirectory()
    let limit = 50 * 1024
    let sink = NDJSONSink(directory: dir.url, limits: .init(maxFileBytes: limit), onFailure: { _, _, _ in })
    for index in 0..<1200 { await sink.write(Self.record("record \(index) " + String(repeating: "z", count: 150))) }
    await sink.flush()
    let files = try dir.files()
    #expect(files.count >= 4)
    let day = String(files[0].dropFirst("tokenbe-".count).prefix(10))
    #expect(files.contains(NDJSONSink.fileName(day: day, index: 0)))
    #expect(files.contains(NDJSONSink.fileName(day: day, index: 1)))
    var total = 0
    for name in files {
      let lines = try Self.read(dir.url.appendingPathComponent(name))
      total += lines.count
      let size = try FileManager.default.attributesOfItem(atPath: dir.url.appendingPathComponent(name).path)[.size] as? Int
      #expect((size ?? 0) <= limit, "\(name) is \(size ?? 0) bytes")
    }
    #expect(total == 1200)
  }

  @Test("a new file starts at local midnight")
  func rotationAtMidnight() async throws {
    let dir = try TempDirectory()
    let clock = ManualDate(Self.date(2026, 11, 9, 23, 59, 59))
    let sink = NDJSONSink(directory: dir.url, now: clock.provider, calendar: Self.calendar, onFailure: { _, _, _ in })
    await sink.write(Self.record("before"))
    clock.set(Self.date(2026, 11, 10, 0, 0, 1))
    await sink.write(Self.record("after"))
    await sink.flush()
    #expect(try dir.files() == ["tokenbe-2026-11-09.ndjson", "tokenbe-2026-11-10.ndjson"])
    #expect(try Self.read(dir.url.appendingPathComponent("tokenbe-2026-11-09.ndjson")).count == 1)
  }

  @Test("reopening continues today's newest file instead of starting over")
  func continuesExistingFile() async throws {
    let dir = try TempDirectory()
    let clock = ManualDate(Self.date(2026, 11, 9))
    let first = NDJSONSink(directory: dir.url, now: clock.provider, calendar: Self.calendar, onFailure: { _, _, _ in })
    await first.write(Self.record("one"))
    await first.flush()
    let second = NDJSONSink(directory: dir.url, now: clock.provider, calendar: Self.calendar, onFailure: { _, _, _ in })
    await second.write(Self.record("two"))
    await second.flush()
    #expect(try dir.files() == ["tokenbe-2026-11-09.ndjson"])
    #expect(try Self.read(dir.url.appendingPathComponent("tokenbe-2026-11-09.ndjson")).count == 2)
  }

  @Test("retention deletes files older than retentionDays and leaves other files alone")
  func retention() async throws {
    let dir = try TempDirectory()
    for name in ["tokenbe-2026-10-20.ndjson", "tokenbe-2026-10-26.ndjson", "tokenbe-2026-10-30.ndjson",
                 "tokenbe-2026-10-30-1.ndjson", "notes.txt"] {
      #expect(FileManager.default.createFile(atPath: dir.url.appendingPathComponent(name).path, contents: Data("x\n".utf8)))
    }
    let sink = NDJSONSink(directory: dir.url, now: { Self.date(2026, 11, 9) }, calendar: Self.calendar,
                          onFailure: { _, _, _ in })
    await sink.write(Self.record())
    await sink.flush()
    #expect(try dir.files() == ["notes.txt", "tokenbe-2026-10-26.ndjson", "tokenbe-2026-10-30-1.ndjson",
                                "tokenbe-2026-10-30.ndjson", "tokenbe-2026-11-09.ndjson"])
  }

  @Test("setRetentionDays (tb.log.retentionDays) applies the new period at once")
  func retentionChange() async throws {
    let dir = try TempDirectory()
    #expect(FileManager.default.createFile(atPath: dir.url.appendingPathComponent("tokenbe-2026-11-01.ndjson").path, contents: Data("x\n".utf8)))
    let sink = NDJSONSink(directory: dir.url, now: { Self.date(2026, 11, 9) }, calendar: Self.calendar, onFailure: { _, _, _ in })
    await sink.write(Self.record())
    #expect(try dir.files().count == 2, "8 days old is within the default 14")
    await sink.setRetentionDays(7)
    #expect(try dir.files() == ["tokenbe-2026-11-09.ndjson"])
    #expect(await sink.limits.retentionDays == 7)
  }

  @Test("total cap deletes oldest files first and never the current one")
  func totalCap() async throws {
    let dir = try TempDirectory()
    let blob = Data(repeating: 0x61, count: 60_000)
    for name in ["tokenbe-2026-11-06.ndjson", "tokenbe-2026-11-07.ndjson", "tokenbe-2026-11-08.ndjson"] {
      #expect(FileManager.default.createFile(atPath: dir.url.appendingPathComponent(name).path, contents: blob))
    }
    let sink = NDJSONSink(directory: dir.url, limits: .init(totalCapBytes: 100_000), now: { Self.date(2026, 11, 9) },
                          calendar: Self.calendar, onFailure: { _, _, _ in })
    await sink.write(Self.record())
    await sink.flush()
    #expect(try dir.files() == ["tokenbe-2026-11-08.ndjson", "tokenbe-2026-11-09.ndjson"])
  }

  @Test("info waits for a flush; error/fault are written at once; 64 KiB threshold flushes")
  func flushRules() async throws {
    let dir = try TempDirectory()
    let sink = NDJSONSink(directory: dir.url, limits: .init(flushBytes: 2048), onFailure: { _, _, _ in })
    await sink.write(Self.record("buffered"))
    let url = try #require(await sink.currentFileURL())
    #expect(try Self.read(url).isEmpty)
    await sink.write(Self.record("boom", lvl: .error, evt: .pollFailed))
    #expect(try Self.read(url).count == 2)
    await sink.write(Self.record("fault", lvl: .fault, evt: .dbCorrupt))
    #expect(try Self.read(url).count == 3)
    for _ in 0..<12 { await sink.write(Self.record(String(repeating: "q", count: 200))) }
    #expect(try Self.read(url).count > 3, "threshold flush without flush()")
  }

  @Test("log directory is 0700 and files are 0600")
  func permissions() async throws {
    let dir = try TempDirectory()
    let logs = dir.url.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    let sink = NDJSONSink(directory: logs, onFailure: { _, _, _ in })
    await sink.write(Self.record())
    let url = try #require(await sink.currentFileURL())
    let dirMode = try FileManager.default.attributesOfItem(atPath: logs.path)[.posixPermissions] as? Int
    let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(dirMode == 0o700)
    #expect(fileMode == 0o600)
    #expect(NDJSONSink.defaultDirectory.path.hasSuffix("Library/Logs/TokenBe"))
  }

  @Test("a sink that cannot create its directory reports once per failure streak")
  func failureReportedOnce() async throws {
    let dir = try TempDirectory()
    let blocker = dir.url.appendingPathComponent("not-a-directory")
    #expect(FileManager.default.createFile(atPath: blocker.path, contents: Data("x".utf8)))
    let failures = Failures()
    let sink = NDJSONSink(directory: blocker.appendingPathComponent("logs"), onFailure: failures.handler)
    for _ in 0..<5 { await sink.write(Self.record()) }
    await sink.flush()
    #expect(failures.ops == ["mkdir"])
    #expect(await sink.currentFileURL() == nil)
  }

  @Test("app.log_sink_failed reaches other sinks and breadcrumbs, never the NDJSON sink")
  func sinkFailureRouting() async throws {
    let dir = try TempDirectory()
    let capture = CapturingLogSink()
    let ndjson = NDJSONSink(directory: dir.url, onFailure: { _, _, _ in })
    let pipeline = LogPipeline(sinks: [ndjson, capture], version: "test")
    pipeline.startConsumer()
    struct DiskFull: Error {}
    pipeline.reportSinkFailure(op: "write", path: "/tmp/x", error: DiskFull())
    for _ in 0..<1000 {
      if await !capture.records.isEmpty { break }
      await Task.yield()
    }
    let reported = try #require(await capture.records.first)
    #expect(reported.evt == .appLogSinkFailed)
    #expect(reported.lvl == .error)
    #expect(reported.ctx["op"] == "write")
    #expect(reported.err?.type == "DiskFull")
    #expect(pipeline.breadcrumbs.snapshot().map(\.evt) == [.appLogSinkFailed])
    await pipeline.drain()
    #expect(await ndjson.currentFileURL() == nil, "nothing was written to the NDJSON sink")
  }
}

/// Pipeline behaviour: overflow, timers, levels, breadcrumbs, os.Logger, shutdown.
extension LogSinkTests {
  @Test("overflow drops records, counts them, and reports app.log_dropped on the 60 s tick")
  func overflowReported() async throws {
    let capture = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [capture], capacity: 4, version: "test")
    for index in 0..<10 { pipeline.emit(.info, .pollStart, cat: .poll("xai"), msg: "start \(index)") }
    #expect(pipeline.droppedCount == 6)
    let clock = TestClock()
    pipeline.start(clock: clock)
    await clock.waitForSleepers()
    clock.advance(by: .seconds(60))
    await clock.waitForSleepers()
    await pipeline.drain()
    let records = await capture.records
    #expect(records.filter { $0.evt == .pollStart }.count == 4)
    let report = try #require(records.first { $0.evt == .appLogDropped })
    #expect(report.lvl == .warn)
    #expect(report.ctx["count"] == .int(6))
    #expect(pipeline.droppedCount == 0)
    await pipeline.shutdown()
  }

  @Test("no report when nothing was dropped; reportDroppedNow reports at once")
  func dropReportOnDemand() async throws {
    let quiet = CapturingLogSink()
    let idle = LogPipeline(sinks: [quiet], version: "test")
    idle.startConsumer()
    await idle.reportDroppedNow()
    #expect(await quiet.records.isEmpty)

    let capture = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [capture], capacity: 2, version: "test")
    for name in ["a", "b", "c"] { pipeline.emit(.info, .pollStart, cat: .app, msg: name) }
    #expect(pipeline.droppedCount == 1)
    pipeline.startConsumer()
    await pipeline.drain()
    await pipeline.reportDroppedNow()
    let records = await capture.records
    #expect(records.map(\.msg) == ["a", "b", "log records dropped"])
    #expect(records.last?.ctx["count"] == .int(1))
  }

  @Test("the 1 s timer flushes buffered lines without an explicit flush")
  func timerFlush() async throws {
    let dir = try TempDirectory()
    let sink = NDJSONSink(directory: dir.url, onFailure: { _, _, _ in })
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    let clock = TestClock()
    pipeline.start(clock: clock)
    pipeline.emit(.info, .pollOk, cat: .app, msg: "waiting for the timer")
    await clock.waitForSleepers()
    var url: URL?
    for _ in 0..<2000 {
      url = await sink.currentFileURL()
      if url != nil { break }
      await Task.yield()
    }
    let file = try #require(url)
    #expect(try Self.read(file).isEmpty)
    clock.advance(by: .seconds(1))
    var lines: [String] = []
    for _ in 0..<200 {
      lines = try Self.read(file)
      if !lines.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(lines.count == 1)
    await pipeline.shutdown()
  }

  @Test("records below the minimum level become breadcrumbs only")
  func minimumLevel() async {
    let capture = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [capture], minimumLevel: .warn, version: "test")
    pipeline.startConsumer()
    pipeline.emit(.info, .pollOk, cat: .app, msg: "hidden")
    pipeline.emit(.warn, .pollRetry, cat: .app, msg: "shown")
    pipeline.minimumLevel = .debug
    pipeline.emit(.debug, .schedTick, cat: .sched, msg: "now shown")
    await pipeline.drain()
    #expect(await capture.events() == [.pollRetry, .schedTick])
    #expect(pipeline.breadcrumbs.snapshot().map(\.evt) == [.pollOk, .pollRetry, .schedTick])
    #expect(pipeline.minimumLevel == .debug)
  }

  @Test("breadcrumbs keep the newest 500 records, oldest first")
  func breadcrumbRing() {
    let crumbs = Breadcrumbs()
    #expect(crumbs.capacity == 500)
    for index in 0..<520 { crumbs.append(Self.record("r\(index)")) }
    let snapshot = crumbs.snapshot()
    #expect(snapshot.count == 500)
    #expect(snapshot.first?.msg == "r20")
    #expect(snapshot.last?.msg == "r519")
    #expect(Breadcrumbs(capacity: 0).capacity == 1)
  }

  @Test("OSLogSink accepts every level; shutdown stops delivery cleanly")
  func osLogAndShutdown() async {
    let capture = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [OSLogSink(), capture], version: "test")
    pipeline.startConsumer()
    for level in LogLevel.allCases { pipeline.emit(level, .appLaunch, cat: .app, msg: "level \(level.rawValue)") }
    await pipeline.shutdown()
    #expect(await capture.records.count == LogLevel.allCases.count - 1, "debug is below the default minimum")
    pipeline.emit(.error, .appTerminate, cat: .app, msg: "after shutdown")
    await pipeline.drain()
    #expect(await capture.records.count == LogLevel.allCases.count - 1)
    #expect(OSLogSink.subsystem == "dev.bathyon.tokenbe")
    #expect(LogPipeline.bundleVersion().isEmpty == false)
    #expect(LogPipeline.threadLabel().isEmpty == false)
  }
}
