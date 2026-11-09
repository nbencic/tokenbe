import Foundation
import Testing
@testable import TokenBeCore

/// 07 § Crash handling: a dry run writes one parseable NDJSON line with the last 50 breadcrumbs; sentinel semantics.
/// Serialized because two tests touch the process-wide crash file descriptor. No real handler is ever installed here.
@Suite(.serialized) struct CrashHandlerTests {
  static func line(_ msg: String, evt: Evt = .pollStart) -> String {
    LogRecord(ts: Date(), lvl: .info, cat: .poll("openai"), evt: evt, msg: msg, pid: 1, thr: "main", v: "t").jsonLine()
  }

  /// Runs a dry-run crash write into a temp file and returns the written text.
  static func dryRun(_ ring: CrashRing, signal: Int32) throws -> String {
    let dir = try TempDirectory()
    let url = dir.url.appendingPathComponent("crash.ndjson")
    #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
    let fd = open(url.path, O_WRONLY | O_APPEND)
    #expect(fd >= 0)
    let written = ring.writeCrashRecord(signal: signal, to: fd)
    close(fd)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(written == text.utf8.count)
    return text
  }

  static func parse(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }

  @Test("dry run writes one parseable crash.signal line with breadcrumbs")
  func dryRunLine() throws {
    let ring = CrashRing(version: "1.2.3 (4)")
    ring.record(line: Self.line("first", evt: .appLaunch))
    ring.record(line: Self.line("second \"quoted\" \\ and\nnewline"))
    ring.record(line: Self.line("third", evt: .pollOk))
    let text = try Self.dryRun(ring, signal: SIGSEGV)
    #expect(text.hasSuffix("\n"))
    #expect(text.filter { $0 == "\n" }.count == 1)
    let record = try Self.parse(text)
    #expect(record["evt"] as? String == "crash.signal")
    #expect(record["lvl"] as? String == "fault")
    #expect(record["cat"] as? String == "crash")
    #expect(record["pid"] as? Int == Int(getpid()))
    #expect(record["v"] as? String == "1.2.3 (4)")
    let ts = try #require(record["ts"] as? String)
    #expect(ts.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil)
    let ctx = try #require(record["ctx"] as? [String: Any])
    #expect(ctx["signal"] as? String == "SIGSEGV")
    let crumbs = try #require(ctx["breadcrumbs"] as? String).components(separatedBy: "\n")
    #expect(crumbs.count == 3)
    let events = try crumbs.map { try Self.parse($0)["evt"] as? String }
    #expect(events == ["app.launch", "poll.start", "poll.ok"])
    #expect(try Self.parse(crumbs[1])["msg"] as? String == "second \"quoted\" \\ and\nnewline")
  }

  @Test("keeps only the last 50 breadcrumbs, oldest first")
  func lastFifty() throws {
    let ring = CrashRing(version: "t")
    for index in 0..<60 { ring.record(line: Self.line("n\(index)")) }
    let ctx = try #require(try Self.parse(Self.dryRun(ring, signal: SIGABRT))["ctx"] as? [String: Any])
    let crumbs = try #require(ctx["breadcrumbs"] as? String).components(separatedBy: "\n")
    #expect(crumbs.count == 50)
    #expect(try Self.parse(crumbs[0])["msg"] as? String == "n10")
    #expect(try Self.parse(crumbs[49])["msg"] as? String == "n59")
  }

  @Test("an oversized breadcrumb is cut to its slot and the line stays valid JSON")
  func oversizedBreadcrumb() throws {
    let long = String(repeating: "\"é\\", count: 2000)
    let slot = CrashRing.slotText(long)
    #expect(slot.utf8.count <= CrashRing.slotBytes)
    #expect(slot.hasSuffix("…"))
    #expect(CrashRing.slotText("short") == "short")
    let ring = CrashRing(version: "t")
    ring.record(line: long)
    for _ in 0..<49 { ring.record(line: Self.line(String(repeating: "y", count: 2000))) }
    let text = try Self.dryRun(ring, signal: SIGBUS)
    #expect(text.utf8.count <= CrashRing.bufferBytes)
    #expect(try Self.parse(text)["evt"] as? String == "crash.signal")
  }

