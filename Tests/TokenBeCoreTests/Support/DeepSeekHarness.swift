import Foundation
@testable import TokenBeCore

/// One DeepSeek account (direct, USD by default) on a temp-file database, with a stub transport, an in-memory key,
/// a `TestClock` and a capturing log. "Now" is the same instant as `OpenAIHarness.now`.
struct DeepSeekHarness {
  static let now = OpenAIHarness.now
  static let fetchedAt = "2026-11-10T12:00:00.000Z"
  static let balancePath = "/user/balance"

  static let accountID = "0190f0a0-0000-7000-8000-0000000000d5"

  static func account(currency: String = "USD") throws -> AccountRecord {
    var record = FixtureDBBuilder.account(id: accountID, provider: "deepseek", label: "DeepSeek")
    record.keychainRef = "deepseek"
    record.balanceMode = "direct"
    record.currency = currency
    record.capabilities = try DeepSeekAdapter.capabilities.json()
    record.orgId = nil
    record.orgName = nil
    return record
  }

  let store: StoreHarness
  let repository: GRDBRepository
  let transport = StubTransport()
  let keys: InMemoryKeyStore
  let clock = TestClock()
  let date = ManualDate(DeepSeekHarness.now)
  let adapter: DeepSeekAdapter
  let poller: Poller
  let account: AccountRecord
  /// Built at run time so no key-shaped literal is committed (Q-028).
  let key: String

  init(currency: String = "USD") async throws {
    store = try StoreHarness()
    repository = GRDBRepository(database: try await store.open().database)
    account = try Self.account(currency: currency)
    try await repository.insertAccount(account)
    key = "sk-" + String(repeating: "d5e7", count: 8)
    keys = InMemoryKeyStore([account.keychainRef: key])
    adapter = DeepSeekAdapter(logPipeline: store.pipeline)
    poller = Poller(
      store: repository, keyStore: keys, registry: ProviderRegistry(adapters: [adapter]), transport: transport,
      clock: clock, rng: SeededRNG(seed: 3), logPipeline: store.pipeline, now: date.provider
    )
  }

  static func fixture(_ name: String) -> URL {
    let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
    return root.appendingPathComponent("Fixtures/providers/deepseek/balance.\(name).synthetic.json")
  }

  func on(_ fixtures: String...) async {
    for name in fixtures { await transport.on("GET", Self.balancePath, .fixture(Self.fixture(name))) }
  }

  func on(_ answers: StubTransport.Answer...) async {
    for answer in answers { await transport.on("GET", Self.balancePath, answer) }
  }

  func run(_ job: Job = .balance) async -> Poller.Outcome {
    await poller.runOnce(account: account, job: job)
  }

  func snapshots() async throws -> [BalanceSnapshotRecord] {
    try await repository.fetchBalanceSnapshots(accountID: account.id)
  }

  func state(_ job: Job = .balance) async throws -> PollStateRecord {
    guard let state = try await repository.fetchPollState(accountID: account.id, job: job) else {
      throw StoreError.notFound("poll_state \(job)")
    }
    return state
  }

  func records(_ evt: Evt) async -> [LogRecord] {
    await store.records(evt)
  }

  func allLines() async -> String {
    await store.pipeline.drain()
    return await store.sink.lines().joined(separator: "\n")
  }

  /// The first value of the summary observation, mapped like the app maps it.
  func summaries(now: Date = DeepSeekHarness.now) async throws -> [AccountSummary] {
    for await inputs in repository.observeSummaryInputs() {
      return AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: now))
    }
    throw StoreError.notFound("summary inputs")
  }

  static func snapshot(_ currency: String, _ cents: Int64, granted: Int64?, toppedUp: Int64?, available: Bool,
                       accountID: String = DeepSeekHarness.accountID, ts: String = fetchedAt)
    -> BalanceSnapshotRecord {
    BalanceSnapshotRecord(accountId: accountID, ts: ts, currency: currency, amountCents: cents, grantedCents: granted,
                          toppedUpCents: toppedUp, isAvailable: available)
  }
}
