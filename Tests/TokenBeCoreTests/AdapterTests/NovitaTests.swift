import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 10.0.5 Tests, `AdapterTests/Novita` (Q-062): the probe, its failures, and the balance poll → exact
/// `balance_snapshot` rows from 1/10000 USD strings (÷ 100, half away from zero). Synthetic fixtures from 02 § novita.
@Suite struct NovitaTests {
  static let path = "/openapi/v1/billing/balance/detail"
  static let now = OpenAIHarness.now
  static let fetchedAt = "2026-11-10T12:00:00.000Z"

  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository
    let transport = StubTransport()
    let adapter: NovitaAdapter
    let poller: Poller
    let account: AccountRecord
    let key = "sk_" + String(repeating: "Nv8", count: 16)

    init() async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      var record = FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-0000000000c1", provider: "novita",
                                            label: "Novita")
      record.keychainRef = "novita"
      record.balanceMode = BalanceMode.direct.rawValue
      record.capabilities = try NovitaAdapter.capabilities.json()
      record.orgId = nil
      record.orgName = nil
      account = record
      try await repository.insertAccount(record)
      adapter = NovitaAdapter(logPipeline: store.pipeline)
      poller = Poller(
        store: repository, keyStore: InMemoryKeyStore([record.keychainRef: key]),
        registry: ProviderRegistry(adapters: [adapter]), transport: transport, clock: TestClock(),
        rng: SeededRNG(seed: 5), logPipeline: store.pipeline, now: { NovitaTests.now }
      )
    }

    func on(_ name: String) async {
      let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
      await transport.on("GET", NovitaTests.path,
                         .fixture(root.appendingPathComponent("Fixtures/providers/novita/balance.\(name).synthetic.json")))
    }

    func probe() async -> ProbeResult { await adapter.probe(key: key, transport: transport) }

    func records(_ evt: Evt) async -> [LogRecord] { await store.records(evt) }
  }

  @Test("probe ok: direct, USD, one request to api.novita.ai with the key, body kept redacted")
  func probeOK() async throws {
    let env = try await Harness()
    await env.on("ok")
    let result = await env.probe()
    #expect(result.humanMessage == nil)
    #expect(result.capabilities == NovitaAdapter.capabilities)
    #expect(result.capabilities.balance && !result.capabilities.usage && !result.capabilities.cost)
    #expect(result.currency == .usd)
    let request = try #require(await env.transport.calls.first)
    #expect(request.url.absoluteString == "https://api.novita.ai/openapi/v1/billing/balance/detail")
    #expect(request.headers["Authorization"] == "Bearer \(env.key)")
    #expect(result.rawBodiesRedacted["balance"]?.contains("1000000") == true)
  }

  @Test("probe failures end with their messages; the key never appears", arguments: [
    (OpenAIHarness.status(403, "no"), CoreStrings.Novita.keyRejected),
    (OpenAIHarness.status(429), CoreStrings.rateLimited("Novita")),
    (OpenAIHarness.status(500, "down"), CoreStrings.serverError("Novita", status: 500))
  ])
  func probeFailures(_ answer: StubTransport.Answer, _ message: String) async throws {
    let env = try await Harness()
    await env.transport.on("GET", Self.path, answer)
    #expect(await env.probe().humanMessage == message)
    await env.store.pipeline.drain()
    #expect(!(await env.store.sink.lines().joined()).contains(env.key))
  }

  @Test("the 401 fixture gives 02's key-rejected message")
  func probe401() async throws {
    let env = try await Harness()
    await env.on("401")
    let result = await env.probe()
    #expect(result.humanMessage == CoreStrings.Novita.keyRejected)
    #expect(result.rawBodiesRedacted["balance"]?.contains("synthetic 401") == true)
  }

  @Test("an amount that is not a decimal string: poll.schema_drift, the unexpected-response message")
  func probeDrift() async throws {
    let env = try await Harness()
    await env.on("drift")
    #expect(await env.probe().humanMessage == CoreStrings.unexpectedResponse("Novita"))
    #expect(await env.records(.pollSchemaDrift).count == 1)
  }

  @Test("the poll writes one USD snapshot: available → amount, cash → topped up, 1/10000 USD → cents")
  func pollOK() async throws {
    let env = try await Harness()
    await env.on("ok")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .succeeded(rows: 1))
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id) == [
      BalanceSnapshotRecord(accountId: env.account.id, ts: Self.fetchedAt, currency: "USD", amountCents: 10_000,
                            grantedCents: nil, toppedUpCents: 8_000, isAvailable: nil)
    ])
  }

  @Test("half a cent rounds away from zero, for a negative cash balance too (05)")
  func pollRounding() async throws {
    let env = try await Harness()
    await env.on("rounding")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .succeeded(rows: 1))
    let snapshot = try #require(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id).first)
    #expect(snapshot.amountCents == 12_346)
    #expect(snapshot.toppedUpCents == -124)
  }

  @Test("a poll whose body drifted fails as decode and writes nothing; unknown keys are logged once a day")
  func pollDriftAndUnknown() async throws {
    let env = try await Harness()
    await env.on("drift")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .failed("decode"))
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id).isEmpty)
    let body = #"{"availableBalance":"10000","cashBalance":"10000","frozenBalance":"0"}"#
    await env.transport.on("GET", Self.path, OpenAIHarness.ok(body), OpenAIHarness.ok(body))
    _ = await env.poller.runOnce(account: env.account, job: .balance)
    _ = await env.poller.runOnce(account: env.account, job: .balance)
    let unknown = await env.records(.pollUnknownKeys)
    #expect(unknown.count == 1)
    #expect(unknown.first?.ctx["keys"] == .string("frozenBalance"))
  }

  @Test("Novita has no usage, cost or keys job in V1 (02): those polls answer their provider rule")
  func noOtherPolls() async throws {
    let env = try await Harness()
    let context = PollContext(accountID: env.account.id, key: env.key, cursor: nil,
                              window: DateInterval(start: Self.now, end: Self.now), transport: env.transport,
                              clock: TestClock())
    await #expect(throws: PollError.providerRule("novita_no_usage_api")) { try await env.adapter.pollUsage(context) }
    await #expect(throws: PollError.providerRule("novita_no_cost_api")) { try await env.adapter.pollCost(context) }
    await #expect(throws: PollError.providerRule("novita_no_keys_api")) { try await env.adapter.pollKeys(context) }
  }

  @Test("fixture mode serves the probe")
  func fixtureRoutes() async throws {
    let result = await NovitaAdapter(logPipeline: try StoreHarness().pipeline)
      .probe(key: "fixture", transport: FixtureTransport(routes: FixtureTransport.knownRoutes))
    #expect(result.humanMessage == nil && result.currency == .usd)
  }
}
