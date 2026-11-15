import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 6.1 Tests, `AdapterTests/DeepSeek`: the probe (currency from the first entry, 02's failures), the
/// balance poll → exact `balance_snapshot` rows for each synthetic fixture (string amounts incl. `"110.00"`, two
/// currencies, unavailable), strict amount parsing, and the polls DeepSeek does not have.
@Suite struct DeepSeekTests {
  typealias Harness = DeepSeekHarness

  // MARK: - Amount strings

  @Test("amounts: digits with an optional fraction parse in any locale; anything else is rejected (Q-045)")
  func amounts() {
    #expect(MinorUnits.decimal("110.00") == Decimal(110))
    #expect(MinorUnits.decimal("0") == Decimal(0))
    #expect(MinorUnits.decimal("-3.25") == Decimal(string: "-3.25", locale: Locale(identifier: "en_US_POSIX")))
    for bad in ["", "-", ".5", "5.", "12abc", "1,5", "1.2.3", " 1.00", "1.00 ", "+1", "1e3", "١٢"] {
      #expect(MinorUnits.decimal(bad) == nil, "\(bad)")
    }
    #expect(MinorUnits.cents(Decimal(string: "56.785", locale: Locale(identifier: "en_US_POSIX")) ?? 0) == 5_679)
    #expect(MinorUnits.cents(Decimal(string: "50.004", locale: Locale(identifier: "en_US_POSIX")) ?? 0) == 5_000)
  }

  // MARK: - Probe

  @Test("probe ok: direct balance, no usage/cost/keys, currency from the first entry, body kept redacted")
  func probeOK() async throws {
    let env = try await Harness()
    await env.on("ok")
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == nil)
    #expect(result.capabilities == DeepSeekAdapter.capabilities)
    #expect(result.capabilities.balance && !result.capabilities.usage && !result.capabilities.cost)
    #expect(result.capabilities.balanceModeDefault == .direct)
    #expect(result.currency == .usd)
    #expect(result.discoveredKeys.isEmpty)
    #expect(result.rawBodiesRedacted["balance"]?.contains("110.00") == true)
    let request = try #require(await env.transport.calls.first)
    #expect(request.url.absoluteString == "https://api.deepseek.com/user/balance")
    #expect(request.headers["Authorization"] == "Bearer \(env.key)")
  }

  @Test("probe: CNY first → the account's currency is CNY (02)")
  func probeCNY() async throws {
    let env = try await Harness()
    await env.on("cny")
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == nil)
    #expect(result.currency == .cny)
  }

  @Test("probe: unavailable still passes (D-deepseek-unavailable shows the balance)")
  func probeUnavailable() async throws {
    let env = try await Harness()
    await env.on("unavailable")
    #expect(await env.adapter.probe(key: env.key, transport: env.transport).humanMessage == nil)
  }

  @Test("probe 401: the key-rejected message; the key is in no body and no log line")
  func probe401() async throws {
    let env = try await Harness()
    await env.on(OpenAIHarness.status(401, "bad key \(env.key)"))
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == CoreStrings.DeepSeek.keyRejected)
    #expect(result.rawBodiesRedacted["balance"]?.contains(env.key) == false)
    #expect(await env.records(.pollFailed).first?.job == "probe")
    #expect(!(await env.allLines()).contains(env.key))
  }

  @Test("probe: 429, 5xx and offline end with their messages", arguments: [
    (OpenAIHarness.status(429), CoreStrings.rateLimited("DeepSeek")),
    (OpenAIHarness.status(503), CoreStrings.serverError("DeepSeek", status: 503)),
    (StubTransport.Answer.failure(.urlError(URLError(.notConnectedToInternet))), CoreStrings.unreachable("DeepSeek"))
  ])
  func probeFailures(_ answer: StubTransport.Answer, _ message: String) async throws {
    let env = try await Harness()
    await env.on(answer)
    #expect(await env.adapter.probe(key: env.key, transport: env.transport).humanMessage == message)
  }

  @Test("probe: a first currency TokenBe cannot show, a bad amount, or no entries → unexpected response + drift",
        arguments: [
          #"{"is_available":true,"balance_infos":[{"currency":"EUR","total_balance":"1.00"}]}"#,
          #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12abc"}]}"#,
          #"{"is_available":true,"balance_infos":[]}"#,
          #"{"balance_infos":[{"currency":"USD","total_balance":"1.00"}]}"#
        ])
  func probeUnreadable(_ body: String) async throws {
    let env = try await Harness()
    await env.on(OpenAIHarness.ok(body))
    let result = await env.adapter.probe(key: env.key, transport: env.transport)
    #expect(result.humanMessage == CoreStrings.unexpectedResponse("DeepSeek"))
    #expect(await env.records(.pollSchemaDrift).count == 1)
  }

  // MARK: - Balance poll

  @Test("balance ok: one USD snapshot with every amount in cents; poll_state success and last_raw")
  func balanceOK() async throws {
    let env = try await Harness()
    await env.on("ok")
    #expect(await env.run() == .succeeded(rows: 1))
    #expect(try await env.snapshots() == [
      Harness.snapshot("USD", 11_000, granted: 1_000, toppedUp: 10_000, available: true)
    ])
    let state = try await env.state()
    #expect(state.lastSuccessAt == Harness.fetchedAt)
    #expect(state.consecutiveFailures == 0)
    #expect(utf8Text(state.lastRaw ?? Data()).contains("\"total_balance\""))
    #expect(await env.records(.pollOk).first?.ctx["rows"] == .int(1))
  }

  @Test("balance cny: one snapshot per currency, sent amounts rounded half up once")
  func balanceTwoCurrencies() async throws {
    let env = try await Harness(currency: "CNY")
    await env.on("cny")
    #expect(await env.run() == .succeeded(rows: 2))
    #expect(try await env.snapshots() == [
      Harness.snapshot("CNY", 5_679, granted: 678, toppedUp: 5_001, available: true),
      Harness.snapshot("USD", 150, granted: 0, toppedUp: 150, available: true)
    ])
  }

  @Test("balance unavailable: the snapshot keeps is_available = false")
  func balanceUnavailable() async throws {
    let env = try await Harness()
    await env.on("unavailable")
    #expect(await env.run() == .succeeded(rows: 1))
    #expect(try await env.snapshots() == [Harness.snapshot("USD", 0, granted: 0, toppedUp: 0, available: false)])
  }

  @Test("a later poll adds a reading; a currency listed twice keeps its first entry; absent optionals are NULL")
  func laterReading() async throws {
    let env = try await Harness()
    await env.on("ok")
    #expect(await env.run() == .succeeded(rows: 1))
    env.date.set(Harness.now.addingTimeInterval(60))
    await env.transport.replace("GET", Harness.balancePath, OpenAIHarness.ok(
      #"{"is_available":true,"balance_infos":[{"currency":"usd","total_balance":"109.5"},"#
        + #"{"currency":"USD","total_balance":"1.00","granted_balance":null}]}"#
    ))
    #expect(await env.run() == .succeeded(rows: 1))
    #expect(try await env.snapshots().last == Harness.snapshot(
      "USD", 10_950, granted: nil, toppedUp: nil, available: true, ts: "2026-11-10T12:01:00.000Z"
    ))
    #expect(try await env.snapshots().count == 2)
  }

  @Test("an empty or malformed reading fails as decode: no row, schema drift logged, last_raw keeps the body")
  func balanceDecodeFailure() async throws {
    let env = try await Harness()
    await env.on(OpenAIHarness.ok(#"{"is_available":true,"balance_infos":[]}"#))
    #expect(await env.run() == .failed("decode"))
    #expect(try await env.snapshots().isEmpty)
    #expect(await env.records(.pollSchemaDrift).first?.ctx["missing_keys"] == .string("balance_infos"))
    #expect(await env.transport.calls.count == 1)
  }

  @Test("401 on a poll: auth failure, no retry, key not logged")
  func balance401() async throws {
    let env = try await Harness()
    await env.on("401")
    #expect(await env.run() == .failed("auth"))
    #expect(try await env.state().consecutiveFailures == 1)
    #expect(await env.records(.pollAuthFailed).count == 1)
    #expect(!(await env.allLines()).contains(env.key))
  }

  @Test("unknown keys are logged once per day")
  func unknownKeys() async throws {
    let env = try await Harness()
    await env.on(OpenAIHarness.ok(
      #"{"is_available":true,"extra":1,"balance_infos":[{"currency":"USD","total_balance":"1.00","note":"x"}]}"#
    ))
    #expect(await env.run() == .succeeded(rows: 1))
    #expect(await env.run() == .succeeded(rows: 1))
    let logged = await env.records(.pollUnknownKeys)
    #expect(logged.count == 1)
    #expect(logged.first?.ctx["keys"] == .string("balance_infos[].note,extra"))
  }

  @Test("DeepSeek has no usage, cost or keys endpoint (02): those polls answer their provider rule")
  func noOtherPolls() async throws {
    let env = try await Harness()
    let context = PollContext(accountID: env.account.id, key: env.key, cursor: nil,
                              window: DateInterval(start: Harness.now, end: Harness.now), transport: env.transport,
                              clock: env.clock)
    await #expect(throws: PollError.providerRule("deepseek_no_usage_api")) { try await env.adapter.pollUsage(context) }
    await #expect(throws: PollError.providerRule("deepseek_no_cost_api")) { try await env.adapter.pollCost(context) }
    await #expect(throws: PollError.providerRule("deepseek_no_keys_api")) { try await env.adapter.pollKeys(context) }
    // The scheduler never asks: the stored capabilities rule the jobs out.
    #expect(await env.run(.usage) == .skipped("deepseek_no_usage_api"))
    #expect(await env.transport.calls.isEmpty)
  }

  @Test("fixture mode serves DeepSeek's balance from the synthetic files")
  func fixtureRoutes() async throws {
    let transport = FixtureTransport(routes: FixtureTransport.knownRoutes, cases: ["deepseek/balance": "cny"])
    let adapter = DeepSeekAdapter(logPipeline: try StoreHarness().pipeline)
    let result = await adapter.probe(key: "fixture", transport: transport)
    #expect(result.humanMessage == nil)
    #expect(result.currency == .cny)
  }
}
