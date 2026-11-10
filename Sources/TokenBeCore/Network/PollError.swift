import Foundation

/// The one error type every adapter reports (04 § Error taxonomy).
public enum PollError: Error, Sendable, Equatable {
  /// DNS, timeout, offline.
  case transport(URLError)
  /// 401, 403.
  case auth(http: Int, body: String)
  /// 429.
  case rateLimited(retryAfter: Duration?)
  /// 5xx.
  case server(http: Int, body: String)
  /// JSON present but shape wrong.
  case decode(field: String, path: String)
  /// Decoded, but with unexpected keys (non-fatal; logged, not thrown).
  case schemaDrift(unknownKeys: [String])
  /// e.g. "costs endpoint bucket_width must be 1d".
  case providerRule(String)
  case cancelled
}

extension PollError {
  /// Classifies a response (14 § Stage 3.1 step 3). Nil for 2xx. 401/403 → `auth`; 429 → `rateLimited` with
  /// `Retry-After` parsed as seconds or an HTTP-date (uncapped here; `RetryPolicy` caps it); 5xx → `server`.
  /// Any other status (3xx, other 4xx) → `providerRule("http <status>")`, never retried (Q-026). Adapters map
  /// provider-specific statuses, such as Anthropic's 400 for low credit, before calling this.
  public static func from(_ response: HTTPResponse, now: Date = Date()) -> PollError? {
    let body = String(bytes: response.body, encoding: .utf8) ?? "<\(response.body.count) bytes, not UTF-8>"
    switch response.status {
    case 200..<300: return nil
    case 401, 403: return .auth(http: response.status, body: body)
    case 429: return .rateLimited(retryAfter: retryAfter(response.header("Retry-After"), now: now))
    case 500..<600: return .server(http: response.status, body: body)
    default: return .providerRule("http \(response.status)")
    }
  }

  /// Classifies a failed send. A body over the cap is not transient, so it is a `decode` failure (no retry).
  public static func from(_ error: TransportError) -> PollError {
    switch error {
    case .urlError(let urlError) where urlError.code == .cancelled: .cancelled
    case .urlError(let urlError): .transport(urlError)
    case .tooLarge(let limit): .decode(field: "body", path: "larger than \(limit) bytes")
    case .notHTTP: .transport(URLError(.badServerResponse))
    case .noFixture(let route): .providerRule("no fixture for \(route)")
    }
  }

  /// `Retry-After` (RFC 9110 § 10.2.3): delay-seconds or an HTTP-date. A date in the past is zero; anything
  /// unparseable is nil, and the policy's 30 s default applies.
  static func retryAfter(_ value: String?, now: Date) -> Duration? {
    guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
    if let seconds = Int(value) { return seconds >= 0 ? .seconds(seconds) : nil }
    guard let date = httpDate(value) else { return nil }
    return .milliseconds(max(0, Int((date.timeIntervalSince(now) * 1000).rounded(.up))))
  }

  /// IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`), the form RFC 9110 requires senders to use.
  static func httpDate(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: text)
  }
}
