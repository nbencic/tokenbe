import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// `AccountRepository` (03 `account`), on the real database and on `MemoryRepository`, which must behave alike.
@Suite struct RepositoryAccountTests {
  enum Kind: String, CaseIterable, CustomTestStringConvertible {
    case grdb, memory
    var testDescription: String { rawValue }
  }

  /// Keeps the temp folder alive as long as the repository.
  struct Subject {
    let repository: any Repository
    let harness: StoreHarness?
    let database: AppDatabase?
  }

  static func make(_ kind: Kind) async throws -> Subject {
    switch kind {
    case .memory:
      return Subject(repository: MemoryRepository(), harness: nil, database: nil)
    case .grdb:
      let harness = try StoreHarness()
      let database = try await harness.open().database
      return Subject(repository: GRDBRepository(database: database), harness: harness, database: database)
    }
  }

  static let openai = FixtureDBBuilder.account()
  static let xai = FixtureDBBuilder.account(id: "acct-xai", provider: "xai", label: "xAI",
                                            createdAt: "2026-01-16T00:00:00.000Z")

  @Test("insert then fetch returns every column, oldest first", arguments: Kind.allCases)
  func insertFetch(_ kind: Kind) async throws {
    let subject = try await Self.make(kind)
    try await subject.repository.insertAccount(Self.xai)
    var openai = Self.openai
    openai.paused = true
    openai.autoReloadEnabled = true
    openai.autoReloadBelowCents = 500
    openai.autoReloadToCents = 2_000
    openai.intervalOverrideJson = #"{"usage":120}"#
    try await subject.repository.insertAccount(openai)
    #expect(try await subject.repository.fetchAccounts() == [openai, Self.xai])
  }

  @Test("a second account for the same provider, or the same id, is a duplicate", arguments: Kind.allCases)
  func duplicates(_ kind: Kind) async throws {
    let subject = try await Self.make(kind)
    try await subject.repository.insertAccount(Self.openai)
    var sameProvider = Self.openai
    sameProvider.id = "another-id"
    await #expect(throws: StoreError.self) { try await subject.repository.insertAccount(sameProvider) }
    var sameID = Self.xai
    sameID.id = Self.openai.id
    await #expect(throws: StoreError.self) { try await subject.repository.insertAccount(sameID) }
    #expect(try await subject.repository.fetchAccounts().count == 1)
  }

  @Test("update changes the row; an unknown id is not found", arguments: Kind.allCases)
  func update(_ kind: Kind) async throws {
    let subject = try await Self.make(kind)
    try await subject.repository.insertAccount(Self.openai)
    var renamed = Self.openai
    renamed.label = "Work"
    renamed.balanceMode = "direct"
    try await subject.repository.updateAccount(renamed)
    #expect(try await subject.repository.fetchAccounts() == [renamed])
    await #expect(throws: StoreError.notFound(Self.xai.id)) { try await subject.repository.updateAccount(Self.xai) }
  }

  @Test("moving an account onto a provider that already has one is a duplicate", arguments: Kind.allCases)
  func updateDuplicate(_ kind: Kind) async throws {
    let subject = try await Self.make(kind)
    try await subject.repository.insertAccount(Self.openai)
    try await subject.repository.insertAccount(Self.xai)
    var clash = Self.xai
    clash.provider = "openai"
    await #expect(throws: StoreError.self) { try await subject.repository.updateAccount(clash) }
  }

  @Test("delete removes the account; an unknown id is not found", arguments: Kind.allCases)
  func delete(_ kind: Kind) async throws {
    let subject = try await Self.make(kind)
    try await subject.repository.insertAccount(Self.openai)
    try await subject.repository.deleteAccount(id: Self.openai.id)
    #expect(try await subject.repository.fetchAccounts().isEmpty)
    await #expect(throws: StoreError.notFound("nope")) { try await subject.repository.deleteAccount(id: "nope") }
  }

