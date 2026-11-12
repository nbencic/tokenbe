import Foundation
import Synchronization

/// Where a running job is (04 § Cancellation; 07 `sched.overrun {phase}`).
public enum PollPhase: String, Sendable {
  case fetch, decode, write
}

/// The phase of one running job, written by `Poller` and the adapter's `ResponseTrace`, read synchronously by
/// `PollCoordinator` when the job overruns.
public final class PollPhaseBox: Sendable {
  private let value = Mutex(PollPhase.fetch)

  public init() {}

  public func set(_ phase: PollPhase) {
    value.withLock { $0 = phase }
  }

  public var current: PollPhase { value.withLock { $0 } }
}

/// One account's poller (04 § Concurrency model): its `account` row, the jobs in flight, and the shared `Poller`
/// that runs them. Invariant I1/V3: at most one in-flight task per `(account, job)`; a second `run` of a job that is
/// still running logs `sched.overlap_skipped` and makes no request.
public actor AccountPoller {
  public nonisolated let accountID: String
  public private(set) var account: AccountRecord
  public private(set) var inFlight: Set<Job> = []
  let runner: Poller
  let log: EventLog

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(account: AccountRecord, runner: Poller, logPipeline: LogPipeline? = nil) {
    accountID = account.id
    self.account = account
    self.runner = runner
    log = EventLog(pipeline: logPipeline)
  }

  /// The row changed (label, paused, override); the next run uses it.
  public func update(_ account: AccountRecord) {
    self.account = account
  }

  public func run(_ job: Job, phase: PollPhaseBox = PollPhaseBox()) async -> Poller.Outcome {
    // I1: checked and claimed before the first suspension, so two concurrent calls cannot both pass.
    guard !inFlight.contains(job) else {
      log.emit(.warn, .schedOverlapSkipped, cat: .sched, msg: "job already in flight", acct: account.provider,
               job: job.rawValue)
      return .skipped("overlap")
    }
    inFlight.insert(job)
    defer { inFlight.remove(job) }
    return await runner.runOnce(account: account, job: job, phase: phase)
  }
}
