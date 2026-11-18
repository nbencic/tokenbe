import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 10.0.4 Tests, `AdapterTests/Moonshot` (Q-062): the probe finds the key's region (`api.moonshot.ai`,
/// USD, else `api.moonshot.cn`, CNY), its failures, and the balance poll → exact `balance_snapshot` rows from the
/// account's region. Synthetic fixtures from 02 § moonshot only (R2).
@Suite struct MoonshotTests {
  static let path = "/v1/users/me/balance"
  static let now = OpenAIHarness.now
  static let fetchedAt = "2026-11-10T12:00:00.000Z"

  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository
    let transport = StubTransport()
    let adapter: MoonshotAdapter
    let poller: Poller
    let account: AccountRecord
    let key = "sk-" + String(repeating: "Ms4", count: 16)

    init(currency: Currency = .usd) async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      var record = FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-0000000000b1", provider: "moonshot",
                                            label: "Moonshot")
      record.keychainRef = "moonshot"
      record.balanceMode = BalanceMode.direct.rawValue
      record.currency = currency.rawValue
      var capabilities = MoonshotAdapter.capabilities
      capabilities.currencyHint = currency
      record.capabilities = try capabilities.json()
      record.orgId = nil
      record.orgName = nil
      account = record
      try await repository.insertAccount(record)
      adapter = MoonshotAdapter(logPipeline: store.pipeline)
      poller = Poller(
        store: repository, keyStore: InMemoryKeyStore([record.keychainRef: key]),
        registry: ProviderRegistry(adapters: [adapter]), transport: transport, clock: TestClock(),
        rng: SeededRNG(seed: 5), logPipeline: store.pipeline, now: { MoonshotTests.now }
      )
    }

    static func fixture(_ name: String) -> StubTransport.Answer {
      let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
      return .fixture(root.appendingPathComponent("Fixtures/providers/moonshot/\(name).synthetic.json"))
    }

    /// The answers in the order the requests arrive (both hosts share the path).
    func on(_ names: String...) async {
      for name in names { await transport.on("GET", MoonshotTests.path, Self.fixture(name)) }
    }

    func probe() async -> ProbeResult { await adapter.probe(key: key, transport: transport) }

    func hosts() async -> [String] { await transport.calls.compactMap { $0.url.host() } }

    func records(_ evt: Evt) async -> [LogRecord] { await store.records(evt) }
  }

  // MARK: - Probe

  @Test("an international key: direct, USD, one request to api.moonshot.ai, body kept redacted")
  func probeInternational() async throws {
    let env = try await Harness()
    await env.on("balance.ok")
    let result = await env.probe()
    #expect(result.humanMessage == nil)
    #expect(result.capabilities.balance && !result.capabilities.usage && !result.capabilities.cost)
    #expect(result.capabilities.balanceModeDefault == .direct)
    #expect(result.currency == .usd && result.capabilities.currencyHint == .usd)
    #expect(await env.hosts() == ["api.moonshot.ai"])
    #expect(await env.transport.calls.first?.headers["Authorization"] == "Bearer \(env.key)")
    #expect(result.rawBodiesRedacted["balance"]?.contains("49.58894") == true)
  }

  @Test("a China key: the .ai 401 is a debug region fallback, then api.moonshot.cn answers in CNY")
  func probeChina() async throws {
    let env = try await Harness()
    env.store.pipeline.minimumLevel = .debug  // `poll.region_fallback` is a debug record (07)
    await env.on("balance.401", "balance_cn.ok")
    let result = await env.probe()
    #expect(result.humanMessage == nil)
    #expect(result.currency == .cny && result.capabilities.currencyHint == .cny)
    #expect(await env.hosts() == ["api.moonshot.ai", "api.moonshot.cn"])
    let fallback = try #require(await env.records(.pollRegionFallback).first)
    #expect(fallback.lvl == .debug)
    #expect(fallback.ctx["to_host"] == .string("api.moonshot.cn"))
    #expect(await env.records(.pollFailed).isEmpty, "the expected 401 is not a failure")
  }

  @Test("refused on both regions: 02's key-rejected message, no key in the log")
  func probeRefused() async throws {
    let env = try await Harness()
    await env.on("balance.401", "balance.401")
    let result = await env.probe()
    #expect(result.humanMessage == CoreStrings.Moonshot.keyRejected)
    #expect(await env.hosts() == ["api.moonshot.ai", "api.moonshot.cn"])
    #expect(result.rawBodiesRedacted["balance"]?.contains("synthetic 401") == true)
    await env.store.pipeline.drain()
    #expect(!(await env.store.sink.lines().joined()).contains(env.key))
  }

  @Test("other failures end with their messages", arguments: [
    (OpenAIHarness.status(403, "no"), CoreStrings.Moonshot.keyRejected),
    (OpenAIHarness.status(429), CoreStrings.rateLimited("Moonshot")),
    (OpenAIHarness.status(500, "down"), CoreStrings.serverError("Moonshot", status: 500))
  ])
  func probeFailures(_ answer: StubTransport.Answer, _ message: String) async throws {
    let env = try await Harness()
    await env.transport.on("GET", Self.path, answer)
    #expect(await env.probe().humanMessage == message)
    #expect(await env.hosts() == ["api.moonshot.ai"], "only a 401 tries the other region")
  }

  @Test("status false / code ≠ 0 and an unreadable body: the unexpected-response message")
  func probeUnusable() async throws {
    let notOK = try await Harness()
    await notOK.on("balance.not_ok")
    #expect(await notOK.probe().humanMessage == CoreStrings.unexpectedResponse("Moonshot"))
    #expect(await notOK.records(.pollFailed).first?.err?.type == "PollError.providerRule")
    let drift = try await Harness()
    await drift.on("balance.drift")
    #expect(await drift.probe().humanMessage == CoreStrings.unexpectedResponse("Moonshot"))
    #expect(await drift.records(.pollSchemaDrift).count == 1)
  }

  // MARK: - Balance poll

  @Test("a USD account polls api.moonshot.ai: available, voucher (granted) and cash (topped up), half up to cents")
  func pollUSD() async throws {
    let env = try await Harness()
    await env.on("balance.ok")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .succeeded(rows: 1))
    #expect(await env.hosts() == ["api.moonshot.ai"])
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id) == [
      BalanceSnapshotRecord(accountId: env.account.id, ts: Self.fetchedAt, currency: "USD", amountCents: 4_959,
                            grantedCents: 4_659, toppedUpCents: 300, isAvailable: nil)
    ])
  }

  @Test("a CNY account polls api.moonshot.cn only")
  func pollCNY() async throws {
    let env = try await Harness(currency: .cny)
    await env.on("balance_cn.ok")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .succeeded(rows: 1))
    #expect(await env.hosts() == ["api.moonshot.cn"])
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id) == [
      BalanceSnapshotRecord(accountId: env.account.id, ts: Self.fetchedAt, currency: "CNY", amountCents: 12_050,
                            grantedCents: 2_000, toppedUpCents: 10_050, isAvailable: nil)
    ])
  }

  @Test("an account that owes money keeps its negative cash balance")
  func pollOwing() async throws {
    let env = try await Harness()
    await env.on("balance.owing")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .succeeded(rows: 1))
    let snapshot = try #require(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id).first)
    #expect(snapshot.amountCents == 550 && snapshot.toppedUpCents == -213 && snapshot.grantedCents == 550)
  }

  @Test("a not-ok body fails the poll as a provider rule and writes nothing; unknown keys are logged once a day")
  func pollNotOKAndUnknown() async throws {
    let env = try await Harness()
    await env.on("balance.not_ok")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .failed("provider_rule"))
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id).isEmpty)
    let body = #"{"code":0,"data":{"available_balance":1,"voucher_balance":0,"cash_balance":1,"frozen":0},"#
      + #""scode":"0x0","status":true}"#
    await env.transport.on("GET", Self.path, OpenAIHarness.ok(body), OpenAIHarness.ok(body))
    _ = await env.poller.runOnce(account: env.account, job: .balance)
    _ = await env.poller.runOnce(account: env.account, job: .balance)
    let unknown = await env.records(.pollUnknownKeys)
    #expect(unknown.count == 1)
    #expect(unknown.first?.ctx["keys"] == .string("data.frozen"))
  }

  @Test("Moonshot has no usage, cost or keys endpoint (02): those polls answer their provider rule")
  func noOtherPolls() async throws {
    let env = try await Harness()
    let context = PollContext(accountID: env.account.id, key: env.key, cursor: nil,
                              window: DateInterval(start: Self.now, end: Self.now), transport: env.transport,
                              clock: TestClock())
    await #expect(throws: PollError.providerRule("moonshot_no_usage_api")) { try await env.adapter.pollUsage(context) }
    await #expect(throws: PollError.providerRule("moonshot_no_cost_api")) { try await env.adapter.pollCost(context) }
    await #expect(throws: PollError.providerRule("moonshot_no_keys_api")) { try await env.adapter.pollKeys(context) }
  }

  @Test("fixture mode serves both regions")
  func fixtureRoutes() async throws {
    let pipeline = try StoreHarness().pipeline
    let international = await MoonshotAdapter(logPipeline: pipeline)
      .probe(key: "fixture", transport: FixtureTransport(routes: FixtureTransport.knownRoutes))
    #expect(international.currency == .usd && international.humanMessage == nil)
    let china = await MoonshotAdapter(logPipeline: pipeline).probe(
      key: "fixture", transport: FixtureTransport(routes: FixtureTransport.knownRoutes,
                                                  cases: ["moonshot/balance": "401"])
    )
    #expect(china.currency == .cny && china.humanMessage == nil)
  }

  @Test("the region's host: CNY → .cn, anything else → .ai")
  func hosts() {
    #expect(MoonshotAdapter.host(currency: "CNY") == "api.moonshot.cn")
    #expect(MoonshotAdapter.host(currency: "USD") == "api.moonshot.ai")
  }
}
