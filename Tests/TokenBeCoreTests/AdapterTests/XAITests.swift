import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 6.2 Tests, `AdapterTests/XAI`: both `GET /v1/api-key` shapes → the account's mode (D-xai-balance), the
/// probe's failures, and a direct account's balance poll → its exact `balance_snapshot` row.
@Suite struct XAITests {
  static let path = "/v1/api-key"
  static let now = OpenAIHarness.now
  static let fetchedAt = "2026-11-10T12:00:00.000Z"

  /// One xAI account on a temp-file database, `direct` (the `api_key.ok` shape) unless `capabilities` says otherwise.
  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository
    let transport = StubTransport()
    let adapter: XAIAdapter
    let poller: Poller
    let account: AccountRecord
    let key = "xai-" + String(repeating: "Xa1", count: 12)

    init(capabilities: Capabilities = XAIAdapter.capabilities) async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      var record = FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-0000000000a1", provider: "xai", label: "xAI")
      record.keychainRef = "xai"
      record.balanceMode = capabilities.balanceModeDefault.rawValue
      record.capabilities = try capabilities.json()
      record.orgId = nil
      record.orgName = nil
      account = record
      try await repository.insertAccount(record)
      adapter = XAIAdapter(logPipeline: store.pipeline)
      poller = Poller(
        store: repository, keyStore: InMemoryKeyStore([record.keychainRef: key]),
        registry: ProviderRegistry(adapters: [adapter]), transport: transport, clock: TestClock(),
        rng: SeededRNG(seed: 5), logPipeline: store.pipeline, now: { XAITests.now }
      )
    }

    func on(_ fixture: String) async {
      let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
      await transport.on("GET", XAITests.path,
                         .fixture(root.appendingPathComponent("Fixtures/providers/xai/api_key.\(fixture).synthetic.json")))
    }

    func on(_ answer: StubTransport.Answer) async { await transport.on("GET", XAITests.path, answer) }

    func probe() async -> ProbeResult { await adapter.probe(key: key, transport: transport) }

    func records(_ evt: Evt) async -> [LogRecord] { await store.records(evt) }
  }

  // MARK: - Probe → mode

  @Test("remaining_balance as a number → direct, balance job on, USD (D-xai-balance)")
  func probeDirect() async throws {
    let env = try await Harness()
    await env.on("ok")
    let result = await env.probe()
    #expect(result.humanMessage == nil)
    #expect(result.capabilities == XAIAdapter.capabilities)
    #expect(result.capabilities.balanceModeDefault == .direct && result.capabilities.balance)
    #expect(result.currency == .usd)
    #expect(await env.records(.pollProviderRule).isEmpty)
    let request = try #require(await env.transport.calls.first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/api-key")
    #expect(request.headers["Authorization"] == "Bearer \(env.key)")
  }

  @Test("no usable remaining_balance → anchored, no balance job, poll.provider_rule xai_no_balance_field",
        arguments: [
          "no_balance",
          #"{"remaining_balance":null,"spent_balance":1}"#,
          #"{"remaining_balance":"42.50"}"#,
          #"{"remaining_balance":true}"#
        ])
  func probeAnchored(_ shape: String) async throws {
    let env = try await Harness()
    if shape.hasPrefix("{") { await env.on(OpenAIHarness.ok(shape)) } else { await env.on(shape) }
    let result = await env.probe()
    #expect(result.humanMessage == nil)
    #expect(result.capabilities == XAIAdapter.anchoredCapabilities)
    #expect(result.capabilities.balanceModeDefault == .anchored && !result.capabilities.balance)
    let rule = try #require(await env.records(.pollProviderRule).first)
    #expect(rule.ctx["rule"] == .string("xai_no_balance_field"))
    #expect(rule.lvl == .warn)
  }

  @Test("probe failures end with their messages; the key never appears", arguments: [
    (OpenAIHarness.status(401, "bad"), CoreStrings.XAI.keyRejected),
    (OpenAIHarness.status(403, "no"), CoreStrings.XAI.keyRejected),
    (OpenAIHarness.status(429), CoreStrings.rateLimited("xAI")),
    (OpenAIHarness.status(500), CoreStrings.serverError("xAI", status: 500)),
    (OpenAIHarness.ok("[1,2]"), CoreStrings.unexpectedResponse("xAI"))
  ])
  func probeFailures(_ answer: StubTransport.Answer, _ message: String) async throws {
    let env = try await Harness()
    await env.on(answer)
    #expect(await env.probe().humanMessage == message)
    await env.store.pipeline.drain()
    #expect(!(await env.store.sink.lines().joined()).contains(env.key))
  }

  @Test("the 401 fixture gives the key-rejected message")
  func probe401Fixture() async throws {
    let env = try await Harness()
    await env.on("401")
    #expect(await env.probe().humanMessage == CoreStrings.XAI.keyRejected)
  }

  // MARK: - Balance poll (direct accounts)

  @Test("a direct account's poll writes one USD snapshot: dollars → cents, half up, from the number's digits")
  func pollDirect() async throws {
    let env = try await Harness()
    await env.on("ok")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .succeeded(rows: 1))
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id) == [
      BalanceSnapshotRecord(accountId: env.account.id, ts: Self.fetchedAt, currency: "USD", amountCents: 4_251,
                            grantedCents: nil, toppedUpCents: nil, isAvailable: nil)
    ])
  }

  @Test("a direct account whose response lost remaining_balance fails as decode (schema drift), writes nothing")
  func pollLostField() async throws {
    let env = try await Harness()
    await env.on("no_balance")
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .failed("decode"))
    #expect(try await env.repository.fetchBalanceSnapshots(accountID: env.account.id).isEmpty)
    #expect(await env.records(.pollSchemaDrift).first?.ctx["missing_keys"] == .string("remaining_balance"))
  }

  @Test("an anchored account never polls a balance: the job is skipped before any request")
  func anchoredSkipsBalance() async throws {
    let env = try await Harness(capabilities: XAIAdapter.anchoredCapabilities)
    #expect(await env.poller.runOnce(account: env.account, job: .balance) == .skipped("xai_no_balance_api"))
    #expect(await env.transport.calls.isEmpty)
  }

  @Test("xAI has no usage, cost or keys endpoint in V1 (02): those polls answer their provider rule")
  func noOtherPolls() async throws {
    let env = try await Harness()
    let context = PollContext(accountID: env.account.id, key: env.key, cursor: nil,
                              window: DateInterval(start: Self.now, end: Self.now), transport: env.transport,
                              clock: TestClock())
    await #expect(throws: PollError.providerRule("xai_no_usage_api")) { try await env.adapter.pollUsage(context) }
    await #expect(throws: PollError.providerRule("xai_no_cost_api")) { try await env.adapter.pollCost(context) }
    await #expect(throws: PollError.providerRule("xai_no_keys_api")) { try await env.adapter.pollKeys(context) }
  }

  @Test("fixture mode serves both shapes")
  func fixtureRoutes() async throws {
    let pipeline = try StoreHarness().pipeline
    let direct = await XAIAdapter(logPipeline: pipeline)
      .probe(key: "fixture", transport: FixtureTransport(routes: FixtureTransport.knownRoutes))
    #expect(direct.capabilities.balanceModeDefault == .direct)
    let anchored = await XAIAdapter(logPipeline: pipeline).probe(
      key: "fixture", transport: FixtureTransport(routes: FixtureTransport.knownRoutes,
                                                  cases: ["xai/api_key": "no_balance"])
    )
    #expect(anchored.capabilities.balanceModeDefault == .anchored)
  }
}
