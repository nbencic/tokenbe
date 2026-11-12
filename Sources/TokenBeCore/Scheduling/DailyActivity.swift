import Foundation

/// One step of the daily activity (04 § Daily activity). `run` gets the run's number (1 for the first run ever).
public struct DailyStep: Sendable {
  /// When a step runs.
  public enum Gate: Sendable, Equatable {
    case everyRun
    /// Every `n`th run (04: the full `integrity_check` every 7th run, counted by `tb.daily.runCount`).
    case everyNthRun(Int)
  }

  public let name: String
  public let gate: Gate
  public let run: @Sendable (_ runNumber: Int) async throws -> Void

  public init(_ name: String, gate: Gate = .everyRun, run: @escaping @Sendable (_ runNumber: Int) async throws -> Void) {
    self.name = name
    self.gate = gate
    self.run = run
  }
}

/// The daily activity's runner (04 § Daily activity, 14 § Stage 4.3): an ordered registry of steps, run in order.
/// A step that throws is logged (`sched.daily_step_failed`) and the remaining steps still run; it is retried at the
/// next activity, a gated step included (a weekly check that failed runs again the next day). Every run is wrapped in
/// `sched.daily_start` / `sched.daily_end {dur_ms, steps_ok, steps_failed}`, with each step's duration in the end
/// record's ctx (`<step>_ms`). `NSBackgroundActivityScheduler` (the app) and `Run daily tasks now` call `run`.
public actor DailyActivity {
  /// What one run did.
  public struct Summary: Sendable, Equatable {
    public var runNumber: Int
    public var ran: [String]
    public var failed: [String]
    /// Gated steps that were not due.
    public var skipped: [String]
  }

  public private(set) var steps: [DailyStep]
  /// Gated steps whose last run failed; they run at the next activity whatever their gate (04: "retried at the next
  /// activity"). Kept in memory: a relaunch falls back to the gate.
  private var retry: Set<String> = []
  private var running = false
  let log: EventLog
  /// Durations are only logged, so the run measures on the monotonic clock.
  let clock = ContinuousClock()

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(steps: [DailyStep] = [], logPipeline: LogPipeline? = nil) {
    self.steps = steps
    self.log = EventLog(pipeline: logPipeline)
  }

  /// Adds a step at the end of the registry (14 § Stage 4.3 step 2: later stages insert themselves at their 04
  /// position by registering in order).
  public func register(_ step: DailyStep) {
    steps.append(step)
  }

  public var stepNames: [String] { steps.map(\.name) }

  /// Runs every due step in order as run `runNumber`. Nil when a run is already in progress: the second request is
  /// skipped (`sched.overlap_skipped {job: daily}`), so `Run daily tasks now` never doubles a scheduled run.
  @discardableResult
  public func run(runNumber: Int) async -> Summary? {
    guard !running else {
      log.emit(.warn, .schedOverlapSkipped, cat: .sched, msg: "daily activity already running", job: "daily")
      return nil
    }
    running = true
    defer { running = false }
    log.emit(.info, .schedDailyStart, cat: .sched, msg: "daily activity started", ctx: ["run": .int(runNumber)])
    let start = clock.now
    var summary = Summary(runNumber: runNumber, ran: [], failed: [], skipped: [])
    var ctx: [String: LogValue] = [:]
    for step in steps {
      guard isDue(step, runNumber: runNumber) else {
        summary.skipped.append(step.name)
        continue
      }
      let stepStart = clock.now
      do {
        try await step.run(runNumber)
        summary.ran.append(step.name)
        retry.remove(step.name)
      } catch {
        summary.failed.append(step.name)
        if step.gate != .everyRun { retry.insert(step.name) }
        log.emit(.error, .schedDailyStepFailed, cat: .sched, msg: "daily step failed", err: error,
                 ctx: ["step": .string(step.name)])
      }
      ctx[Self.durationKey(step.name)] = .int(Self.milliseconds(stepStart.duration(to: clock.now)))
    }
    ctx["steps_ok"] = .int(summary.ran.count)
    ctx["steps_failed"] = .int(summary.failed.count)
    ctx["run"] = .int(runNumber)
    log.emit(summary.failed.isEmpty ? .info : .warn, .schedDailyEnd, cat: .sched, msg: "daily activity finished",
             dur: start.duration(to: clock.now), ctx: ctx)
    return summary
  }

  func isDue(_ step: DailyStep, runNumber: Int) -> Bool {
    switch step.gate {
    case .everyRun: true
    case .everyNthRun(let period): runNumber % max(period, 1) == 0 || retry.contains(step.name)
    }
  }

  /// `cost polls` → `cost_polls_ms`.
  static func durationKey(_ name: String) -> String {
    name.replacingOccurrences(of: " ", with: "_") + "_ms"
  }

  static func milliseconds(_ duration: Duration) -> Int {
    let parts = duration.components
    return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
  }
}

/// The `cost polls` step (04: first in the daily activity; 14 § Stage 4.3 step 2): every account whose capabilities
/// include `cost` runs its cost job once. Paused accounts, the global pause and an open circuit are skipped as the
/// scheduler skips them (`sched.skip {reason}`). The step throws `Failed` when any account's poll failed, so the run
/// counts it and the next activity retries it.
public struct CostPolls: Sendable {
  public struct Failed: Error, Sendable, Equatable, CustomStringConvertible {
    public let providers: [String]
    public var description: String { "cost poll failed for \(providers.joined(separator: ", "))" }
  }

  let store: any AccountRepository & PollRepository
  let poller: Poller
  let isPaused: @Sendable () async -> Bool
  let now: @Sendable () -> Date
  let log: EventLog

  public init(store: any AccountRepository & PollRepository, poller: Poller,
              isPaused: @escaping @Sendable () async -> Bool, logPipeline: LogPipeline? = nil,
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.store = store
    self.poller = poller
    self.isPaused = isPaused
    self.log = EventLog(pipeline: logPipeline)
    self.now = now
  }

  public func run() async throws {
    let paused = await isPaused()
    var failed: [String] = []
    for account in try await store.fetchAccounts() {
      guard let capabilities = Result(catching: { try Capabilities.decode(json: account.capabilities) }).success,
            capabilities.cost else { continue }
      if let reason = try await skipReason(account, paused: paused) {
        log.emit(.info, .schedSkip, cat: .sched, msg: "cost skipped", acct: account.provider, job: Job.cost.rawValue,
                 ctx: ["reason": .string(reason.rawValue)])
        continue
      }
      if case .failed = await poller.runOnce(account: account, job: .cost) { failed.append(account.provider) }
    }
    if !failed.isEmpty { throw Failed(providers: failed) }
  }

  func skipReason(_ account: AccountRecord, paused: Bool) async throws -> SkipReason? {
    if paused || account.paused { return .paused }
    let state = try await store.fetchPollState(accountID: account.id, job: .cost)
    if let until = state?.circuitOpenUntil.flatMap(DBTime.date), until > now() { return .circuitOpen }
    return nil
  }
}
