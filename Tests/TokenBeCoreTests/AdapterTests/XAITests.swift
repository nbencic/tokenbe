import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 10.0.2 Tests, `AdapterTests/XAI` (Q-062): the management key's probe (validation → team → one usage
/// call), its failures, and the cost job → exact `cost_bucket` rows. Synthetic fixtures from 02 § xai only (R2).
@Suite struct XAITests {
  static let validation = "/auth/management-keys/validation"
  static let usage = "/v1/billing/teams/team_fixture/usage"
  static let now = OpenAIHarness.now
  static let fetchedAt = "2026-11-10T12:00:00.000Z"

  /// One xAI account on a temp-file database.
  struct Harness {
    let store: StoreHarness
    let repository: GRDBRepository
    let transport = StubTransport()
    let adapter: XAIAdapter
    let poller: Poller
    let account: AccountRecord
    let key = "xai-" + String(repeating: "Mk7", count: 12)

    init() async throws {
      store = try StoreHarness()
      repository = GRDBRepository(database: try await store.open().database)
      var record = FixtureDBBuilder.account(id: "0190f0a0-0000-7000-8000-0000000000a1", provider: "xai", label: "xAI")
      record.keychainRef = "xai"
      record.balanceMode = BalanceMode.anchored.rawValue
      record.capabilities = try XAIAdapter.capabilities.json()
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

    static func fixture(_ name: String) -> StubTransport.Answer {
      let root = Bundle.module.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
      return .fixture(root.appendingPathComponent("Fixtures/providers/xai/\(name).synthetic.json"))
    }

    func on(validation: String = "ok", usage: String = "ok") async {
      await transport.on("GET", XAITests.validation, Self.fixture("validation.\(validation)"))
      await transport.on("POST", XAITests.usage, Self.fixture("usage.\(usage)"))
    }

    func probe() async -> ProbeResult { await adapter.probe(key: key, transport: transport) }

    func records(_ evt: Evt) async -> [LogRecord] { await store.records(evt) }
  }

  // MARK: - Probe

  @Test("a team management key passes: anchored with the cost job, USD; validation then one usage call")
  func probeOK() async throws {
    let env = try await Harness()
    await env.on()
    let result = await env.probe()
    #expect(result.humanMessage == nil)
    #expect(result.capabilities == XAIAdapter.capabilities)
    #expect(result.capabilities.balanceModeDefault == .anchored && result.capabilities.cost)
    #expect(!result.capabilities.balance && !result.capabilities.usage)
    #expect(result.currency == .usd)
    #expect(await env.transport.callOrder == ["GET \(Self.validation)", "POST \(Self.usage)"])
    let calls = await env.transport.calls
    #expect(calls.allSatisfy { $0.url.host() == "management-api.x.ai" })
    #expect(calls.allSatisfy { $0.headers["Authorization"] == "Bearer \(env.key)" })
    #expect(calls[1].headers["Content-Type"] == "application/json")
  }

  @Test("a key with only the deprecated teamId still names its team")
  func probeLegacyTeam() async throws {
    let env = try await Harness()
    await env.on(validation: "legacy")
    #expect(await env.probe().humanMessage == nil)
    #expect(await env.transport.callOrder.last == "POST \(Self.usage)")
  }

  @Test("an organization-scoped key has no team: 02's message, no usage call")
  func probeNoTeam() async throws {
    let env = try await Harness()
    await env.on(validation: "organization")
    #expect(await env.probe().humanMessage == CoreStrings.XAI.noTeam)
    #expect(await env.transport.callOrder == ["GET \(Self.validation)"])
    #expect(await env.records(.pollFailed).first?.ctx["endpoint"] == .string("validation"))
  }

