import Foundation
@testable import TokenBeCore

/// One OpenAI account on a temp-file database (11: integration tests use real SQL), with a stub transport, an
/// in-memory key, a `TestClock`, a seeded generator and a capturing log. "Now" is 2026-11-10T12:00:00Z, the
/// moment the synthetic fixtures were written against.
struct OpenAIHarness {
  static let now = Date(timeIntervalSince1970: 1_794_312_000)
  static let account = FixtureDBBuilder.account()

  let store: StoreHarness
  let database: AppDatabase
  let repository: GRDBRepository
  let transport = StubTransport()
  let keys: InMemoryKeyStore
  let clock = TestClock()
  let date = ManualDate(OpenAIHarness.now)
  let adapter: OpenAIAdapter
  let poller: Poller
  /// Built at run time so no key-shaped literal is committed (Q-028).
  let key: String

  init(seed: UInt64 = 7) async throws {
    store = try StoreHarness()
    database = try await store.open().database
    repository = GRDBRepository(database: database)
    try await repository.insertAccount(Self.account)
    key = "sk-" + "admin-" + String(repeating: "Zq7", count: 14)
    keys = InMemoryKeyStore([Self.account.keychainRef: key])
    adapter = OpenAIAdapter(logPipeline: store.pipeline)
    poller = Poller(
      store: repository, keyStore: keys, registry: ProviderRegistry(adapters: [adapter]), transport: transport,
      clock: clock, rng: SeededRNG(seed: seed), logPipeline: store.pipeline, now: date.provider
    )
  }

  static func fixture(_ name: String) -> URL {
    let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
    return root.appendingPathComponent("Fixtures/providers/openai/\(name).synthetic.json")
  }

  static let projects = "/v1/organization/projects"
  static let apiKeys = "/v1/organization/projects/proj_fixture/api_keys"
  static let usage = "/v1/organization/usage/completions"
  static let costs = "/v1/organization/costs"

  func on(_ path: String, _ fixtures: String...) async {
    for name in fixtures { await transport.on("GET", path, .fixture(Self.fixture(name))) }
  }

  func on(_ path: String, _ answers: StubTransport.Answer...) async {
    for answer in answers { await transport.on("GET", path, answer) }
  }

  func run(_ job: Job) async -> Poller.Outcome {
    await poller.runOnce(account: Self.account, job: job)
  }

  func state(_ job: Job) async throws -> PollStateRecord {
    guard let state = try await repository.fetchPollState(accountID: Self.account.id, job: job) else {
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

  /// A failing HTTP answer with `body` as the provider's text.
  static func status(_ status: Int, _ body: String = "x", headers: [String: String] = [:]) -> StubTransport.Answer {
    .response(HTTPResponse(status: status, headers: headers, body: Data(body.utf8)))
  }

  static func ok(_ json: String) -> StubTransport.Answer {
    .response(HTTPResponse(status: 200, body: Data(json.utf8)))
  }
}
