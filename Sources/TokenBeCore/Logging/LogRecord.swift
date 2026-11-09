import Foundation

/// Record level (07 § Level policy). Ordered from least to most severe.
public enum LogLevel: String, Sendable, CaseIterable, Comparable {
  case debug, info, notice, warn, error, fault

  private var rank: Int {
    switch self {
    case .debug: 0
    case .info: 1
    case .notice: 2
    case .warn: 3
    case .error: 4
    case .fault: 5
    }
  }

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Record category (07 § Record shape). `poll(_)` takes the provider id, e.g. `.poll("openai")` → `poll.openai`.
public enum Cat: Sendable, Equatable {
  case app, sched, poll(String), normalize, price, ledger, ingest, keychain, db, ui, update, crash

  public var name: String {
    switch self {
    case .app: "app"
    case .sched: "sched"
    case .poll(let provider): "poll.\(provider)"
    case .normalize: "normalize"
    case .price: "price"
    case .ledger: "ledger"
    case .ingest: "ingest"
    case .keychain: "keychain"
    case .db: "db"
    case .ui: "ui"
    case .update: "update"
    case .crash: "crash"
    }
  }
}

/// A flat `ctx` value (07: primitives only, never nested).
public enum LogValue: Sendable, Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case null
}

extension LogValue: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, ExpressibleByIntegerLiteral,
  ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
  public init(integerLiteral value: Int) { self = .int(value) }
  public init(floatLiteral value: Double) { self = .double(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(nilLiteral: ()) { self = .null }
}

/// The `err` object of a record: `{"type","code","desc"}`.
public struct LogError: Sendable, Equatable {
  public var type: String
  public var code: Int?
  public var desc: String

  public init(type: String, code: Int?, desc: String) {
    self.type = type
    self.code = code
    self.desc = desc
  }

  /// `type` is `TypeName.caseName` for enum errors (e.g. `PollError.transport`), else the type name.
  public init(_ error: any Error) {
    let typeName = String(describing: Swift.type(of: error))
    let described = String(describing: error)
    let caseName = described.prefix { $0 != "(" }
    let isCaseName = !caseName.isEmpty && caseName != typeName
      && caseName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
      && caseName.first?.isLowercase == true
    let nsError = error as NSError
    self.init(
      type: isCaseName ? "\(typeName).\(caseName)" : typeName,
      code: nsError.code,
      desc: nsError.localizedDescription
    )
  }
}

/// One NDJSON record (07 § Record shape). Build records through `LogRecord.sanitized`, which redacts and truncates.
public struct LogRecord: Sendable, Equatable {
  public static let maxStringLength = 512
  public static let maxContextBytes = 2048
  public static let contextTruncatedKey = "ctx_truncated"

  public var ts: Date
  public var lvl: LogLevel
  public var cat: Cat
  public var evt: Evt
  public var msg: String
  public var acct: String?
  public var job: String?
  public var attempt: Int?
  public var err: LogError?
  public var durMs: Int?
  public var ctx: [String: LogValue]
  public var pid: Int32
  public var thr: String
  public var v: String

  public init(
    ts: Date, lvl: LogLevel, cat: Cat, evt: Evt, msg: String,
    acct: String? = nil, job: String? = nil, attempt: Int? = nil, err: LogError? = nil, durMs: Int? = nil,
    ctx: [String: LogValue] = [:], pid: Int32, thr: String, v: String
  ) {
    self.ts = ts
    self.lvl = lvl
    self.cat = cat
    self.evt = evt
    self.msg = msg
    self.acct = acct
    self.job = job
    self.attempt = attempt
    self.err = err
    self.durMs = durMs
    self.ctx = ctx
    self.pid = pid
    self.thr = thr
    self.v = v
  }

  // swiftlint:disable function_parameter_count
  /// Redacts every string, then truncates strings to 512 characters and caps `ctx` at 2 KiB (07).
  /// Redaction runs first so a key cut by truncation cannot escape the patterns.
  public static func sanitized(
    ts: Date, lvl: LogLevel, cat: Cat, evt: Evt, msg: String,
    acct: String?, job: String?, attempt: Int?, err: LogError?, durMs: Int?,
    ctx: [String: LogValue], pid: Int32, thr: String, v: String, redactor: Redactor
  ) -> LogRecord {
    func clean(_ value: String) -> String { truncate(redactor.redact(value)) }
    let cleanErr = err.map { LogError(type: clean($0.type), code: $0.code, desc: clean($0.desc)) }
    var cleanCtx: [String: LogValue] = [:]
    for (key, value) in ctx {
      if case .string(let text) = value { cleanCtx[key] = .string(clean(text)) } else { cleanCtx[key] = value }
    }
    return LogRecord(
      ts: ts, lvl: lvl, cat: cat, evt: evt, msg: clean(msg),
      acct: acct.map(clean), job: job.map(clean), attempt: attempt, err: cleanErr, durMs: durMs,
      ctx: cappedContext(cleanCtx), pid: pid, thr: clean(thr), v: v
    )
  }

  // swiftlint:enable function_parameter_count

  /// Truncates to `maxStringLength` characters, the last being `…`.
  public static func truncate(_ value: String) -> String {
    guard value.count > maxStringLength else { return value }
    return String(value.prefix(maxStringLength - 1)) + "…"
  }

  /// Keeps keys in sorted order while the rendered object fits in `maxContextBytes`; marks the rest as dropped.
  static func cappedContext(_ ctx: [String: LogValue]) -> [String: LogValue] {
    guard JSONText.object(ctx).utf8.count > maxContextBytes else { return ctx }
    let marker = ",\(JSONText.quoted(contextTruncatedKey)):true"
    var kept: [String: LogValue] = [:]
    var size = 2 + marker.utf8.count  // braces + marker
    for key in ctx.keys.sorted() {
      guard let value = ctx[key] else { continue }
      let entry = JSONText.quoted(key) + ":" + JSONText.value(value)
      let added = entry.utf8.count + (kept.isEmpty ? 0 : 1)
      if size + added > maxContextBytes { break }
      kept[key] = value
      size += added
    }
    kept[contextTruncatedKey] = .bool(true)
    return kept
  }

  /// The record as one JSON line (no trailing newline), keys in the order of 07.
  public func jsonLine() -> String {
    var out = "{\"ts\":" + JSONText.quoted(LogRecord.timestamp(ts))
    out += ",\"lvl\":" + JSONText.quoted(lvl.rawValue)
    out += ",\"cat\":" + JSONText.quoted(cat.name)
    out += ",\"evt\":" + JSONText.quoted(evt.rawValue)
    out += ",\"msg\":" + JSONText.quoted(msg)
    if let acct { out += ",\"acct\":" + JSONText.quoted(acct) }
    if let job { out += ",\"job\":" + JSONText.quoted(job) }
    if let attempt { out += ",\"attempt\":\(attempt)" }
    if let err {
      out += ",\"err\":{\"type\":" + JSONText.quoted(err.type)
      out += ",\"code\":" + (err.code.map { String($0) } ?? "null")
      out += ",\"desc\":" + JSONText.quoted(err.desc) + "}"
    }
    if let durMs { out += ",\"dur_ms\":\(durMs)" }
    out += ",\"ctx\":" + JSONText.object(ctx)
    out += ",\"pid\":\(pid)"
    out += ",\"thr\":" + JSONText.quoted(thr)
    out += ",\"v\":" + JSONText.quoted(v)
    return out + "}"
  }

  /// `2026-11-09T14:03:21.512Z`.
  public static func timestamp(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }
}

/// Minimal RFC 8259 writer for log lines. Hand-written so key order is fixed on every toolchain.
enum JSONText {
  static func object(_ ctx: [String: LogValue]) -> String {
    "{" + ctx.keys.sorted().map { quoted($0) + ":" + value(ctx[$0] ?? .null) }.joined(separator: ",") + "}"
  }

  static func value(_ value: LogValue) -> String {
    switch value {
    case .string(let text): quoted(text)
    case .int(let number): String(number)
    case .double(let number): number.isFinite ? String(describing: number) : "null"
    case .bool(let flag): flag ? "true" : "false"
    case .null: "null"
    }
  }

  static func quoted(_ text: String) -> String { "\"" + escaped(text) + "\"" }

  /// Escapes for use inside a JSON string literal (without the surrounding quotes).
  static func escaped(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.utf8.count)
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if scalar.value < 0x20 {
          let hex = String(scalar.value, radix: 16)
          out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out
  }
}
