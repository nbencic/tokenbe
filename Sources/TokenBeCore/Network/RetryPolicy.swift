import Foundation

/// 04 § Retry policy, as pure functions (14 § Stage 3.1 step 4). The poller (3.4) and scheduler (4.1) apply them.
public enum RetryPolicy {
  /// `transport` and `server`: retries 1–3 wait 2 s, 4 s, 8 s, each ± 25 %.
  public static let transientDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]
  public static let jitter = 0.25
  /// `rateLimited`: one retry after `Retry-After`, capped at 300 s, or 30 s when the header is absent.
  public static let rateLimitDefault = Duration.seconds(30)
  public static let retryAfterCap = Duration.seconds(300)
  /// Between failed attempts: interval × 2ⁿ, capped at 15 min.
  public static let backoffCap = Duration.seconds(15 * 60)

  /// The wait before retry number `attempt` (1-based) within one job attempt, or nil when the attempt has failed.
  /// `auth`, `decode`, `schemaDrift`, `providerRule` and `cancelled` never retry.
  public static func nextDelay(
    attempt: Int, error: PollError, using rng: inout some RandomNumberGenerator
  ) -> Duration? {
    guard attempt >= 1 else { return nil }
    switch error {
    case .transport, .server:
      guard attempt <= transientDelays.count else { return nil }
      let factor = 1 + Double.random(in: -jitter...jitter, using: &rng)
      return transientDelays[attempt - 1] * factor
    case .rateLimited(let retryAfter):
      guard attempt == 1 else { return nil }
      return min(retryAfter ?? rateLimitDefault, retryAfterCap)
    case .auth, .decode, .schemaDrift, .providerRule, .cancelled:
      return nil
    }
  }

  /// The delay before the next attempt after `consecutiveFailures` failed attempts in a row (0 = on schedule).
  public static func backoff(interval: Duration, consecutiveFailures: Int) -> Duration {
    guard consecutiveFailures > 0 else { return interval }
    // Doubling past the cap is pointless; stopping early also keeps the multiplication from overflowing.
    var delay = interval
    for _ in 0..<consecutiveFailures {
      delay *= 2
      if delay >= backoffCap { return backoffCap }
    }
    return delay
  }
}
