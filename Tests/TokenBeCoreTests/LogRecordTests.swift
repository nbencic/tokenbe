import Foundation
import Testing
@testable import TokenBeCore

/// 07 § Record shape: key order, omission of absent fields, escaping, string truncation and the 2 KiB ctx cap.
@Suite struct LogRecordTests {
  static let keyOrder = ["ts", "lvl", "cat", "evt", "msg", "acct", "job", "attempt", "err", "dur_ms", "ctx", "pid", "thr", "v"]

  static func full() -> LogRecord {
    LogRecord(
      ts: Date(timeIntervalSince1970: 1_762_697_001.5), lvl: .error, cat: .poll("openai"), evt: .pollFailed,
      msg: "usage poll failed", acct: "openai", job: "usage", attempt: 2,
      err: LogError(type: "PollError.transport", code: -1001, desc: "The request timed out."), durMs: 10_012,
      ctx: ["url": "https://api.openai.com/v1/organization/usage/completions", "status": nil],
      pid: 4132, thr: "actor:AccountPoller(openai)", v: "1.0.0 (112)"
    )
  }

  static func parse(_ line: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
    return try #require(object as? [String: Any])
  }

  static func keyPositions(_ line: String) -> [String] {
    keyOrder.filter { line.contains("\"\($0)\":") }
      .sorted { line.range(of: "\"\($0)\":")!.lowerBound < line.range(of: "\"\($1)\":")!.lowerBound }
  }

  @Test("matches the 07 example exactly")
  func matchesExample() {
    let expected = #"{"ts":"2025-11-09T14:03:21.500Z","lvl":"error","cat":"poll.openai","evt":"poll.failed","msg":"usage poll failed","acct":"openai","job":"usage","attempt":2,"err":{"type":"PollError.transport","code":-1001,"desc":"The request timed out."},"dur_ms":10012,"ctx":{"status":null,"url":"https://api.openai.com/v1/organization/usage/completions"},"pid":4132,"thr":"actor:AccountPoller(openai)","v":"1.0.0 (112)"}"#
    #expect(Self.full().jsonLine() == expected)
  }

  @Test("keys appear in the order of 07 and the line parses")
  func keyOrderAndParse() throws {
    let line = Self.full().jsonLine()
    #expect(Self.keyPositions(line) == Self.keyOrder)
    let parsed = try Self.parse(line)
    #expect(parsed["evt"] as? String == "poll.failed")
    #expect((parsed["err"] as? [String: Any])?["code"] as? Int == -1001)
  }

  @Test("absent optional fields are omitted; required ones stay (Q-007)")
  func omitsAbsentFields() throws {
    let record = LogRecord(ts: Date(), lvl: .info, cat: .app, evt: .appLaunch, msg: "launch", pid: 1, thr: "main", v: "dev")
    let line = record.jsonLine()
    #expect(Self.keyPositions(line) == ["ts", "lvl", "cat", "evt", "msg", "ctx", "pid", "thr", "v"])
    #expect(try Self.parse(line)["ctx"] is [String: Any])
  }

  @Test("escapes quotes, backslashes, control characters and keeps Unicode")
  func escaping() throws {
    let text = "quote \" backslash \\ newline \n tab \t bell \u{07} formfeed \u{0C} back \u{08} cr \r — Benčić ≈ ±"
    var record = Self.full()
    record.msg = text
    record.ctx = ["s": .string(text), "nan": .double(.nan), "inf": .double(.infinity), "d": 1.5, "b": true, "i": -3]
    let parsed = try Self.parse(record.jsonLine())
    #expect(parsed["msg"] as? String == text)
    let ctx = try #require(parsed["ctx"] as? [String: Any])
    #expect(ctx["s"] as? String == text)
    #expect(ctx["nan"] is NSNull)
    #expect(ctx["inf"] is NSNull)
    #expect(ctx["d"] as? Double == 1.5)
    #expect(ctx["b"] as? Bool == true)
    #expect(ctx["i"] as? Int == -3)
  }

