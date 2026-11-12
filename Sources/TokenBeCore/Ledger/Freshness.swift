import Foundation

/// One job's line in the account page's Sources strip (08 `HP-0`): `Usage · ok · 2 min ago · next 3 min`.
public struct SourceStatus: Sendable, Equatable, Identifiable {
  public enum State: String, Sendable, Equatable {
    /// The last attempt succeeded (`ok`).
    case succeeded
    /// The last attempt failed; `message` is its human message (`poll_state.last_error_message`, Q-036).
    case failed
    /// Applies to the account, never attempted yet (`never`, 08 § Popover states).
    case never
    /// The account's capabilities rule the job out (`n/a`, 08).
    case notApplicable
  }

  public var job: Job
  public var state: State
  public var lastSuccessAt: Date?
  /// When the scheduler runs the job next (wall clock, from `CoordinatorState`); nil for `cost`, which runs in the
  /// daily activity (04), and for jobs the scheduler does not hold.
  public var nextDue: Date?
  public var message: String?

  public var id: Job { job }

  public init(job: Job, state: State, lastSuccessAt: Date? = nil, nextDue: Date? = nil, message: String? = nil) {
    self.job = job
    self.state = state
    self.lastSuccessAt = lastSuccessAt
    self.nextDue = nextDue
    self.message = message
  }

  /// One status per job in `Job.allCases` order, from the account's capabilities and `poll_state` (03).
  /// Unreadable capabilities count as "applies", so a failing job still shows its error.
  public static func all(capabilities: Capabilities?, states: [PollStateSummary]) -> [SourceStatus] {
    let byJob = Dictionary(states.map { ($0.job, $0) }, uniquingKeysWith: { first, _ in first })
    return Job.allCases.map { job in
      guard capabilities.map(job.applies(to:)) ?? true else { return SourceStatus(job: job, state: .notApplicable) }
      let row = byJob[job.rawValue]
      let success = row?.lastSuccessAt.flatMap(DBTime.date)
      if row?.lastErrorClass != nil {
        return SourceStatus(job: job, state: .failed, lastSuccessAt: success, message: row?.lastErrorMessage)
      }
      return SourceStatus(job: job, state: success == nil ? .never : .succeeded, lastSuccessAt: success)
    }
  }
}

/// What staleness depends on besides the stored rows: the 09 settings, Low Power Mode and the scheduler's next runs.
public struct FreshnessContext: Sendable, Equatable {
  public var settings: ScheduleSettings
  /// 09 `tb.alerts.staleMultiplier`.
  public var staleMultiplier: Int
  /// Low Power Mode stretches every interval (04), so it stretches the stale threshold too.
  public var lowPower: Bool
  /// `CoordinatorState.nextDue`: account id → job → next run.
  public var nextDue: [String: [Job: Date]]

  /// `staleMultiplier` nil → 09's default.
  public init(settings: ScheduleSettings = .defaults, staleMultiplier: Int? = nil, lowPower: Bool = false,
              nextDue: [String: [Job: Date]] = [:]) {
    self.settings = settings
    self.staleMultiplier = staleMultiplier ?? SettingsKey.alertsStaleMultiplier.defaultInt
    self.lowPower = lowPower
    self.nextDue = nextDue
  }
}

/// 05 § Bands: stale is an overlay, not a band: `now − last_success_at > stale_multiplier × interval`. An account is
/// stale when its primary job is (14 § Stage 4.2 step 1): `usage` for anchored and spend-only accounts, `balance`
/// for direct ones. A job that never succeeded reads `never`, not stale (Q-036).
public enum Freshness {
  public static func primaryJob(for mode: BalanceMode) -> Job {
    mode == .direct ? .balance : .usage
  }

  /// The instant the data turns stale; nil when it never succeeded or the job has no minute cadence.
  public static func staleAt(lastSuccess: Date?, interval: Duration?, multiplier: Int) -> Date? {
    guard let lastSuccess, let interval else { return nil }
    return lastSuccess.addingTimeInterval(TimeInterval(interval.components.seconds) * TimeInterval(multiplier))
  }

  /// The account's stale instant: its primary job's last success plus the multiple of that job's interval (the
  /// account's override or the 09 setting, × the Low Power multiplier, as the scheduler uses it).
  public static func staleAt(_ summary: AccountSummary, context: FreshnessContext) -> Date? {
    let job = primaryJob(for: summary.mode)
    guard let capabilities = summary.capabilities, job.applies(to: capabilities) else { return nil }
    let interval = job.interval(for: summary.provider, settings: context.settings, override: summary.intervalOverride,
                                lowPower: context.lowPower)
    return staleAt(lastSuccess: summary.freshness[job] ?? nil, interval: interval, multiplier: context.staleMultiplier)
  }

  /// Sets each summary's `isStale` at `now` and its sources' next runs. Returns the next instant at which an
  /// account turns stale, so the caller re-evaluates then (stale must appear with no database write, e.g. offline);
  /// nil when none will.
  @discardableResult
  public static func apply(to summaries: inout [AccountSummary], context: FreshnessContext, now: Date) -> Date? {
    var next: Date?
    for index in summaries.indices {
      let staleAt = staleAt(summaries[index], context: context)
      summaries[index].isStale = staleAt.map { now > $0 } ?? false
      if let staleAt, staleAt >= now { next = min(next ?? staleAt, staleAt) }
      let due = context.nextDue[summaries[index].id] ?? [:]
      for source in summaries[index].sources.indices where summaries[index].sources[source].state != .notApplicable {
        summaries[index].sources[source].nextDue = due[summaries[index].sources[source].job]
      }
    }
    return next
  }
}