  @Test("a refused key (validation 401) and a key without billing access (usage 403) give the key-rejected message")
  func probeRefused() async throws {
    let refused = try await Harness()
    await refused.on(validation: "401")
    #expect(await refused.probe().humanMessage == CoreStrings.XAI.keyRejected)
    let noBilling = try await Harness()
    await noBilling.on(usage: "403")
    let result = await noBilling.probe()
    #expect(result.humanMessage == CoreStrings.XAI.keyRejected)
    #expect(result.rawBodiesRedacted["usage"]?.contains("synthetic 403") == true)
    #expect(await noBilling.records(.pollFailed).first?.ctx["endpoint"] == .string("usage"))
  }

  @Test("probe failures end with their messages; the key never appears", arguments: [
    (OpenAIHarness.status(429), CoreStrings.rateLimited("xAI")),
    (OpenAIHarness.status(500), CoreStrings.serverError("xAI", status: 500)),
    (OpenAIHarness.ok("[1,2]"), CoreStrings.unexpectedResponse("xAI"))
  ])
  func probeFailures(_ answer: StubTransport.Answer, _ message: String) async throws {
    let env = try await Harness()
    await env.transport.on("GET", Self.validation, answer)
    #expect(await env.probe().humanMessage == message)
    await env.store.pipeline.drain()
    #expect(!(await env.store.sink.lines().joined()).contains(env.key))
  }

  @Test("a usage body TokenBe cannot read: poll.schema_drift with a sample, the unexpected-response message")
  func probeDrift() async throws {
    let env = try await Harness()
    await env.on(usage: "drift")
    #expect(await env.probe().humanMessage == CoreStrings.unexpectedResponse("xAI"))
    let drift = try #require(await env.records(.pollSchemaDrift).first)
    #expect(drift.ctx["missing_keys"] == .string("timestamp (usage: timeSeries[].dataPoints[])"))
    #expect(drift.ctx["sample"].map { "\($0)".contains("yesterday") } == true)
  }

  // MARK: - Cost job