  @Test("strings are truncated to 512 characters ending in …")
  func truncation() {
    let long = String(repeating: "x", count: 2000)
    let record = LogRecord.sanitized(
      ts: Date(), lvl: .info, cat: .app, evt: .appLaunch, msg: long, acct: long, job: nil, attempt: nil,
      err: LogError(type: "T", code: nil, desc: long), durMs: nil, ctx: ["k": .string(long)],
      pid: 1, thr: "main", v: "dev", redactor: Redactor()
    )
    #expect(record.msg.count == 512)
    #expect(record.msg.hasSuffix("…"))
    #expect(record.acct?.count == 512)
    #expect(record.err?.desc.count == 512)
    if case .string(let value) = record.ctx["k"] { #expect(value.count == 512) } else { Issue.record("ctx k missing") }
    #expect(LogRecord.truncate("short") == "short")
  }

  @Test("ctx is capped at 2 KiB after redaction, in sorted key order, with ctx_truncated (Q-007)")
  func contextCap() throws {
    var ctx: [String: LogValue] = [:]
    for index in 0..<40 { ctx[String(format: "k%02d", index)] = .string(String(repeating: "v", count: 100)) }
    let record = LogRecord.sanitized(
      ts: Date(), lvl: .info, cat: .app, evt: .appLaunch, msg: "m", acct: nil, job: nil, attempt: nil,
      err: nil, durMs: nil, ctx: ctx, pid: 1, thr: "main", v: "dev", redactor: Redactor()
    )
    #expect(JSONText.object(record.ctx).utf8.count <= LogRecord.maxContextBytes)
    #expect(record.ctx[LogRecord.contextTruncatedKey] == .bool(true))
    #expect(record.ctx["k00"] != nil)
    #expect(record.ctx["k39"] == nil)
    let small = LogRecord.cappedContext(["a": 1])
    #expect(small == ["a": 1])
  }

  @Test("LogError names enum cases as Type.case and keeps code/description")
  func errorNaming() {
    enum PollError: Error { case transport(code: Int), decode }
    struct Plain: Error {}
    #expect(LogError(PollError.transport(code: 3)).type == "PollError.transport")
    #expect(LogError(PollError.decode).type == "PollError.decode")
    #expect(LogError(Plain()).type == "Plain")
    let nsError = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "timed out"])
    let converted = LogError(nsError)
    #expect(converted.code == -1001)
    #expect(converted.desc == "timed out")
  }

  @Test("levels and categories")
  func levelsAndCategories() {
    #expect(LogLevel.allCases.sorted() == [.debug, .info, .notice, .warn, .error, .fault])
    #expect(LogLevel.warn > .info)
    let names: [Cat] = [.app, .sched, .poll("xai"), .normalize, .price, .ledger, .ingest, .keychain, .db, .ui, .update, .crash]
    #expect(names.map(\.name) == ["app", "sched", "poll.xai", "normalize", "price", "ledger", "ingest", "keychain", "db", "ui", "update", "crash"])
    #expect(OSLogSink.osLevel(.fault) == .fault)
    #expect(OSLogSink.osLevel(.warn) == .default)
    #expect(OSLogSink.osLevel(.debug) == .debug)
    #expect(OSLogSink.osLevel(.info) == .info)
    #expect(OSLogSink.osLevel(.error) == .error)
  }

  @Test("durations are whole milliseconds; ctx accepts literals")
  func durationsAndLiterals() {
    #expect(LogPipeline.milliseconds(.milliseconds(10_012)) == 10_012)
    #expect(LogPipeline.milliseconds(.seconds(2) + .microseconds(1500)) == 2001)
    let ctx: [String: LogValue] = ["s": "text \(1)", "i": 2, "d": 0.5, "b": false, "n": nil]
    #expect(ctx["s"] == .string("text 1"))
    #expect(ctx["n"] == .null)
  }
}
