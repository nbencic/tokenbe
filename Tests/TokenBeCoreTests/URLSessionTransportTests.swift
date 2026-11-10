import Foundation
import Synchronization
import Testing
@testable import TokenBeCore

/// Answers `URLSession` requests in-process: no request leaves the machine (11). Each test uses its own host, so
/// parallel tests never see each other's replies.
final class StubURLProtocol: URLProtocol {
  struct Reply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var chunks: [Data] = []
    var failure: URLError?
  }

  struct Seen: Sendable {
    var request: URLRequest
    var body: Data?
  }

  private static let replies = Mutex<[String: Reply]>([:])
  private static let seen = Mutex<[String: Seen]>([:])

  static func reply(host: String, _ reply: Reply) {
    replies.withLock { $0[host] = reply }
  }

  static func seenRequest(host: String) -> Seen? {
    seen.withLock { $0[host] }
  }

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let host = request.url?.host() ?? ""
    let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
    Self.seen.withLock { $0[host] = Seen(request: request, body: body) }
    guard let reply = Self.replies.withLock({ $0[host] }), let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    if let failure = reply.failure {
      client?.urlProtocol(self, didFailWithError: failure)
      return
    }
    let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                   headerFields: reply.headers)
    if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
    for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func read(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

/// 14 § Stage 3.1 Tests: headers through a local `URLProtocol` stub, the size cap, error translation, and the
/// session configuration of step 2.
@Suite struct URLSessionTransportTests {
  static func transport(cap: Int = URLSessionTransport.maxBodyBytes) -> URLSessionTransport {
    URLSessionTransport(version: "1.2.3", protocolClasses: [StubURLProtocol.self], maxBodyBytes: cap)
  }

  static func uniqueHost() -> String { "stub-\(UUID().uuidString.lowercased()).test" }

  @Test("sends method, headers, body and 02's User-Agent; returns status, headers and body")
  func roundTrip() async throws {
    let host = Self.uniqueHost()
    StubURLProtocol.reply(host: host, .init(status: 201, headers: ["X-Request-Id": "req_1"],
                                           chunks: [Data("{\"ok\":".utf8), Data("true}".utf8)]))
    let url = try #require(URL(string: "https://\(host)/v1/things?limit=2"))
    let request = HTTPRequest(method: "POST", url: url, headers: ["Authorization": "Bearer test-token",
                                                                  "User-Agent": "overridden"],
                              body: Data("{\"a\":1}".utf8))
    let response = try await Self.transport().send(request)
    #expect(response.status == 201)
    #expect(response.header("x-request-id") == "req_1")
    #expect(utf8Text(response.body) == "{\"ok\":true}")

    let seen = try #require(StubURLProtocol.seenRequest(host: host))
    #expect(seen.request.httpMethod == "POST")
    #expect(seen.request.url?.query() == "limit=2")
    #expect(seen.request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    #expect(seen.request.value(forHTTPHeaderField: "User-Agent") == "TokenBe/1.2.3 (+https://github.com/nbencic/tokenbe)")
    #expect(seen.body == Data("{\"a\":1}".utf8))
  }

  @Test("a 4xx or 5xx is a response, not a transport error")
  func errorStatusIsAResponse() async throws {
    let host = Self.uniqueHost()
    StubURLProtocol.reply(host: host, .init(status: 429, headers: ["Retry-After": "7"], chunks: [Data("{}".utf8)]))
    let response = try await Self.transport().send(HTTPRequest(url: try #require(URL(string: "https://\(host)/x"))))
    #expect(response.status == 429)
    #expect(PollError.from(response) == .rateLimited(retryAfter: .seconds(7)))
  }

  @Test("a body over the cap fails with tooLarge, by Content-Length or while streaming")
  func sizeCap() async throws {
    let declared = Self.uniqueHost()
    StubURLProtocol.reply(host: declared, .init(headers: ["Content-Length": "2048"],
                                               chunks: [Data(repeating: 65, count: 2048)]))
    await #expect(throws: TransportError.tooLarge(limit: 1024)) {
      try await Self.transport(cap: 1024).send(HTTPRequest(url: try #require(URL(string: "https://\(declared)/big"))))
    }

    let streamed = Self.uniqueHost()
    StubURLProtocol.reply(host: streamed, .init(chunks: Array(repeating: Data(repeating: 66, count: 512), count: 3)))
    await #expect(throws: TransportError.tooLarge(limit: 1024)) {
      try await Self.transport(cap: 1024).send(HTTPRequest(url: try #require(URL(string: "https://\(streamed)/big"))))
    }

    let exact = Self.uniqueHost()
    StubURLProtocol.reply(host: exact, .init(chunks: [Data(repeating: 67, count: 1024)]))
    let response = try await Self.transport(cap: 1024).send(HTTPRequest(url: try #require(URL(string: "https://\(exact)/ok"))))
    #expect(response.body.count == 1024)
  }

  @Test("URLSession failures become TransportError.urlError, and PollError.transport")
  func urlErrors() async throws {
    let host = Self.uniqueHost()
    StubURLProtocol.reply(host: host, .init(failure: URLError(.notConnectedToInternet)))
    let url = try #require(URL(string: "https://\(host)/x"))
    do {
      _ = try await Self.transport().send(HTTPRequest(url: url))
      Issue.record("expected a transport error")
    } catch {
      guard case .urlError(let urlError) = error else {
        Issue.record("unexpected \(error)")
        return
      }
      #expect(urlError.code == .notConnectedToInternet)
      #expect(PollError.from(error) == .transport(urlError))
    }
  }

  @Test("other errors are translated: cancellation, foreign errors, our own")
  func translation() {
    #expect(URLSessionTransport.transportError(CancellationError()) == .urlError(URLError(.cancelled)))
    #expect(URLSessionTransport.transportError(TransportError.notHTTP) == .notHTTP)
    let foreign = URLSessionTransport.transportError(CocoaError(.fileReadUnknown))
    guard case .urlError(let wrapped) = foreign else {
      Issue.record("expected urlError, got \(foreign)")
      return
    }
    #expect(wrapped.code == .unknown)
  }

  @Test("session configuration matches 14 § Stage 3.1 step 2")
  func configuration() {
    let configuration = Self.transport().session.configuration
    #expect(configuration.timeoutIntervalForRequest == 15)
    #expect(configuration.timeoutIntervalForResource == 30)
    #expect(configuration.waitsForConnectivity == false)
    #expect(configuration.httpShouldSetCookies == false)
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil || configuration.httpCookieAcceptPolicy == .never)
    #expect(URLSessionTransport.userAgent(version: "1.0.0") == "TokenBe/1.0.0 (+https://github.com/nbencic/tokenbe)")
    #expect(URLSessionTransport.maxBodyBytes == 20 * 1024 * 1024)
    let production = URLSessionTransport(version: "9.9")
    #expect(production.maxBodyBytes == 20 * 1024 * 1024)
    #expect(production.session.configuration.protocolClasses?.contains { $0 == StubURLProtocol.self } != true)
  }

  @Test("in a test process the app's transport cannot reach the network (11, R13; PM-3.1-1)")
  func noRealRequests() async throws {
    #expect(NoNetworkInTests.isActive)
    let before = NoNetworkInTests.blocked
    let transport = URLSessionTransport(version: "test")
    let url = try #require(URL(string: "https://api.openai.com/v1/organization/projects"))
    do {
      _ = try await transport.send(HTTPRequest(url: url))
      Issue.record("a real request went through")
    } catch {
      guard case .urlError(let urlError) = error else { Issue.record("unexpected \(error)"); return }
      #expect(urlError.code == .notConnectedToInternet)
    }
    #expect(NoNetworkInTests.blocked == before + 1)
    // The factory's network transport is guarded the same way.
    let made = Transports.make(fixtureMode: false, version: "test")
    await #expect(throws: TransportError.self) { try await made.send(HTTPRequest(url: url)) }
    #expect(NoNetworkInTests.blocked == before + 2)
  }
}
