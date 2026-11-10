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

  /// True in a DEBUG build whose main bundle is not an `.app`: `swift test` runs inside a tool
  /// (`swiftpm-testing-helper` or `xctest`), never inside `TokenBe.app`. The runner is not detected by name or by
  /// XCTest being loaded: CI's Swift Testing runner does not load XCTest, and a guard that keyed on it let two
  /// requests reach the network there (PM-3.4-9). The DEBUG app, under UI tests too, keeps the network.
  /// Release builds never block.
  static let isActive: Bool = {
    #if DEBUG
    return isTestProcess(mainBundle: Bundle.main.bundleURL)
    #else
    return false
    #endif
  }()

  static func isTestProcess(mainBundle: URL) -> Bool {
    mainBundle.pathExtension != "app"
  }

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
