import Foundation

/// Runs one adapter job for one account (14 § Stage 3.4 step 6): reads the key, applies 04's retry policy, writes
/// the rows, updates `poll_state` (attempt, success, failure, consecutive failures, circuit, cursor, last_raw) and
/// logs the `poll.*` events of 07. One `Poller` serves every account; each account's `AccountPoller` (4.1) calls
/// `runOnce` when `PollCoordinator` dispatches a job. `acct` in its records is the provider name, like 07's example
/// (Q-029).
public actor Poller {
  /// 04: three consecutive auth failures open the circuit for 24 h.
  public static let circuitThreshold = 3
  public static let circuitDuration: TimeInterval = 24 * 3600
  /// A guard against a page sequence that never ends (Q-029).
  public static let maxPages = 50

  /// How far back each job looks (02: usage "last 48 h", cost "last 7 days").
  public static func lookback(_ job: Job) -> TimeInterval {
    switch job {
    case .usage: 48 * 3600
    case .cost: 7 * 86400
    case .balance, .keys: 0
    }
  }

  public enum Outcome: Sendable, Equatable {
    case succeeded(rows: Int)
    /// `poll_state.last_error_class` of the failure (`PollFailure.errorClass`).
    case failed(String)
    /// Nothing ran, nothing was recorded: the job does not apply to the account, or it was cancelled.
    case skipped(String)
  }

  let store: any PollStore
  let keyStore: any KeyStore
  let registry: ProviderRegistry
  let transport: any HTTPTransport
  let clock: any Clock<Duration>
  let now: @Sendable () -> Date
  let log: EventLog
  var rng: any RandomNumberGenerator & Sendable

  /// `logPipeline` is for tests; the app logs through `Log`. Tests pass a `TestClock` and a seeded generator.
  public init(store: any PollStore, keyStore: any KeyStore, registry: ProviderRegistry, transport: any HTTPTransport,
              clock: any Clock<Duration> = ContinuousClock(),
              rng: any RandomNumberGenerator & Sendable = SystemRandomNumberGenerator(),
              logPipeline: LogPipeline? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
    self.store = store
    self.keyStore = keyStore
    self.registry = registry
    self.transport = transport
    self.clock = clock
    self.rng = rng
    self.log = EventLog(pipeline: logPipeline)
    self.now = now
  }

  /// `phase` is where the job is (`fetch`, `decode`, `write`), read by the coordinator for `sched.overrun` (04).
  public func runOnce(account: AccountRecord, job: Job, phase: PollPhaseBox = PollPhaseBox()) async -> Outcome {
    let acct = account.provider
    let cat = Cat.poll(acct)
    guard let provider = ProviderID(rawValue: acct), let adapter = registry.adapter(for: provider) else {
      return skip("\(acct)_no_adapter", acct: acct, job: job)
    }
    let capabilities: Capabilities
    do {
      capabilities = try Capabilities.decode(json: account.capabilities)
    } catch {
      log.emit(.error, .pollFailed, cat: cat, msg: "account capabilities unreadable", acct: acct, job: job.rawValue,
               err: error, ctx: ["attempts": 0])
      return .failed("capabilities")
    }
    guard job.applies(to: capabilities) else { return skip("\(acct)_no_\(job.rawValue)_api", acct: acct, job: job) }

    let time = now()
    guard let key = await readKey(account, job: job, at: time) else { return .failed("keychain") }
    let redactor = log.redactor
    redactor.register(secret: key)
    defer { redactor.unregister(secret: key) }

    let started = ContinuousClock.now
    log.emit(.info, .pollStart, cat: cat, msg: "\(job.rawValue) poll started", acct: acct, job: job.rawValue)
    let trace = ResponseTrace(phase: phase)
    let context = PollContext(
      accountID: account.id, key: key, cursor: nil,
      window: DateInterval(start: time.addingTimeInterval(-Self.lookback(job)), end: time),
      transport: transport, clock: clock, trace: trace
    )
    var attempts = 0
    var resumedFrom: String?
    do {
      try await store.recordPollAttempt(accountID: account.id, job: job, at: time)
      if job == .usage { resumedFrom = try await store.fetchPollState(accountID: account.id, job: job)?.cursor }
      let (rows, lastRaw) = try await perform(job, adapter: adapter, context: context, cursor: resumedFrom,
                                              attempts: &attempts)
      let before = try await store.recordPollSuccess(accountID: account.id, job: job, at: now(), lastRaw: lastRaw)
      if before?.circuitOpenUntil != nil {
        log.emit(.info, .pollCircuitClose, cat: cat, msg: "circuit closed", acct: acct, job: job.rawValue,
                 ctx: ["until": .null])
      }
      log.emit(.info, .pollOk, cat: cat, msg: "\(job.rawValue) poll ok", acct: acct, job: job.rawValue,
               dur: ContinuousClock.now - started,
               ctx: ["rows": .int(rows), "cursor": resumedFrom.map { .string($0) } ?? .null])
      return .succeeded(rows: rows)
    } catch let error as PollError {
      return await failed(error, Run(account: account, job: job, attempts: attempts, trace: trace, time: time))
    } catch is CancellationError {
      // Stopped by the coordinator (overrun, account removed, quit) while writing: not a failure, nothing recorded.
      return .skipped("cancelled")
    } catch {
      return await storeFailed(error, Run(account: account, job: job, attempts: attempts, trace: trace, time: time))
    }
  }

  // MARK: - Jobs

  /// Runs the job and writes its rows; returns the row count and the redacted body for `last_raw`.
  private func perform(_ job: Job, adapter: any ProviderAdapter, context: PollContext, cursor start: String?,
                       attempts: inout Int) async throws -> (Int, String) {
    let acct = adapter.id.rawValue
    switch job {
    case .keys:
      let page = try await retrying(acct, job, phase: context.trace.phase, attempts: &attempts) { () async throws(PollError) in
        try await adapter.pollKeys(context)
      }
      context.trace.phase.set(.write)
      try await store.upsertProviderKeys(accountID: context.accountID, keys: page.keys, seenAt: context.window.end)
      return (page.keys.count, page.rawBody)
    case .usage:
      // Pages are written one by one with their cursor, so an interrupted sequence resumes where it stopped.
      var cursor = start
      var rows = 0
      for _ in 0..<Self.maxPages {
        var pageContext = context
        pageContext.cursor = cursor
        let page = try await retrying(acct, job, phase: context.trace.phase, attempts: &attempts) { () async throws(PollError) in
          try await adapter.pollUsage(pageContext)
        }
        if let next = page.nextCursor, next == cursor { throw PollError.providerRule("\(acct)_usage_cursor_repeated") }
        context.trace.phase.set(.write)
        try await store.writeUsagePage(UsagePageWrite(
          accountID: context.accountID, rows: page.rows, expected: page.expected, cursor: page.nextCursor,
          lastRaw: page.rawBody
        ))
        rows += page.rows.count
        guard let next = page.nextCursor else { return (rows, page.rawBody) }
        cursor = next
      }
      throw PollError.providerRule("\(acct)_usage_more_than_\(Self.maxPages)_pages")
    case .cost:
      let page = try await retrying(acct, job, phase: context.trace.phase, attempts: &attempts) { () async throws(PollError) in
        try await adapter.pollCost(context)
      }
      context.trace.phase.set(.write)
      try await store.replaceCostDays(accountID: context.accountID, rows: page.rows)
      return (page.rows.count, page.rawBody)
    case .balance:
      // No provider with a balance endpoint exists yet; its stage adds `Repository+Balance` and the write (Q-029).
      throw PollError.providerRule("\(acct)_balance_not_stored")
    }
  }

  /// 04 § Retry policy within one attempt: transport/server ×3 (2/4/8 s ± 25 %), rate limit ×1 (`Retry-After`,
  /// cap 300 s, else 30 s), everything else at once.
  private func retrying<T: Sendable>(_ acct: String, _ job: Job, phase: PollPhaseBox, attempts: inout Int,
                                     _ operation: () async throws(PollError) -> T) async throws(PollError) -> T {
    var tries = 0
    while true {
      tries += 1
      attempts += 1
      phase.set(.fetch)
      do {
        return try await operation()
      } catch {
        if case .rateLimited(let retryAfter) = error {
          log.emit(.warn, .pollRateLimited, cat: .poll(acct), msg: "rate limited", acct: acct, job: job.rawValue,
                   ctx: ["retry_after_s": retryAfter.map { .int(Int($0.components.seconds)) } ?? .null])
        }
        guard let delay = RetryPolicy.nextDelay(attempt: tries, error: error, using: &rng) else { throw error }
        log.emit(.warn, .pollRetry, cat: .poll(acct), msg: "\(job.rawValue) poll retrying", acct: acct,
                 job: job.rawValue, attempt: tries, err: error,
                 ctx: ["delay_ms": .int(LogPipeline.milliseconds(delay))])
        do {
          try await clock.sleep(for: delay)
        } catch {
          throw .cancelled
        }
      }
    }
  }

  // MARK: - Outcomes

  private func readKey(_ account: AccountRecord, job: Job, at time: Date) async -> String? {
    do {
      if let key = try await keyStore.get(account.keychainRef) { return key }
      log.emit(.error, .keychainMissing, cat: .keychain, msg: "no Keychain item for the account",
               acct: account.keychainRef)
    } catch {
      // `KeychainKeyStore` has logged `keychain.read_failed` / `access_denied`.
      log.emit(.error, .pollFailed, cat: .poll(account.provider), msg: "key unavailable", acct: account.provider,
               job: job.rawValue, err: error, ctx: ["attempts": 0])
    }
    await record(PollFailure(errorClass: "keychain", message: "Keychain item missing or unreadable"),
                 account: account, job: job, at: time)
    return nil
  }

  private func skip(_ rule: String, acct: String, job: Job) -> Outcome {
    log.emit(.warn, .pollProviderRule, cat: .poll(acct), msg: "job does not apply", acct: acct, job: job.rawValue,
             ctx: ["rule": .string(rule)])
    return .skipped(rule)
  }

  /// One `runOnce` call, for the failure paths.
  struct Run {
    var account: AccountRecord
    var job: Job
    var attempts: Int
    var trace: ResponseTrace
    var time: Date
  }

  private func failed(_ error: PollError, _ run: Run) async -> Outcome {
    let (account, job, attempts, trace, time) = (run.account, run.job, run.attempts, run.trace, run.time)
    let acct = account.provider
    let cat = Cat.poll(acct)
    let redactor = log.redactor
    var failure = PollFailure(errorClass: error.className, message: RawBody.truncated(redactor.redact(error.summary),
                                                                                       limit: 512))
    switch error {
    case .cancelled:
      return .skipped("cancelled")
    case .auth(let status, _):
      failure.countsTowardCircuit = true
      log.emit(.error, .pollAuthFailed, cat: cat, msg: "key rejected", acct: acct, job: job.rawValue,
               ctx: ["http_status": .int(status)])
    case .decode(let field, let path):
      let body = trace.lastBody.map { RawBody.redacted($0, redactor: redactor) }
      failure.lastRaw = body
      log.emit(.error, .pollSchemaDrift, cat: cat, msg: "response does not match 02", acct: acct, job: job.rawValue,
               ctx: ["missing_keys": .string(field), "path": .string(path),
                     "sample": .string(String((body ?? "").prefix(512)))])
    case .providerRule(let rule):
      log.emit(.warn, .pollProviderRule, cat: cat, msg: "provider rule", acct: acct, job: job.rawValue,
               ctx: ["rule": .string(rule)])
    case .transport, .rateLimited, .server, .schemaDrift:
      break
    }
    let state = await record(failure, account: account, job: job, at: time)
    if failure.countsTowardCircuit, let until = state?.circuitOpenUntil,
       until == DBTime.string(time.addingTimeInterval(Self.circuitDuration)) {
      log.emit(.warn, .pollCircuitOpen, cat: cat, msg: "circuit open", acct: acct, job: job.rawValue,
               ctx: ["until": .string(until)])
    }
    log.emit(.error, .pollFailed, cat: cat, msg: "\(job.rawValue) poll failed", acct: acct, job: job.rawValue,
             err: error, ctx: ["attempts": .int(attempts)])
    return .failed(failure.errorClass)
  }

  private func storeFailed(_ error: any Error, _ run: Run) async -> Outcome {
    let (account, job, attempts, time) = (run.account, run.job, run.attempts, run.time)
    let acct = account.provider
    if case StoreError.writeIncomplete(let expected, let written) = error {
      log.emit(.error, .pollWriteIncomplete, cat: .poll(acct), msg: "usage rows do not add up to the page (V2)",
               acct: acct, job: job.rawValue, ctx: ["expected": .int(Int(expected)), "written": .int(Int(written))])
    }
    await record(PollFailure(errorClass: "store", message: RawBody.truncated(log.redactor.redact("\(error)"), limit: 512)),
                 account: account, job: job, at: time)
    log.emit(.error, .pollFailed, cat: .poll(acct), msg: "\(job.rawValue) poll failed", acct: acct, job: job.rawValue,
             err: error, ctx: ["attempts": .int(attempts)])
    return .failed("store")
  }

  @discardableResult
  private func record(_ failure: PollFailure, account: AccountRecord, job: Job, at time: Date) async -> PollStateRecord? {
    do {
      return try await store.recordPollFailure(
        accountID: account.id, job: job, at: time, failure: failure,
        circuit: CircuitRule(threshold: Self.circuitThreshold, until: time.addingTimeInterval(Self.circuitDuration))
      )
    } catch {
      log.emit(.error, .pollFailed, cat: .poll(account.provider), msg: "poll_state not updated",
               acct: account.provider, job: job.rawValue, err: error, ctx: ["attempts": 0])
      return nil
    }
  }
}

extension PollError {
  /// `poll_state.last_error_class` (Q-029).
  public var className: String {
    switch self {
    case .transport: "transport"
    case .auth: "auth"
    case .rateLimited: "rate_limited"
    case .server: "server"
    case .decode: "decode"
    case .schemaDrift: "schema_drift"
    case .providerRule: "provider_rule"
    case .cancelled: "cancelled"
    }
  }

  /// `poll_state.last_error_message` before redaction.
  var summary: String {
    switch self {
    case .transport(let error): "URLError \(error.code.rawValue)"
    case .auth(let http, let body): "HTTP \(http): \(body)"
    case .rateLimited(let retryAfter): "HTTP 429, Retry-After \(retryAfter.map { "\($0)" } ?? "none")"
    case .server(let http, let body): "HTTP \(http): \(body)"
    case .decode(let field, let path): "missing or invalid \(field) at \(path)"
    case .schemaDrift(let keys): "unknown keys \(keys.joined(separator: ","))"
    case .providerRule(let rule): rule
    case .cancelled: "cancelled"
    }
  }
}
