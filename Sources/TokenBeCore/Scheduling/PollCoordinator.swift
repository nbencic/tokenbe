import Foundation

/// Owns every account's `AccountPoller` and the single minute-cadence loop (04 § Concurrency model, § Scheduler).
///
/// Accounts arrive from `sync(_:)` (the store's observation: a new account is polled at once, a removed one is
/// dropped, `account.paused`, overrides and circuits are followed); settings from `update(_:)`. Each wake runs the
/// jobs due within the 5 s tolerance and sleeps until the next deadline: a job's due instant, an in-flight job's
/// overrun limit (2 × interval → cancelled, `sched.overrun`), or the end of the global pause. Any change wakes the
/// loop early. Times are on the injected monotonic clock; `now` (wall time) is for pause ends, circuits and
/// clock-jump detection.
public actor PollCoordinator<C: Clock<Duration>> {
  public typealias Schedule = SchedulerLoop<C.Instant>
  public typealias Key = Schedule.Key

  /// 04: a wall-clock jump larger than this against the monotonic clock is a `sched.clock_jump`.
  public static var clockJumpThreshold: Duration { .seconds(30) }
  /// 04: a job running longer than this many intervals is cancelled.
  public static var overrunFactor: Int { 2 }

  struct AccountState {
    var record: AccountRecord
    var provider: ProviderID
    var capabilities: Capabilities
    var override: IntervalOverride
    var circuits: [Job: Date]
  }

  /// Where and when the previous tick ran, for clock-jump detection (04).
  struct TickMark {
    var wall: Date
    var mono: C.Instant
    var timeZone: String
  }

  struct Running {
    var id: Int
    var task: Task<Void, Never>
    var started: C.Instant
    var phase: PollPhaseBox
    var overrun = false
  }

  let clock: C
  let runner: Poller
  let now: @Sendable () -> Date
  let log: EventLog
  let logPipeline: LogPipeline?

  var settings: ScheduleSettings
  var lowPower: Bool
  var online = true
  var schedule = Schedule()
  var accounts: [String: AccountState] = [:]
  var pollers: [String: AccountPoller] = [:]
  var running: [Key: Running] = [:]
  private var nextRunID = 0
  /// Accounts `stop(_:)` took out; ignored by `sync` until they leave the store (the removal race, Q-034).
  var retired: Set<String> = []
  /// Accounts whose `capabilities` JSON could not be read, logged once each.
  var unreadable: Set<String> = []
  private var loop: Task<Void, Never>?
  private var sleeper: Task<Bool, Never>?
  var followers: [Task<Void, Never>] = []
  private var lastTick: TickMark?
  private var wasPaused = false
  private var lastState: CoordinatorState?

  public nonisolated let states: AsyncStream<CoordinatorState>
  private let stateContinuation: AsyncStream<CoordinatorState>.Continuation

  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(clock: C, runner: Poller, settings: ScheduleSettings = .defaults, lowPower: Bool = false,
              logPipeline: LogPipeline? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
    self.clock = clock
    self.runner = runner
    self.settings = settings
    self.lowPower = lowPower
    self.logPipeline = logPipeline
    self.log = EventLog(pipeline: logPipeline)
    self.now = now
    (states, stateContinuation) = AsyncStream.makeStream(of: CoordinatorState.self, bufferingPolicy: .bufferingNewest(1))
  }

  // MARK: - Lifecycle

  /// Starts the loop (04 startup step 6); the first tick runs at once.
  public func start() {
    guard loop == nil else { return }
    wasPaused = settings.isPaused(at: now())
    emitState()
    loop = Task { await self.runLoop() }
  }

  /// Stops the loop, the followers and every running job (app terminate).
  public func shutdown() {
    loop?.cancel()
    loop = nil
    sleeper?.cancel()
    for follower in followers { follower.cancel() }
    followers = []
    for entry in running.values { entry.task.cancel() }
    stateContinuation.finish()
  }

  /// Feeds `sync` from the store's observation (the same `SummaryInputs` the UI reads).
  public func follow(_ inputs: AsyncStream<SummaryInputs>) {
    followers.append(Task {
      for await next in inputs { self.sync(next) }
    })
  }

  /// Follows reachability: offline jobs are skipped (`sched.skip reason=offline`); a reconnect runs them at once.
  public func follow(_ monitor: any NetworkMonitor) {
    let statuses = monitor.statuses()
    followers.append(Task {
      for await status in statuses { self.setOnline(status.online) }
    })
  }

  // MARK: - Loop

  private func runLoop() async {
    while !Task.isCancelled {
      let deadline = tick()
      await sleep(until: deadline)
    }
  }

  /// One wake of 04's loop: clock check, overruns, then every due job is dispatched or skipped.
  func tick() -> C.Instant {
    let mono = clock.now
    let wall = now()
    detectClockJump(wall: wall, mono: mono)
    cancelOverruns(at: mono)
    let paused = settings.isPaused(at: wall)
    if wasPaused && !paused {
      for key in schedule.entries.keys { schedule.runNow(key, at: mono) }
    }
    wasPaused = paused
    for key in schedule.due(at: mono, excluding: Set(running.keys)) {
      if let reason = skipReason(key, paused: paused, at: wall) {
        log.emit(.info, .schedSkip, cat: .sched, msg: "\(key.job.rawValue) skipped", acct: provider(of: key),
                 job: key.job.rawValue, ctx: ["reason": .string(reason.rawValue)])
        schedule.skipped(key, reason: reason, at: mono)
      } else {
        dispatch(key, at: mono)
      }
    }
    emitState()
    return nextDeadline(at: mono, wall: wall)
  }

  private func nextDeadline(at mono: C.Instant, wall: Date) -> C.Instant {
    var candidates: [C.Instant] = []
    if let due = schedule.nextDue(excluding: Set(running.keys)) { candidates.append(due) }
    for (key, entry) in running where !entry.overrun {
      if let interval = schedule.entries[key]?.interval {
        candidates.append(entry.started.advanced(by: interval * Self.overrunFactor))
      }
    }
    if let until = settings.pausedUntil, until > wall {
      candidates.append(mono.advanced(by: .seconds(until.timeIntervalSince(wall))))
    }
    // Nothing scheduled: sleep until something wakes the loop.
    return candidates.min() ?? mono.advanced(by: .seconds(86_400))
  }

  /// Sleeps until `deadline` or a `wake()`. Returns false when woken early.
  @discardableResult
  private func sleep(until deadline: C.Instant) async -> Bool {
    let clock = clock
    let task = Task {
      do {
        try await clock.sleep(until: deadline, tolerance: Schedule.tolerance)
        return true
      } catch {
        // Cancelled by `wake()` or `shutdown()`: a control signal, not a failure, so there is nothing to log.
        return false
      }
    }
    sleeper = task
    let completed = await task.value
    if sleeper == task { sleeper = nil }
    return completed
  }

  func wake() {
    sleeper?.cancel()
  }

  private func dispatch(_ key: Key, at mono: C.Instant) {
    guard let poller = pollers[key.accountID] else { return }
    let entry = schedule.entries[key]
    log.emit(.debug, .schedTick, cat: .sched, msg: "\(key.job.rawValue) due", acct: provider(of: key),
             job: key.job.rawValue,
             ctx: ["due_in_s": .int(entry.map { Int(mono.duration(to: $0.nextDue).components.seconds) } ?? 0)])
    nextRunID += 1
    let id = nextRunID
    let phase = PollPhaseBox()
    let task = Task {
      let outcome = await poller.run(key.job, phase: phase)
      self.finished(key, id: id, outcome: outcome)
    }
    running[key] = Running(id: id, task: task, started: mono, phase: phase)
  }

  private func finished(_ key: Key, id: Int, outcome: Poller.Outcome) {
    guard running[key]?.id == id else { return }
    running[key] = nil
    schedule.completed(key, outcome: outcome, at: clock.now)
    emitState()
    wake()
  }

  private func cancelOverruns(at mono: C.Instant) {
    for (key, entry) in running where !entry.overrun {
      guard let interval = schedule.entries[key]?.interval else { continue }
      let elapsed = entry.started.duration(to: mono)
      guard elapsed >= interval * Self.overrunFactor else { continue }
      running[key]?.overrun = true
      entry.task.cancel()
      log.emit(.error, .schedOverrun, cat: .sched, msg: "\(key.job.rawValue) overran its interval",
               acct: provider(of: key), job: key.job.rawValue, dur: elapsed,
               ctx: ["phase": .string(entry.phase.current.rawValue)])
    }
  }

  private func detectClockJump(wall: Date, mono: C.Instant) {
    guard let last = lastTick else {
      lastTick = TickMark(wall: wall, mono: mono, timeZone: TimeZone.current.identifier)
      return
    }
    let wallDelta = wall.timeIntervalSince(last.wall)
    let monoDelta = Self.seconds(last.mono.duration(to: mono))
    if abs(wallDelta - monoDelta) > Self.seconds(Self.clockJumpThreshold) {
      clockJumped(wall: wall, mono: mono, reason: "drift")
    } else {
      lastTick = TickMark(wall: wall, mono: mono, timeZone: TimeZone.current.identifier)
    }
  }

  func clockJumped(wall: Date, mono: C.Instant, reason: String) {
    let timeZone = TimeZone.current.identifier
    let last = lastTick
    log.emit(.warn, .schedClockJump, cat: .sched, msg: reason == "wake" ? "system woke" : "wall clock jumped", ctx: [
      "wall_delta_s": .int(Int((last.map { wall.timeIntervalSince($0.wall) } ?? 0).rounded())),
      "mono_delta_s": .int(Int(last.map { Self.seconds($0.mono.duration(to: mono)) } ?? 0)),
      "tz": .bool(last.map { $0.timeZone != timeZone } ?? false),
      "reason": .string(reason)
    ])
    schedule.rebase(at: mono)
    lastTick = TickMark(wall: wall, mono: mono, timeZone: timeZone)
  }

  static func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }

  private func skipReason(_ key: Key, paused: Bool, at wall: Date) -> SkipReason? {
    guard let account = accounts[key.accountID] else { return .paused }
    if paused || account.record.paused { return .paused }
    if let until = account.circuits[key.job], until > wall { return .circuitOpen }
    if !online { return .offline }
    return nil
  }

  func provider(of key: Key) -> String {
    accounts[key.accountID]?.record.provider ?? key.accountID
  }

  func emitState() {
    let wall = now()
    let state = CoordinatorState(pausedUntil: settings.isPaused(at: wall) ? settings.pausedUntil : nil,
                                 inFlightCount: running.count, isOnline: online, isLowPower: lowPower,
                                 nextDue: wallClockDue(at: wall))
    guard state != lastState else { return }
    lastState = state
    stateContinuation.yield(state)
  }

  // MARK: - Test hooks

  var runningKeys: Set<Key> { Set(running.keys) }
  var accountIDs: Set<String> { Set(accounts.keys) }
}