  @Test("the cost job writes per day one description row per model and a total, dollars → cents once, half up")
  func pollCost() async throws {
    let env = try await Harness()
    await env.on()
    #expect(await env.poller.runOnce(account: env.account, job: .cost) == .succeeded(rows: 6))
    let id = env.account.id
    func row(_ day: String, _ kind: String, _ key: String, _ cents: Int64, _ provisional: Bool) -> CostBucketRecord {
      CostBucketRecord(accountId: id, day: day, groupKind: kind, groupKey: key, amountCents: cents, currency: "USD",
                       provisional: provisional, fetchedAt: Self.fetchedAt)
    }
    #expect(try await env.repository.fetchCostBuckets(accountID: id) == [
      row("2026-11-09", "description", "Chat grok-4-0709", 123, false),
      row("2026-11-09", "description", "Chat grok-4-fast-non-reasoning", 0, false),
      row("2026-11-09", "total", "", 123, false),
      row("2026-11-10", "description", "Chat grok-4-0709", 76, true),
      row("2026-11-10", "description", "Chat grok-4-fast-non-reasoning", 14, true),
      row("2026-11-10", "total", "", 90, true)
    ])
  }

  @Test("the usage request asks for daily USD per model over whole UTC days of the 7-day window")
  func usageRequestBody() async throws {
    let env = try await Harness()
    await env.on()
    _ = await env.poller.runOnce(account: env.account, job: .cost)
    let post = try #require(await env.transport.calls.first { $0.method == "POST" })
    let data = try #require(post.body)
    let body = try #require(String(bytes: data, encoding: .utf8))
    #expect(body == #"{"analyticsRequest":{"filters":[],"groupBy":["description"],"timeRange":{"#
      + #""endTime":"2026-11-11 00:00:00","startTime":"2026-11-03 00:00:00","timezone":"Etc/GMT"},"#
      + #""timeUnit":"TIME_UNIT_DAY","values":[{"aggregation":"AGGREGATION_SUM","name":"usd"}]}}"#)
  }

  @Test("limitReached keeps the partial rows and logs xai_usage_limit_reached once a day")
  func limitReached() async throws {
    let env = try await Harness()
    await env.transport.on("GET", Self.validation, Harness.fixture("validation.ok"), Harness.fixture("validation.ok"))
    await env.transport.on("POST", Self.usage, Harness.fixture("usage.limit"), Harness.fixture("usage.limit"))
    #expect(await env.poller.runOnce(account: env.account, job: .cost) == .succeeded(rows: 2))
    #expect(await env.poller.runOnce(account: env.account, job: .cost) == .succeeded(rows: 2))
    let rules = await env.records(.pollProviderRule)
    #expect(rules.count == 1)
    #expect(rules.first?.ctx["rule"] == .string("xai_usage_limit_reached"))
  }

  @Test("a cost poll with an unreadable timestamp fails as decode and writes nothing")
  func pollDrift() async throws {
    let env = try await Harness()
    await env.on(usage: "drift")
    #expect(await env.poller.runOnce(account: env.account, job: .cost) == .failed("decode"))
    #expect(try await env.repository.fetchCostBuckets(accountID: env.account.id).isEmpty)
  }

  @Test("a key that lost its team fails the cost poll as the no-team provider rule")
  func pollNoTeam() async throws {
    let env = try await Harness()
    await env.on(validation: "organization")
    #expect(await env.poller.runOnce(account: env.account, job: .cost) == .failed("provider_rule"))
  }

  @Test("unknown keys are logged once per day")
  func unknownKeys() async throws {
    let env = try await Harness()
    let body = #"{"timeSeries":[],"limitReached":false,"nextPage":"x"}"#
    await env.transport.on("GET", Self.validation, Harness.fixture("validation.ok"), Harness.fixture("validation.ok"))
    await env.transport.on("POST", Self.usage, OpenAIHarness.ok(body), OpenAIHarness.ok(body))
    _ = await env.poller.runOnce(account: env.account, job: .cost)
    _ = await env.poller.runOnce(account: env.account, job: .cost)
    let unknown = await env.records(.pollUnknownKeys)
    #expect(unknown.count == 1)
    #expect(unknown.first?.ctx["keys"] == .string("nextPage"))
  }

  @Test("xAI has no usage, balance or keys job: those polls answer their provider rule")
  func noOtherPolls() async throws {
    let env = try await Harness()
    let context = PollContext(accountID: env.account.id, key: env.key, cursor: nil,
                              window: DateInterval(start: Self.now, end: Self.now), transport: env.transport,
                              clock: TestClock())
    await #expect(throws: PollError.providerRule("xai_no_usage_api")) { try await env.adapter.pollUsage(context) }
    await #expect(throws: PollError.providerRule("xai_no_balance_api")) { try await env.adapter.pollBalance(context) }
    await #expect(throws: PollError.providerRule("xai_no_keys_api")) { try await env.adapter.pollKeys(context) }
  }

  @Test("fixture mode serves the probe and the cost job")
  func fixtureRoutes() async throws {
    let pipeline = try StoreHarness().pipeline
    let result = await XAIAdapter(logPipeline: pipeline)
      .probe(key: "fixture", transport: FixtureTransport(routes: FixtureTransport.knownRoutes))
    #expect(result.humanMessage == nil)
    #expect(result.capabilities.cost)
  }

  @Test("timestamps: an ISO UTC day start maps to its day; anything else is nil")
  func days() {
    #expect(XAIAdapter.day("2026-11-10T00:00:00Z") == "2026-11-10")
    #expect(XAIAdapter.day("2026-13-40T00:00:00Z") == nil)
    #expect(XAIAdapter.day("yesterday") == nil)
  }
}

/// `BearerRequest` (DeepSeek, xAI): a path that is not absolute cannot form a URL and fails as a provider rule, before
/// any request.
@Suite struct BearerRequestTests {
  @Test("a relative path fails as <provider>_bad_url without sending")
  func badURL() async throws {
    let transport = StubTransport()
    await #expect(throws: PollError.providerRule("xai_bad_url no-slash")) {
      try await BearerRequest.post(BearerRequest.Target(host: "management-api.x.ai", path: "no-slash", provider: .xai),
                                   key: "k", json: Data(), transport: transport)
    }
    #expect(await transport.calls.isEmpty)
  }
}
