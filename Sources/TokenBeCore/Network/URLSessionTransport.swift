import Foundation

/// `HTTPTransport` over `URLSession` (04 § Stack, 14 § Stage 3.1 step 2): an ephemeral session, 15 s request and
/// 30 s resource timeouts, no waiting for connectivity, no cookies, no cache, and 02's `User-Agent` on every request.
/// Bodies are read up to 20 MiB; a larger one fails with `TransportError.tooLarge`.
public final class URLSessionTransport: HTTPTransport {
  public static let maxBodyBytes = 20 * 1024 * 1024

  let session: URLSession
  let userAgent: String
  let maxBodyBytes: Int

  /// `version` is the app's `CFBundleShortVersionString`.
  public convenience init(version: String) {
    self.init(version: version, protocolClasses: nil, maxBodyBytes: Self.maxBodyBytes)
  }

  /// Tests pass a `URLProtocol` stub and a small cap; nothing else differs from the app's session.
  init(version: String, protocolClasses: [AnyClass]?, maxBodyBytes: Int) {
    let configuration = Self.configuration()
    if let protocolClasses { configuration.protocolClasses = protocolClasses }
    session = URLSession(configuration: configuration)
    userAgent = Self.userAgent(version: version)
    self.maxBodyBytes = maxBodyBytes
  }

  deinit {
    session.finishTasksAndInvalidate()
  }

  static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    configuration.waitsForConnectivity = false
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
  }

  /// 02 RULE: `TokenBe/<version> (+https://github.com/nbencic/tokenbe)`.
  static func userAgent(version: String) -> String {
    "TokenBe/\(version) (+https://github.com/nbencic/tokenbe)"
  }

  public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
    urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    do {
      let (bytes, response) = try await session.bytes(for: urlRequest)
      guard let http = response as? HTTPURLResponse else {
        bytes.task.cancel()
        throw TransportError.notHTTP
      }
      if http.expectedContentLength > Int64(maxBodyBytes) {
        bytes.task.cancel()
        throw TransportError.tooLarge(limit: maxBodyBytes)
      }
      var body = Data()
      if http.expectedContentLength > 0 { body.reserveCapacity(Int(http.expectedContentLength)) }
      for try await byte in bytes {
        guard body.count < maxBodyBytes else {
          bytes.task.cancel()
          throw TransportError.tooLarge(limit: maxBodyBytes)
        }
        body.append(byte)
      }
      return HTTPResponse(status: http.statusCode, headers: Self.headers(of: http), body: body)
    } catch {
      // Translation only; the poller logs the outcome (`poll.retry`, `poll.failed`, Q-026).
      throw Self.transportError(error)
    }
  }

  static func headers(of response: HTTPURLResponse) -> [String: String] {
    var headers: [String: String] = [:]
    for (name, value) in response.allHeaderFields {
      headers[String(describing: name)] = String(describing: value)
    }
    return headers
  }

  static func transportError(_ error: any Error) -> TransportError {
    switch error {
    case let transport as TransportError: transport
    case let urlError as URLError: .urlError(urlError)
    case is CancellationError: .urlError(URLError(.cancelled))
    default: .urlError(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
    }
  }
}
