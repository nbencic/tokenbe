import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.1 step 4 / 04 § Retry policy: a table of attempt × error → delay, jitter bounds, caps, backoff.
@Suite struct RetryPolicyTests {
  static let transient: [PollError] = [.transport(URLError(.timedOut)), .server(http: 503, body: "")]

  @Test("transport and server: 2 s, 4 s, 8 s ± 25 %, then give up")
  func transientRetries() {
    for error in Self.transient {
      for seed in UInt64(0)..<200 {
        var rng = SeededRNG(seed: seed)
        for (index, base) in [2.0, 4.0, 8.0].enumerated() {
          let delay = RetryPolicy.nextDelay(attempt: index + 1, error: error, using: &rng)
          let seconds = delay.map(Self.seconds) ?? -1
          #expect(seconds >= base * 0.75 && seconds <= base * 1.25, "\(error) attempt \(index + 1): \(seconds) s")
        }
        #expect(RetryPolicy.nextDelay(attempt: 4, error: error, using: &rng) == nil)
      }
    }
  }

  @Test("jitter spreads across the band and is reproducible with the same seed")
  func jitter() {
    var low = Double.infinity
    var high = -Double.infinity
    for seed in UInt64(0)..<500 {
      var rng = SeededRNG(seed: seed)
      let seconds = Self.seconds(RetryPolicy.nextDelay(attempt: 1, error: Self.transient[0], using: &rng) ?? .zero)
      low = min(low, seconds)
      high = max(high, seconds)
    }
    #expect(low < 1.55 && high > 2.45, "observed \(low)…\(high) s")
    var first = SeededRNG(seed: 42)
    var second = SeededRNG(seed: 42)
    #expect(RetryPolicy.nextDelay(attempt: 2, error: Self.transient[1], using: &first)
            == RetryPolicy.nextDelay(attempt: 2, error: Self.transient[1], using: &second))
  }

  @Test("429: Retry-After, capped at 300 s, else 30 s; exactly one retry")
  func rateLimited() {
    var rng = SeededRNG(seed: 1)
    let table: [(Duration?, Duration)] = [
      (.seconds(12), .seconds(12)), (.zero, .zero), (.seconds(300), .seconds(300)), (.seconds(301), .seconds(300)),
      (.seconds(86_400), .seconds(300)), (nil, .seconds(30))
    ]
    for (retryAfter, expected) in table {
      #expect(RetryPolicy.nextDelay(attempt: 1, error: .rateLimited(retryAfter: retryAfter), using: &rng) == expected)
      #expect(RetryPolicy.nextDelay(attempt: 2, error: .rateLimited(retryAfter: retryAfter), using: &rng) == nil)
    }
  }

  @Test("auth, decode, schema drift, provider rule and cancellation never retry")
  func noRetry() {
    var rng = SeededRNG(seed: 7)
    let errors: [PollError] = [
      .auth(http: 401, body: ""), .auth(http: 403, body: ""), .decode(field: "data", path: "$.data"),
      .schemaDrift(unknownKeys: ["x"]), .providerRule("http 404"), .cancelled
    ]
    for error in errors {
      #expect(RetryPolicy.nextDelay(attempt: 1, error: error, using: &rng) == nil, "\(error)")
    }
    #expect(RetryPolicy.nextDelay(attempt: 0, error: Self.transient[0], using: &rng) == nil)
  }

  @Test("backoff between failed attempts: interval × 2ⁿ, capped at 15 min")
  func backoff() {
    let interval = Duration.seconds(60)
    let expected: [(Int, Duration)] = [
      (0, .seconds(60)), (1, .seconds(120)), (2, .seconds(240)), (3, .seconds(480)), (4, .seconds(900)),
      (5, .seconds(900)), (1_000, .seconds(900))
    ]
    for (failures, delay) in expected {
      #expect(RetryPolicy.backoff(interval: interval, consecutiveFailures: failures) == delay, "n = \(failures)")
    }
    #expect(RetryPolicy.backoff(interval: .seconds(300), consecutiveFailures: 1) == .seconds(600))
    #expect(RetryPolicy.backoff(interval: .seconds(300), consecutiveFailures: 2) == .seconds(900))
    #expect(RetryPolicy.backoff(interval: .seconds(3600), consecutiveFailures: 1) == .seconds(900),
            "an interval already above the cap backs off to the cap")
  }

  static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
