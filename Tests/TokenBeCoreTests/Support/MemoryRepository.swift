import Foundation
@testable import TokenBeCore

/// `Repository` in memory, for tests of code above the store (14 § Stage 2.1 step 6). Mirrors the constraints of
/// 03 that callers can observe: unique id, one account per provider, not-found on update and delete.
actor MemoryRepository: Repository {
  private var accounts: [AccountRecord] = []
  private(set) var pollStates: [String: Set<String>] = [:]
  private(set) var backups = 0
  private(set) var vacuums = 0
  private var observers: [UUID: AsyncStream<SummaryInputs>.Continuation] = [:]

  func insertAccount(_ account: AccountRecord) async throws {
    if accounts.contains(where: { $0.id == account.id || $0.provider == account.provider }) {
      throw StoreError.duplicate(account.id)
    }
    accounts.append(account)
    pollStates[account.id] = Set(Job.allCases.map(\.rawValue))
    publish()
  }

  func updateAccount(_ account: AccountRecord) async throws {
    guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
      throw StoreError.notFound(account.id)
    }
    if accounts.contains(where: { $0.id != account.id && $0.provider == account.provider }) {
      throw StoreError.duplicate(account.id)
    }
    accounts[index] = account
    publish()
  }

  func deleteAccount(id: String) async throws {
    guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
    accounts.remove(at: index)
    pollStates[id] = nil
    publish()
  }

  func fetchAccounts() async throws -> [AccountRecord] {
    accounts.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
  }

  func backup() async throws -> BackupResult {
    backups += 1
    return BackupResult(url: URL(fileURLWithPath: "/dev/null"), bytes: 0)
  }

  func integrityCheck() async throws -> IntegrityResult { IntegrityResult(result: "ok", corruptCopy: nil) }

  func quickCheck() async throws -> IntegrityResult { IntegrityResult(result: "ok", corruptCopy: nil) }

  func incrementalVacuum() async throws -> Int {
    vacuums += 1
    return 0
  }

  // MARK: - Provider keys, usage, cost, poll (3.4): plain storage for view-model tests, no SQL semantics (11)

  private(set) var providerKeys: [String: [DiscoveredKey]] = [:]
  private(set) var usage: [UsageBucketRecord] = []
  private(set) var costs: [CostBucketRecord] = []
  private var states: [String: PollStateRecord] = [:]

  func upsertProviderKeys(accountID: String, keys: [DiscoveredKey], seenAt: Date) async throws {
    var known = providerKeys[accountID, default: []].filter { old in !keys.contains { $0.providerKeyID == old.providerKeyID } }
    known += keys
    providerKeys[accountID] = known
  }

  func fetchProviderKeys(accountID: String) async throws -> [ProviderKeyRecord] {
    providerKeys[accountID, default: []].map {
      ProviderKeyRecord(accountId: accountID, providerKeyId: $0.providerKeyID, name: $0.name, redacted: $0.redacted,
                        projectId: $0.projectID, workspaceId: $0.workspaceID, status: "active", firstSeenAt: "",
                        lastSeenAt: "")
    }
  }

  func writeUsagePage(_ page: UsagePageWrite) async throws {
    usage += page.rows
    var state = pollState(page.accountID, page.job)
    state.cursor = page.cursor
    states["\(page.accountID)/\(page.job.rawValue)"] = state
  }

  func fetchUsageBuckets(accountID: String) async throws -> [UsageBucketRecord] {
    usage.filter { $0.accountId == accountID }
  }

  func replaceCostDays(accountID: String, rows: [CostBucketRecord]) async throws {
    let days = Set(rows.map(\.day))
    costs.removeAll { $0.accountId == accountID && days.contains($0.day) }
    costs += rows
  }

  func fetchCostBuckets(accountID: String) async throws -> [CostBucketRecord] {
    costs.filter { $0.accountId == accountID }
  }

  func fetchPollState(accountID: String, job: Job) async throws -> PollStateRecord? {
    states["\(accountID)/\(job.rawValue)"]
  }

  func recordPollAttempt(accountID: String, job: Job, at time: Date) async throws {
    var state = pollState(accountID, job)
    state.lastAttemptAt = DBTime.string(time)
    states["\(accountID)/\(job.rawValue)"] = state
  }

  func recordPollSuccess(accountID: String, job: Job, at time: Date, lastRaw: String?) async throws -> PollStateRecord? {
    let before = states["\(accountID)/\(job.rawValue)"]
    var state = pollState(accountID, job)
    state.lastSuccessAt = DBTime.string(time)
    state.consecutiveFailures = 0
    state.circuitOpenUntil = nil
    state.cursor = nil
    states["\(accountID)/\(job.rawValue)"] = state
    return before
  }

  func recordPollFailure(accountID: String, job: Job, at time: Date, failure: PollFailure,
                         circuit: CircuitRule) async throws -> PollStateRecord? {
    var state = pollState(accountID, job)
    state.consecutiveFailures = state.lastErrorClass == failure.errorClass ? state.consecutiveFailures + 1 : 1
    state.lastErrorClass = failure.errorClass
    if failure.countsTowardCircuit && state.consecutiveFailures >= Int64(circuit.threshold) {
      state.circuitOpenUntil = DBTime.string(circuit.until)
    }
    states["\(accountID)/\(job.rawValue)"] = state
    return state
  }

  func resetCircuit(accountID: String) async throws -> [Job] {
    var open: [Job] = []
    for job in Job.allCases {
      var state = pollState(accountID, job)
      if state.circuitOpenUntil != nil { open.append(job) }
      state.circuitOpenUntil = nil
      state.consecutiveFailures = 0
      states["\(accountID)/\(job.rawValue)"] = state
    }
    return open
  }

  private(set) var ledger: [LedgerEventRecord] = []

  func insertLedgerEvent(_ event: LedgerEventRecord) async throws {
    if ledger.contains(where: { $0.id == event.id }) { throw StoreError.duplicate(event.id) }
    ledger.append(event)
  }

  private func pollState(_ accountID: String, _ job: Job) -> PollStateRecord {
    states["\(accountID)/\(job.rawValue)"] ?? PollStateRecord(
      accountId: accountID, job: job.rawValue, lastAttemptAt: nil, lastSuccessAt: nil, lastErrorClass: nil,
      lastErrorMessage: nil, consecutiveFailures: 0, circuitOpenUntil: nil, cursor: nil, lastRaw: nil
    )
  }

  // MARK: - Observation (like `ValueObservation`: the current value first, then one value per change)

  nonisolated func observeSummaryInputs() -> AsyncStream<SummaryInputs> {
    let (stream, continuation) = AsyncStream.makeStream(of: SummaryInputs.self)
    let id = UUID()
    Task { await self.register(id, continuation) }
    continuation.onTermination = { _ in Task { await self.unregister(id) } }
    return stream
  }

  private func register(_ id: UUID, _ continuation: AsyncStream<SummaryInputs>.Continuation) {
    observers[id] = continuation
    continuation.yield(currentInputs)
  }

  private func unregister(_ id: UUID) {
    observers[id] = nil
  }

  private var currentInputs: SummaryInputs {
    SummaryInputs(accounts: accounts.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) })
  }

  private func publish() {
    let inputs = currentInputs
    for continuation in observers.values { continuation.yield(inputs) }
  }
}
