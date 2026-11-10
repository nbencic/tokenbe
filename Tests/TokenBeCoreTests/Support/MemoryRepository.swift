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
