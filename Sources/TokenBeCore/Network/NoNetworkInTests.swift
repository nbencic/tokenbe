import Foundation
import Synchronization

/// The suite-wide guard of 11 ("the network is never touched in `swift test`") and R13 (PM-3.1-1). In a test
/// process, a `URLSessionTransport` built without a stub protocol gets this protocol instead of the system's HTTP
/// stack: every request fails at once with `notConnectedToInternet` and is counted in `blocked`, and nothing
/// reaches DNS. Tests that need a response inject `protocolClasses` (`URLSessionTransportTests`) or use
/// `StubTransport`/`FixtureTransport`. Release builds never detect a test process.
final class NoNetworkInTests: URLProtocol {
  private static let count = Atomic<Int>(0)

  /// Requests refused so far in this process.
  static var blocked: Int { count.load(ordering: .relaxed) }

  /// True in a DEBUG build running under XCTest or Swift Testing (both load XCTest on macOS); never in the app.
  static let isActive: Bool = {
    #if DEBUG
    return NSClassFromString("XCTestCase") != nil
    #else
    return false
    #endif
  }()

  override static func canInit(with request: URLRequest) -> Bool { true }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.count.add(1, ordering: .relaxed)
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet, userInfo: [
      NSLocalizedDescriptionKey: "Real network requests are blocked in tests (11)."
    ]))
  }

  override func stopLoading() {}
}
