import Foundation

/// Why a due job did not run (07 `sched.skip {reason}`).
public enum SkipReason: String, Sendable {
  case paused
  case circuitOpen = "circuit_open"
  case offline
}

/// The table behind 04's minute-cadence loop: one entry per `(account, job)` with its next due instant on the
/// monotonic clock, its period and its failure streak. Pure value logic; `PollCoordinator` runs the loop
/// (tick → dispatch → `clock.sleep(until: next, tolerance: 5 s)`) and owns the side effects.
public struct SchedulerLoop<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration {
  public struct Key: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var accountID: String
    public var job: Job

    public init(accountID: String, job: Job) {
      self.accountID = accountID
      self.job = job
    }

    public static func < (lhs: Key, rhs: Key) -> Bool {
      (lhs.accountID, lhs.job.rawValue) < (rhs.accountID, rhs.job.rawValue)
    }

    public var description: String { "\(accountID)/\(job.rawValue)" }
  }

  public struct Slot: Sendable, Equatable {
    public var nextDue: Instant
    public var interval: Duration
    /// Failed attempts in a row; 04: the next attempt waits `interval × 2ⁿ` (cap 15 min), reset on success.
    public var failures: Int
    /// The reason of the last skip, so a reconnect can run what going offline held back.
    public var skipped: SkipReason?

    public init(nextDue: Instant, interval: Duration, failures: Int = 0, skipped: SkipReason? = nil) {
      self.nextDue = nextDue
      self.interval = interval
      self.failures = failures
      self.skipped = skipped
    }
  }

  /// 04: the sleep tolerance that lets the OS coalesce wakes. Jobs due within it of a wake run in that wake.
  public static var tolerance: Duration { .seconds(5) }

  public var entries: [Key: Slot] = [:]

  public init() {}

  /// The jobs to run at `now`: due within the tolerance, not in flight, earliest first (ties by account and job).
  public func due(at now: Instant, excluding running: Set<Key>) -> [Key] {
    let horizon = now.advanced(by: Self.tolerance)
    return entries.filter { $0.value.nextDue <= horizon && !running.contains($0.key) }
      .sorted { ($0.value.nextDue, $0.key) < ($1.value.nextDue, $1.key) }
      .map(\.key)
  }

  /// The earliest due instant of a job that is not in flight; nil when there is none.
  public func nextDue(excluding running: Set<Key>) -> Instant? {
    entries.filter { !running.contains($0.key) }.map(\.value.nextDue).min()
  }

  /// Adds a job, due at once (04 step 6: first tick immediately), or updates its period. A shorter period pulls
  /// the next run in; a longer one applies from the next run.
  public mutating func upsert(_ key: Key, interval: Duration, at now: Instant) {
    guard var entry = entries[key] else {
      entries[key] = Slot(nextDue: now, interval: interval)
      return
    }
    entry.interval = interval
    entry.nextDue = min(entry.nextDue, now.advanced(by: interval))
    entries[key] = entry
  }

  /// Due at once (resume, unpause, circuit reset, reconnect, `refreshNow`).
  public mutating func runNow(_ key: Key, at now: Instant) {
    entries[key]?.nextDue = now
  }

  /// After a run: success → one period; failure → backoff (04); cancelled (overrun) → the next tick (04).
  public mutating func completed(_ key: Key, outcome: Poller.Outcome, at now: Instant) {
    guard var entry = entries[key] else { return }
    entry.skipped = nil
    switch outcome {
    case .succeeded:
      entry.failures = 0
      entry.nextDue = now.advanced(by: entry.interval)
    case .failed:
      entry.failures += 1
      entry.nextDue = now.advanced(by: RetryPolicy.backoff(interval: entry.interval,
                                                           consecutiveFailures: entry.failures))
    case .skipped("cancelled"):
      entry.nextDue = now
    case .skipped:
      entry.nextDue = now.advanced(by: entry.interval)
    }
    entries[key] = entry
  }

  /// A due job that did not run waits one period (Q-034).
  public mutating func skipped(_ key: Key, reason: SkipReason, at now: Instant) {
    guard var entry = entries[key] else { return }
    entry.skipped = reason
    entry.nextDue = now.advanced(by: entry.interval)
    entries[key] = entry
  }

  /// After a clock jump or a wake (04): every next run is recomputed from `now`, inside `now … now + interval`, so a
  /// job that missed several periods runs once, never once per missed tick.
  public mutating func rebase(at now: Instant) {
    for (key, entry) in entries {
      entries[key]?.nextDue = min(max(entry.nextDue, now), now.advanced(by: entry.interval))
    }
  }
}
