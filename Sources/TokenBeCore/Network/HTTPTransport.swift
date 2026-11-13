import Foundation

/// One HTTP request, as an adapter builds it (02). Header names are sent as given.
public struct HTTPRequest: Sendable, Equatable {
  public var method: String
  public var url: URL
  public var headers: [String: String]
  public var body: Data?
  /// Seconds without data before the request fails; nil keeps the session's 15 s (02: the price feed uses 10 s).
  public var timeout: TimeInterval?

  public init(method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil,
              timeout: TimeInterval? = nil) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
    self.timeout = timeout
  }
}

/// One HTTP response, any status. Non-2xx statuses are not transport errors; `PollError.from(_:)` classifies them.
public struct HTTPResponse: Sendable, Equatable {
  public var status: Int
  public var headers: [String: String]
  public var body: Data

  public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.status = status
    self.headers = headers
    self.body = body
  }

  /// The header's value, matching the name case-insensitively (HTTP field names are case-insensitive).
  public func header(_ name: String) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }
}

/// Why no response arrived.
public enum TransportError: Error, Sendable, Equatable {
  /// DNS, TLS, timeout, offline, cancelled: whatever `URLSession` reported.
  case urlError(URLError)
  /// The body exceeded the cap (14 § Stage 3.1: 20 MiB); reading stopped there.
  case tooLarge(limit: Int)
  /// The session returned something that is not an HTTP response.
  case notHTTP
  /// DEBUG fixture mode: no fixture file matches the request (Q-026).
  case noFixture(String)
}

/// Every HTTP request of TokenBe goes through this seam (14 § 0.3): `URLSessionTransport` in the app,
/// `StubTransport` in tests, `FixtureTransport` in DEBUG fixture mode.
public protocol HTTPTransport: Sendable {
  func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse
}
