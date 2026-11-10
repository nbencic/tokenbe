/// Every database read and write of TokenBe goes through `Repository` (04 I2; all SQL lives in `TokenBeCore/Store`).
///
/// The V1 method list is fixed in 14 § Stage 2.1 step 5. Swift protocol extensions cannot add requirements, so
/// "an extension per aggregate" is one protocol per aggregate, composed into `Repository`. Each aggregate is added
/// in the stage that implements it, never as a stub (Q-024):
///
/// | Aggregate | Methods | Stage |
/// |---|---|---|
/// | accounts | `insertAccount, updateAccount, deleteAccount, fetchAccounts` | 2.1 |
/// | maintenance | `backup, integrityCheck, quickCheck, incrementalVacuum` | 2.1 |
/// | maintenance | `rollup, purgeHarnessEvents, thinBalanceSnapshots, exportJSON, importJSON, exportCSV, stats` | with their features |
/// | observation | `observeSummaryInputs` (in `Observation.swift`) | 2.2 |
/// | providerKeys, usage, cost, poll | `Repository+ProviderKeys/Usage/Cost/Poll.swift` | 3.4 |
/// | balance, ledger, prices, band, apps, ingest | see 14 § Stage 2.1 | with their features |
public typealias Repository = AccountRepository & MaintenanceRepository & ObservationRepository
  & ProviderKeyRepository & UsageRepository & CostRepository & PollRepository

/// What `Poller` writes (14 § Stage 3.4 step 6).
public typealias PollStore = ProviderKeyRepository & UsageRepository & CostRepository & PollRepository

/// `account` rows (03). Creating an account also seeds its four `poll_state` rows in the same transaction (03).
public protocol AccountRepository: Sendable {
  /// Throws `StoreError.duplicate` when the id or the provider already has an account (03 `UNIQUE (provider)`).
  func insertAccount(_ account: AccountRecord) async throws
  /// Throws `StoreError.notFound` when no account has that id.
  func updateAccount(_ account: AccountRecord) async throws
  /// Deletes the account and, by cascade, every row that belongs to it. Throws `StoreError.notFound`.
  func deleteAccount(id: String) async throws
  /// Oldest first.
  func fetchAccounts() async throws -> [AccountRecord]
}

/// Database upkeep (03 § Durability). Each call logs its `db.*` event.
public protocol MaintenanceRepository: Sendable {
  func backup() async throws -> BackupResult
  func integrityCheck() async throws -> IntegrityResult
  func quickCheck() async throws -> IntegrityResult
  /// Returns the pages freed.
  func incrementalVacuum() async throws -> Int
}
