import Foundation
import GRDB
import Testing
@testable import TokenBeCore

/// Collects what a stream yields, so a test can wait for a value without blocking on `next()` forever.
actor StreamRecorder<Value: Sendable> {
  private(set) var values: [Value] = []
  private(set) var finished = false
  private var task: Task<Void, Never>?

  init(_ stream: AsyncStream<Value>) {
    Task { await self.start(stream) }
  }

  private func start(_ stream: AsyncStream<Value>) {
    task = Task { [weak self] in
      for await value in stream { await self?.append(value) }
      await self?.finish()
    }
  }

  private func append(_ value: Value) { values.append(value) }
  private func finish() { finished = true }
  func cancel() { task?.cancel() }
  var last: Value? { values.last }
}

/// 14 § Stage 2.2 Tests: `observeSummaryInputs` yields the current inputs, then again after each change, on the
/// real database (`ValueObservation`) and on `MemoryRepository` alike.
@Suite struct ObservationTests {
  typealias Kind = RepositoryAccountTests.Kind

  @Test("yields the current accounts, then again after insert, update and delete", arguments: Kind.allCases)
  func yieldsOnChange(_ kind: Kind) async throws {
    let subject = try await RepositoryAccountTests.make(kind)
    let repository = subject.repository
    let recorder = StreamRecorder(repository.observeSummaryInputs())
    await eventually("the initial, empty value") { await recorder.last == SummaryInputs(accounts: []) }

    let openai = RepositoryAccountTests.openai
    try await repository.insertAccount(openai)
    await eventually("the inserted account") { await recorder.last?.accounts == [openai] }

    var renamed = openai
    renamed.label = "Work"
    try await repository.updateAccount(renamed)
    await eventually("the renamed account") { await recorder.last?.accounts.first?.label == "Work" }

    let xai = RepositoryAccountTests.xai
    try await repository.insertAccount(xai)
    await eventually("both accounts, oldest first") { await recorder.last?.accounts.map(\.id) == [openai.id, xai.id] }

    try await repository.deleteAccount(id: openai.id)
    await eventually("the delete") { await recorder.last?.accounts == [xai] }
    await recorder.cancel()
    withExtendedLifetime(subject) {}
  }

  @Test("two observers each get every change", arguments: Kind.allCases)
  func twoObservers(_ kind: Kind) async throws {
    let subject = try await RepositoryAccountTests.make(kind)
    let first = StreamRecorder(subject.repository.observeSummaryInputs())
    let second = StreamRecorder(subject.repository.observeSummaryInputs())
    await eventually("both start") {
      let started = (await first.last, await second.last)
      return started.0 != nil && started.1 != nil
    }
    try await subject.repository.insertAccount(RepositoryAccountTests.openai)
    await eventually("first sees the insert") { await first.last?.accounts.count == 1 }
    await eventually("second sees the insert") { await second.last?.accounts.count == 1 }
    await first.cancel()
    await second.cancel()
    withExtendedLifetime(subject) {}
  }