  @Test("creating an account seeds its four poll_state rows; deleting it cascades")
  func pollStateSeedAndCascade() async throws {
    let subject = try await Self.make(.grdb)
    let database = try #require(subject.database)
    try await subject.repository.insertAccount(Self.openai)
    let jobs = try await database.read { db in
      try String.fetchAll(db, sql: "SELECT job FROM poll_state WHERE account_id = ? ORDER BY job",
                          arguments: [Self.openai.id])
    }
    #expect(jobs == ["balance", "cost", "keys", "usage"])
    let untouched = try await database.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM poll_state WHERE last_attempt_at IS NULL") ?? 0
    }
    #expect(untouched == 4, "jobs start never attempted (03)")
    try await subject.repository.deleteAccount(id: Self.openai.id)
    #expect(try await database.read { db in try PollStateRecord.fetchCount(db) } == 0)
  }

  @Test("the memory repository seeds and clears poll states the same way")
  func memoryPollStates() async throws {
    let memory = MemoryRepository()
    try await memory.insertAccount(Self.openai)
    #expect(await memory.pollStates[Self.openai.id] == Set(Job.allCases.map(\.rawValue)))
    try await memory.deleteAccount(id: Self.openai.id)
    #expect(await memory.pollStates[Self.openai.id] == nil)
  }

  @Test("03's CHECK constraints reject an unknown provider")
  func checkConstraint() async throws {
    let subject = try await Self.make(.grdb)
    var unknown = Self.openai
    unknown.provider = "gemini"
    await #expect(throws: (any Error).self) { try await subject.repository.insertAccount(unknown) }
  }

  @Test("maintenance calls reach the database", arguments: Kind.allCases)
  func maintenance(_ kind: Kind) async throws {
    let subject = try await Self.make(kind)
    #expect(try await subject.repository.quickCheck().isOK)
    #expect(try await subject.repository.integrityCheck().isOK)
    #expect(try await subject.repository.incrementalVacuum() >= 0)
    _ = try await subject.repository.backup()
  }
}

/// Every record type of `Store/Records` writes and reads its table (14 D5); the rows are the fixture's.
@Suite struct RecordRoundTripTests {
  @Test("each of the 14 record types round-trips through its table")
  func roundTrip() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    try await database.write("rows") { db in try FixtureDBBuilder.representativeRows(db) }
    let counts = try await database.read { db in
      [
        try AccountRecord.fetchAll(db).count, try ProviderKeyRecord.fetchAll(db).count,
        try AppRecord.fetchAll(db).count, try AppBindingRecord.fetchAll(db).count,
        try UsageBucketRecord.fetchAll(db).count, try CostBucketRecord.fetchAll(db).count,
        try BalanceSnapshotRecord.fetchAll(db).count, try HarnessEventRecord.fetchAll(db).count,
        try IngestFileRecord.fetchAll(db).count, try LedgerEventRecord.fetchAll(db).count,
        try PriceSnapshotRecord.fetchAll(db).count, try PriceOverrideRecord.fetchAll(db).count,
        try PollStateRecord.fetchAll(db).count, try BandStateRecord.fetchAll(db).count
      ]
    }
    #expect(counts == [1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4, 1])
    let usage = try await database.read { db in try UsageBucketRecord.fetchOne(db) }
    #expect(usage?.cacheWrite5m == 0)
    #expect(usage?.inputUncached == 1200)
    #expect(usage?.provisional == true)
    let snapshot = try await database.read { db in try PriceSnapshotRecord.fetchOne(db) }
    #expect(snapshot?.json == Data(#"{"models":{}}"#.utf8))
    let kind = try await database.read { db in
      try String.fetchOne(db, sql: "SELECT typeof(is_current) || ':' || is_current FROM price_snapshot")
    }
    #expect(kind == "integer:1", "flags are stored as 0/1 (03)")
  }
}
