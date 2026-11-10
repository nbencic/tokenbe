import Foundation
@testable import TokenBeCore

/// `HTTPTransport` for tests (11 § Test doubles): maps `(method, path)` to a response, a fixture file or an error,
/// and records every request in order. Each route answers its queued results in turn; the last one repeats.
actor StubTransport: HTTPTransport {
  enum Answer: Sendable {
    case response(HTTPResponse)
    case fixture(URL)
    case failure(TransportError)
  }

  private var routes: [String: [Answer]] = [:]
  private(set) var calls: [HTTPRequest] = []

  init(_ routes: [String: [Answer]] = [:]) {
    self.routes = routes
  }

  static func key(_ method: String, _ path: String) -> String { "\(method) \(path)" }

  func on(_ method: String, _ path: String, _ answers: Answer...) {
    routes[Self.key(method, path), default: []].append(contentsOf: answers)
  }

  /// Replaces the route's queued answers.
  func replace(_ method: String, _ path: String, _ answers: Answer...) {
    routes[Self.key(method, path)] = answers
  }

  func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
    calls.append(request)
    let key = Self.key(request.method, request.url.path())
    guard var queue = routes[key], let answer = queue.first else { throw .noFixture(key) }
    if queue.count > 1 {
      queue.removeFirst()
      routes[key] = queue
    }
    switch answer {
    case .response(let response):
      return response
    case .fixture(let url):
      do {
        return try FixtureEnvelope.load(url)
      } catch {
        throw .noFixture("\(key): \(error)")
      }
    case .failure(let error):
      throw error
    }
  }

  /// The `METHOD path` of every call so far, in order.
  var callOrder: [String] { calls.map { Self.key($0.method, $0.url.path()) } }
}

/// A body as text for assertions; empty when it is not UTF-8.
func utf8Text(_ data: Data) -> String {
  String(bytes: data, encoding: .utf8) ?? ""
}