  @Test("a write to another table yields nothing new (duplicates dropped)")
  func duplicatesDropped() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let repository = GRDBRepository(database: database)
    try await repository.insertAccount(RepositoryAccountTests.openai)
    let recorder = StreamRecorder(repository.observeSummaryInputs())
    await eventually("the initial value") { await recorder.last?.accounts.count == 1 }
    try await database.write("test") { db in
      try db.execute(sql: "UPDATE poll_state SET last_attempt_at = '2026-11-10T00:00:00.000Z'")
    }
    try await repository.updateAccount(RepositoryAccountTests.openai)
    try await Task.sleep(for: .milliseconds(200))
    #expect(await recorder.values.count == 1)
    await recorder.cancel()
  }

  @Test("a poll_state success alone yields new inputs with that job's last_success_at (3.5, PM-2.2-3)")
  func pollStateFreshness() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let repository = GRDBRepository(database: database)
    let openai = RepositoryAccountTests.openai
    try await repository.insertAccount(openai)
    let recorder = StreamRecorder(repository.observeSummaryInputs())
    await eventually("four never-polled jobs") {
      await recorder.last?.pollStates.map(\.job) == ["balance", "cost", "keys", "usage"]
    }
    #expect(await recorder.last?.pollStates.allSatisfy { $0.lastSuccessAt == nil } == true)
    try await repository.recordPollSuccess(accountID: openai.id, job: .usage,
                                           at: Date(timeIntervalSince1970: 1_794_312_000), lastRaw: nil)
    await eventually("the usage success") {
      await recorder.last?.pollStates.first { $0.job == "usage" }?.lastSuccessAt == "2026-11-10T12:00:00.000Z"
    }
    #expect(await recorder.last?.accounts == [openai], "the account rows did not change")
    await recorder.cancel()
  }

  @Test("a poll_state failure alone yields new inputs with that job's error class and message (4.2, PM-2.2-3)")
  func pollStateErrors() async throws {
    let harness = try StoreHarness()
    let repository = GRDBRepository(database: try await harness.open().database)
    let openai = RepositoryAccountTests.openai
    try await repository.insertAccount(openai)
    let recorder = StreamRecorder(repository.observeSummaryInputs())
    await eventually("four jobs without errors") {
      await recorder.last.map { $0.pollStates.count == 4 && $0.pollStates.allSatisfy { $0.lastErrorClass == nil } } == true
    }
    let message = CoreStrings.serverError("OpenAI", status: 500)
    _ = try await repository.recordPollFailure(
      accountID: openai.id, job: .usage, at: Date(timeIntervalSince1970: 1_794_312_000),
      failure: PollFailure(errorClass: "server", message: message),
      circuit: CircuitRule(threshold: 3, until: Date(timeIntervalSince1970: 1_794_315_600)))
    await eventually("the usage failure") {
      let usage = await recorder.last?.pollStates.first { $0.job == "usage" }
      return usage?.lastErrorClass == "server" && usage?.lastErrorMessage == message
    }
    let summary = await recorder.last.map { AccountSummaryBuilder.summaries(from: $0)[0] }
    #expect(summary?.sources.first { $0.job == .usage }?.state == .failed)
    #expect(await recorder.last?.accounts == [openai], "the account rows did not change")
    await recorder.cancel()
  }

  @Test("pausing an account yields new inputs whose summary is paused (4.1, PM-3.5-3, PM-2.2-3)")
  func pausedFlows() async throws {
    let harness = try StoreHarness()
    let repository = GRDBRepository(database: try await harness.open().database)
    var openai = RepositoryAccountTests.openai
    try await repository.insertAccount(openai)
    let recorder = StreamRecorder(repository.observeSummaryInputs())
    await eventually("the account") { await recorder.last?.accounts.count == 1 }
    #expect(await recorder.last.map { AccountSummaryBuilder.summaries(from: $0).first?.isPaused } == false)
    openai.paused = true
    try await repository.updateAccount(openai)
    await eventually("the paused summary") {
      await recorder.last.map { AccountSummaryBuilder.summaries(from: $0).first?.isPaused } == true
    }
    await recorder.cancel()
  }

  @Test("a read failure logs ui.error and ends the stream; cancelling logs nothing")
  func failureAndCancel() async throws {
    let harness = try StoreHarness()
    let database = try await harness.open().database
    let repository = GRDBRepository(database: database)

    let cancelled = StreamRecorder(repository.observeSummaryInputs())
    await eventually("the initial value") { await cancelled.last != nil }
    await cancelled.cancel()
    await eventually("the cancelled stream ends") { await cancelled.finished }
    #expect(await harness.records(.uiError).isEmpty)

    try database.close()
    let failing = StreamRecorder(repository.observeSummaryInputs())
    await eventually("the failing stream ends") { await failing.finished }
    #expect(await failing.values.isEmpty)
    let records = await harness.records(.uiError)
    #expect(records.count == 1)
    #expect(records.first?.lvl == .error)
    #expect(records.first?.ctx["view"] == .string("summary"))
    #expect(records.first?.err != nil)
  }
}

/// `AccountSummaryBuilder` (14 § Stage 2.2 step 1): identity fields only, in input order; bad rows are reported.
@Suite struct AccountSummaryBuilderTests {
  @Test("maps id, provider, label, mode, currency and paused (4.1, PM-3.5-3); everything else stays empty")
  func identity() {
    var record = FixtureDBBuilder.account(id: "acct-ds", provider: "deepseek", label: "DeepSeek")
    record.balanceMode = "direct"
    record.currency = "CNY"
    record.paused = true
    var summaries = AccountSummaryBuilder.summaries(from: SummaryInputs(accounts: [record]))
    // 4.2's fields (capabilities, override, sources) are covered by `FreshnessTests.builder`.
    summaries[0].capabilities = nil
    summaries[0].sources = []
    #expect(summaries == [AccountSummary(id: "acct-ds", provider: .deepseek, label: "DeepSeek", mode: .direct,
                                         currency: .cny, isPaused: true)])
  }

  @Test("keeps input order and skips, and reports, a row it cannot read")
  func skipsInvalid() {
    let openai = FixtureDBBuilder.account()
    var bad = FixtureDBBuilder.account(id: "acct-bad", provider: "xai", label: "xAI")
    bad.currency = "EUR"
    var spendOnly = FixtureDBBuilder.account(id: "acct-or", provider: "openrouter", label: "OpenRouter")
    spendOnly.balanceMode = "spend_only"
    var skipped: [(String, AccountSummaryBuilder.InvalidRow)] = []
    let summaries = AccountSummaryBuilder.summaries(from: SummaryInputs(accounts: [openai, bad, spendOnly])) {
      skipped.append(($0.id, $1))
    }
    #expect(summaries.map(\.id) == [openai.id, "acct-or"])
    #expect(summaries.map(\.mode) == [.anchored, .spendOnly])
    #expect(skipped.map(\.0) == ["acct-bad"])
    #expect(skipped.first?.1 == AccountSummaryBuilder.InvalidRow(column: "currency", value: "EUR"))
    #expect(skipped.first?.1.description == "unknown currency 'EUR'")
  }

  @Test("an unknown provider or balance mode is reported by column")
  func unknownColumns() {
    var provider = FixtureDBBuilder.account()
    provider.provider = "acme"
    #expect(AccountSummaryBuilder.summary(for: provider) == .failure(.init(column: "provider", value: "acme")))
    var mode = FixtureDBBuilder.account()
    mode.balanceMode = "prepaid"
    #expect(AccountSummaryBuilder.summary(for: mode) == .failure(.init(column: "balance_mode", value: "prepaid")))
  }
}
