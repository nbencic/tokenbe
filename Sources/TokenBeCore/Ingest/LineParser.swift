import Foundation

/// One valid version-1 harness line (06 § Line format), normalized (05) but not yet stored.
public struct HarnessLine: Sendable, Equatable {
  public var provider: ProviderID
  /// 1–128 characters; with the provider, the dedup key (`harness_event` primary key).
  public var requestID: String
  /// The app tag, lowercased (06 regex).
  public var app: String
  /// The last 4 characters of `key_hint`, never more (03).
  public var keyHint: String?
  /// `ts` as given, parsed.
  public var date: Date
  public var model: String
  /// `true` for `status == "ok"`, `false` for `"error"` (03 `status` 1/0).
  public var succeeded: Bool
  /// The `usage` object, re-serialized with sorted keys; its content is the provider's, unchanged (`usage_json`).
  public var usageJSON: String
  /// Nil when normalization failed (`classes_json = NULL`, `normalize.failed`).
  public var classes: TokenClasses?
  /// 06: used as the line's cost instead of the price book, for `openrouter` only.
  public var costCents: Int64?
  /// Diagnostics the caller logs once per file (`ingest.unknown_fields`, `ingest.key_hint_truncated`) or per day
  /// (`normalize.unknown_keys`), and per line (`normalize.failed`, `normalize.negative`).
  public var unknownFields: [String] = []
  public var keyHintTruncated = false
  public var normalization: HarnessNormalizer.Output

  /// `classes` as `classes_json` (03).
  public var classesJSON: String? {
    classes.map {
      "{\"cache_read\":\($0.cacheRead),\"cache_write_1h\":\($0.cacheWrite1h),\"cache_write_5m\":\($0.cacheWrite5m)," +
        "\"input_uncached\":\($0.inputUncached),\"output\":\($0.output),\"reasoning\":\($0.reasoning)," +
        "\"requests\":\($0.requests)}"
    }
  }
}

/// Why a line was not accepted, with the event 07 logs for it.
public enum LineRejection: Error, Sendable, Equatable {
  case badJSON
  case badVersion
  case unknownProvider
  case badApp
  /// A required field missing or of the wrong shape; 07 names no event of its own, so it logs `ingest.bad_json`
  /// with the field (Q-049).
  case badField(String)
  case lineTooLong

  public var event: Evt {
    switch self {
    case .badJSON, .badField: .ingestBadJson
    case .badVersion: .ingestBadVersion
    case .unknownProvider: .ingestUnknownProvider
    case .badApp: .ingestBadApp
    case .lineTooLong: .ingestLineTooLong
    }
  }

  /// A file whose first non-empty line is rejected like this goes to `rejected/` whole (06 § Tailing 6).
  public var rejectsFile: Bool { self == .badJSON || self == .badVersion }
}

/// 06 § Line format, version 1: one line's bytes into a `HarnessLine` or a rejection.
public enum LineParser {
  /// 06: a longer line is rejected (`ingest.line_too_long`).
  public static let maxLineBytes = 64 * 1024
  static let fields: Set<String> = ["v", "ts", "provider", "app", "key_hint", "request_id", "model", "usage",
                                    "status", "cost_cents"]

  public static func parse(_ bytes: Data) -> Result<HarnessLine, LineRejection> {
    guard bytes.count <= maxLineBytes else { return .failure(.lineTooLong) }
    let object: [String: Any]
    do {
      guard let parsed = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
        return .failure(.badJSON)
      }
      object = parsed
    } catch {
      // A malformed line is data, not a failure of TokenBe: the caller counts and logs it (`ingest.bad_json`).
      return .failure(.badJSON)
    }
    return header(object).flatMap { body(object, header: $0) }
  }

  /// `v`, `ts`, `provider`, `app`, in 06's order.
  struct Header {
    var date: Date
    var provider: ProviderID
    var app: String
  }

  static func header(_ object: [String: Any]) -> Result<Header, LineRejection> {
    guard let version = integer(object["v"]), version == 1 else { return .failure(.badVersion) }
    guard let ts = object["ts"] as? String, let date = date(ts) else { return .failure(.badField("ts")) }
    guard let name = object["provider"] as? String, let provider = ProviderID(rawValue: name) else {
      return .failure(.unknownProvider)
    }
    guard let app = (object["app"] as? String)?.lowercased(), isAppTag(app) else { return .failure(.badApp) }
    return .success(Header(date: date, provider: provider, app: app))
  }

  static func body(_ object: [String: Any], header: Header) -> Result<HarnessLine, LineRejection> {
    guard let requestID = object["request_id"] as? String, (1...128).contains(requestID.count) else {
      return .failure(.badField("request_id"))
    }
    guard let model = object["model"] as? String, !model.isEmpty else { return .failure(.badField("model")) }
    guard let usage = object["usage"] as? [String: Any] else { return .failure(.badField("usage")) }
    guard let status = object["status"] as? String, status == "ok" || status == "error" else {
      return .failure(.badField("status"))
    }
    let hint: (value: String?, truncated: Bool)
    switch keyHint(object["key_hint"]) {
    case .success(let parsed): hint = parsed
    case .failure(let rejection): return .failure(rejection)
    }
    let usageJSON: String
    do {
      let data = try JSONSerialization.data(withJSONObject: usage, options: [.sortedKeys])
      usageJSON = String(bytes: data, encoding: .utf8) ?? "{}"
    } catch {
      // Unreachable for an object JSONSerialization just parsed; treated like any other unreadable usage.
      return .failure(.badField("usage"))
    }
    let normalization = HarnessNormalizer.normalize(header.provider, usage: usage)
    return .success(HarnessLine(
      provider: header.provider, requestID: requestID, app: header.app, keyHint: hint.value, date: header.date,
      model: model, succeeded: status == "ok", usageJSON: usageJSON, classes: normalization.classes,
      costCents: header.provider == .openrouter ? integer(object["cost_cents"]) : nil,
      unknownFields: object.keys.filter { !fields.contains($0) }.sorted(), keyHintTruncated: hint.truncated,
      normalization: normalization
    ))
  }

  /// 06 `key_hint`: optional; `…` dropped; only the last 4 characters kept; over 12 characters is flagged.
  static func keyHint(_ value: Any?) -> Result<(value: String?, truncated: Bool), LineRejection> {
    guard let value else { return .success((nil, false)) }
    guard let text = value as? String else { return .failure(.badField("key_hint")) }
    let bare = text.hasPrefix("\u{2026}") ? String(text.dropFirst()) : text
    return .success((bare.isEmpty ? nil : String(bare.suffix(4)), bare.count > 12))
  }

  /// 06: 1–64 characters, `^[a-z0-9][a-z0-9._-]{0,63}$` after lowercasing.
  public static func isAppTag(_ tag: String) -> Bool {
    tag.range(of: "^[a-z0-9][a-z0-9._-]{0,63}$", options: .regularExpression) != nil
  }

  /// An integral JSON number (not a Boolean).
  static func integer(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let double = number.doubleValue
    guard double == double.rounded(), abs(double) < 9e15 else { return nil }
    return number.int64Value
  }

  /// RFC 3339 with `Z` or an offset, with or without fractional seconds. Nil when it is neither; the caller rejects
  /// the line and logs it, so the parse error itself is not logged here.
  static func date(_ text: String) -> Date? {
    for style in [Date.ISO8601FormatStyle(includingFractionalSeconds: true), Date.ISO8601FormatStyle()] {
      do {
        return try style.parse(text)
      } catch {
        continue
      }
    }
    return nil
  }
}