  @Test("signal names, exception marker, unknown signal, empty ring, invalid fd")
  func names() throws {
    let ring = CrashRing(version: "t")
    let expected: [(Int32, String)] = [
      (SIGABRT, "SIGABRT"), (SIGBUS, "SIGBUS"), (SIGSEGV, "SIGSEGV"), (SIGILL, "SIGILL"), (SIGTRAP, "SIGTRAP"),
      (SIGFPE, "SIGFPE"), (CrashRing.exceptionSignal, "NSException"), (SIGUSR1, "UNKNOWN")
    ]
    for (number, name) in expected {
      let ctx = try #require(try Self.parse(Self.dryRun(ring, signal: number))["ctx"] as? [String: Any])
      #expect(ctx["signal"] as? String == name)
      #expect(ctx["breadcrumbs"] as? String == "")
    }
    #expect(ring.writeCrashRecord(signal: SIGSEGV, to: -1) == -1)
    #expect(CrashHandler.signals == [SIGABRT, SIGBUS, SIGSEGV, SIGILL, SIGTRAP, SIGFPE])
  }

  @Test("timestamp formatting without Foundation matches the calendar")
  func timestamps() {
    let cases: [(Int64, String)] = [
      (0, "1970-01-01T00:00:00.000Z"), (951_782_400_123, "2000-02-29T00:00:00.123Z"),
      (-1, "1969-12-31T23:59:59.999Z"), (1_762_697_001_512, "2025-11-09T14:03:21.512Z"),
      (253_402_300_799_999, "9999-12-31T23:59:59.999Z")
    ]
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    defer { buffer.deallocate() }
    for (millis, text) in cases {
      let count = CrashRing.formatTimestamp(millis: millis, into: buffer)
      #expect(String(bytes: UnsafeBufferPointer(start: buffer, count: count), encoding: .utf8) == text)
    }
    for (value, text) in [(Int64(0), "0"), (4132, "4132"), (1_234_567_890, "1234567890"), (-5, "0")] {
      let count = CrashRing.formatDecimal(value, into: buffer)
      #expect(String(bytes: UnsafeBufferPointer(start: buffer, count: count), encoding: .utf8) == text)
    }
  }

  @Test("the pipeline feeds the crash ring with every record, including those below the minimum level")
  func pipelineFeedsRing() async throws {
    let ring = CrashRing(version: "t")
    let pipeline = LogPipeline(sinks: [], crashRing: ring, minimumLevel: .warn, version: "t")
    pipeline.emit(.debug, .schedTick, cat: .sched, msg: "tick")
    pipeline.emit(.error, .pollFailed, cat: .poll("xai"), msg: "failed")
    let ctx = try #require(try Self.parse(Self.dryRun(ring, signal: SIGILL))["ctx"] as? [String: Any])
    let crumbs = try #require(ctx["breadcrumbs"] as? String).components(separatedBy: "\n")
    #expect(try crumbs.map { try Self.parse($0)["evt"] as? String } == ["sched.tick", "poll.failed"])
  }

  @Test("the crash file descriptor follows the NDJSON file and the previous one is closed")
  func crashTarget() async throws {
    let dir = try TempDirectory()
    let sink = NDJSONSink(directory: dir.url, crashTarget: true, onFailure: { _, _, _ in })
    await sink.write(LogRecord(ts: Date(), lvl: .info, cat: .app, evt: .appLaunch, msg: "m", pid: 1, thr: "t", v: "t"))
    let fd = CrashHandler.targetFD.load(ordering: .acquiring)
    #expect(fd >= 0)
    let ring = CrashRing(version: "t")
    #expect(ring.writeCrashRecord(signal: SIGTRAP, to: fd) > 0)
    await sink.flush()
    let url = try #require(await sink.currentFileURL())
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    // The crash line goes straight to disk, so it lands before records still in the sink's buffer.
    #expect(lines.filter { $0.contains("\"crash.signal\"") }.count == 1)
    CrashHandler.setTargetFileDescriptor(-1)
    #expect(fcntl(fd, F_GETFD) == -1, "previous descriptor closed")
  }

  @Test("running sentinel: absent → running → clean")
  func sentinel() throws {
    let dir = try TempDirectory()
    let sentinel = RunningSentinel(directory: dir.url.appendingPathComponent("support"))
    #expect(sentinel.url.lastPathComponent == ".running")
    #expect(!sentinel.wasUnclean())
    try sentinel.markRunning()
    #expect(sentinel.wasUnclean())
    try sentinel.markClean()
    #expect(!sentinel.wasUnclean())
    try sentinel.markClean()
    #expect(RunningSentinel.defaultDirectory.path.hasSuffix("Library/Application Support/TokenBe"))
  }
}
