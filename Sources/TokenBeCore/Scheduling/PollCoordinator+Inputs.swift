import Foundation

/// What the popover shows about scheduling (14 § Stage 4.1 step 5).
public struct CoordinatorState: Sendable, Equatable {
  /// The end of the global pause (`tb.poll.pausedUntil`), while it lasts.
  public var pausedUntil: Date?
  /// Jobs running now; the refresh button spins while this is above 0 (08).
  public var inFlightCount: Int
  public var isOnline: Bool

  public init(pausedUntil: Date? = nil, inFlightCount: Int = 0, isOnline: Bool = true) {
    self.pausedUntil = pausedUntil
    self.inFlightCount = inFlightCount
    self.isOnline = isOnline
  }

  public var isPaused: Bool { pausedUntil != nil }
}

/// What comes into the coordinator: stored accounts (`sync`), settings, Low Power, reachability, wake, the refresh
/// button and account removal. Each input changes the schedule and wakes the loop.
extension PollCoordinator {
  /// The accounts and their poll states, as stored.
  public func sync(_ inputs: SummaryInputs) {
    let ids = Set(inputs.accounts.map(\.id))
    retired.formIntersection(ids)
    for id in accounts.keys where !ids.contains(id) { drop(id) }
    let circuits = Dictionary(grouping: inputs.pollStates, by: \.accountId)
    let mono = clock.now
    for record in inputs.accounts where !retired.contains(record.id) {
      upsert(record, states: circuits[record.id] ?? [], at: mono)
    }
    wake()
  }

  /// 09 § Sources changed (intervals, multiplier, global pause).
  public func update(_ settings: ScheduleSettings) {
    guard settings != self.settings else { return }
    self.settings = settings
    refreshIntervals()
    wake()
  }

  /// `NSProcessInfoPowerStateDidChange` (04 § Low Power Mode): intervals × `tb.poll.lowPowerMultiplier`.
  public func setLowPower(_ enabled: Bool) {
    guard enabled != lowPower else { return }
    lowPower = enabled
    log.emit(.info, .schedLowPower, cat: .sched, msg: enabled ? "low power mode on" : "low power mode off",
             ctx: ["enabled": .bool(enabled)])
    refreshIntervals()
    wake()
  }

  public func setOnline(_ isOnline: Bool) {
    guard isOnline != online else { return }
    online = isOnline
    if isOnline {
      let mono = clock.now
      for (key, entry) in schedule.entries where entry.skipped == .offline { schedule.runNow(key, at: mono) }
    }
    emitState()
    wake()
  }

  /// `NSWorkspace.didWakeNotification` (04): logged as a clock jump; next runs recomputed from now.
  public func systemDidWake() {
    let mono = clock.now
    let wall = now()
    clockJumped(wall: wall, mono: mono, reason: "wake")
    wake()
  }

  /// The popover's refresh button and `Refresh` (08): every job of `accountID` (or of all accounts) runs at the
  /// next wake. Skip rules still apply, so an open circuit stays closed until the key is re-tested (04). A job still
  /// in flight is not started twice (I1: `sched.overlap_skipped`).
  public func refreshNow(_ accountID: String? = nil) {
    let mono = clock.now
    for key in schedule.entries.keys.sorted() where accountID == nil || key.accountID == accountID {
      if running[key] != nil {
        log.emit(.warn, .schedOverlapSkipped, cat: .sched, msg: "job already in flight", acct: provider(of: key),
                 job: key.job.rawValue)
      } else {
        schedule.runNow(key, at: mono)
      }
    }
    wake()
  }

  /// Takes an account out before it is removed (`Remove account…`): its running jobs are cancelled and awaited,
  /// so no poll reads a key that is about to be deleted.
  public func stop(_ accountID: String) async {
    retired.insert(accountID)
    let tasks = running.filter { $0.key.accountID == accountID }.map(\.value.task)
    drop(accountID)
    for task in tasks { await task.value }
  }

  // MARK: - Accounts

  func upsert(_ record: AccountRecord, states: [PollStateSummary], at mono: C.Instant) {
    guard let provider = ProviderID(rawValue: record.provider) else { return }
    let capabilities: Capabilities
    do {
      capabilities = try Capabilities.decode(json: record.capabilities)
    } catch {
      if unreadable.insert(record.id).inserted {
        log.emit(.error, .pollFailed, cat: .poll(record.provider), msg: "account capabilities unreadable",
                 acct: record.provider, err: error, ctx: ["attempts": 0])
      }
      return
    }
    let previous = accounts[record.id]
    let override = parseOverride(record, previous: previous, provider: provider)
    var circuits: [Job: Date] = [:]
    for state in states {
      if let job = Job(rawValue: state.job), let until = state.circuitOpenUntil.flatMap(DBTime.date) {
        circuits[job] = until
      }
    }
    accounts[record.id] = AccountState(record: record, provider: provider, capabilities: capabilities,
                                       override: override, circuits: circuits)
    if let poller = pollers[record.id] {
      Task { await poller.update(record) }
    } else {
      pollers[record.id] = AccountPoller(account: record, runner: runner, logPipeline: logPipeline)
    }
    for job in Job.minuteCadence {
      let key = Key(accountID: record.id, job: job)
      guard job.applies(to: capabilities),
            let interval = job.interval(for: provider, settings: settings, override: override, lowPower: lowPower) else {
        schedule.entries[key] = nil
        continue
      }
      schedule.upsert(key, interval: interval, at: mono)
      let unpaused = previous?.record.paused == true && !record.paused
      let reset = previous?.circuits[job] != nil && circuits[job] == nil
      if unpaused || reset { schedule.runNow(key, at: mono) }
    }
  }

  /// 09: a stored override out of range is clamped and logged (`app.settings_changed clamped=true`), once per
  /// stored value.
  func parseOverride(_ record: AccountRecord, previous: AccountState?, provider: ProviderID)
    -> IntervalOverride {
    let parsed = IntervalOverride.parse(record.intervalOverrideJson, provider: provider)
    if parsed.repaired && previous?.record.intervalOverrideJson != record.intervalOverrideJson {
      log.emit(.info, .appSettingsChanged, cat: .app, msg: "interval override repaired", acct: record.provider, ctx: [
        "key": "account.interval_override_json", "old": record.intervalOverrideJson.map { .string($0) } ?? .null,
        "new": parsed.override.json().map { .string($0) } ?? .null, "clamped": true, "source": "system"
      ])
    }
    return parsed.override
  }

  func drop(_ accountID: String) {
    accounts[accountID] = nil
    pollers[accountID] = nil
    for key in schedule.entries.keys where key.accountID == accountID { schedule.entries[key] = nil }
    for (key, entry) in running where key.accountID == accountID {
      entry.task.cancel()
      running[key] = nil
    }
    unreadable.remove(accountID)
    emitState()
  }

  func refreshIntervals() {
    let mono = clock.now
    for (key, _) in schedule.entries {
      guard let account = accounts[key.accountID],
            let interval = key.job.interval(for: account.provider, settings: settings, override: account.override,
                                            lowPower: lowPower) else { continue }
      schedule.upsert(key, interval: interval, at: mono)
    }
  }

}

extension PollCoordinator {
  /// Follows 09 § Sources: every change of an interval, the multiplier or the global pause reaches the coordinator.
  @MainActor
  public func follow(_ settings: Settings) -> Task<Void, Never> {
    let changes = settings.changes
    return Task { @MainActor in
      for await key in changes where ScheduleSettings.keys.contains(key) {
        await self.update(ScheduleSettings(settings))
      }
    }
  }
}
