import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.5 Tests, `AccountLifecycleTests`: create and remove clean up after themselves; the probe timeout;
/// replace and test reset the circuit; startup step 3 finds missing Keychain items; the onboarding anchor.
@Suite struct AccountLifecycleTests {
  typealias Harness = OpenAIHarness

  static func lifecycle(_ env: Harness, keyStore: (any KeyStore)? = nil,
                        transport: (any HTTPTransport)? = nil) -> AccountLifecycle {
    AccountLifecycle(repository: env.repository, keyStore: keyStore ?? env.keys,
                     registry: ProviderRegistry(adapters: [env.adapter]), transport: transport ?? env.transport,
                     clock: env.clock, logPipeline: env.store.pipeline, now: env.date.provider)
  }

  /// A harness whose database has no account yet (onboarding creates it).
  static func empty() async throws -> Harness {
    let env = try await Harness()
    try await env.repository.deleteAccount(id: Harness.account.id)
    return env
  }

  static func passingProbe(_ env: Harness) async {
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    await env.on(Harness.usage, "usage_completions.empty")
    await env.on(Harness.costs, "costs.ok")
  }

  @Test("create after a passed probe: Keychain item, account, 4 poll_state rows, discovered keys")
  func create() async throws {
    let env = try await Self.empty()
    await Self.passingProbe(env)
    let keys = InMemoryKeyStore()
    let lifecycle = Self.lifecycle(env, keyStore: keys)
    let probe = await lifecycle.probe(.openai, key: " \(env.key)\n")
    #expect(probe.humanMessage == nil)
    let account = try await lifecycle.create(.openai, label: "  ", key: env.key, probe: probe)
    #expect(account.provider == "openai" && account.keychainRef == "openai" && account.label == "OpenAI")
    #expect(account.balanceMode == "anchored" && account.currency == "USD")
    #expect(try Capabilities.decode(json: account.capabilities) == OpenAIAdapter.capabilities)
    #expect(account.id.count == 36 && account.id.dropFirst(14).first == "7", "UUIDv7")
    #expect(account.createdAt == "2026-11-10T12:00:00.000Z")
    #expect(try await keys.get("openai") == env.key)
    #expect(try await env.repository.fetchAccounts() == [account])
    for job in Job.allCases {
      #expect(try await env.repository.fetchPollState(accountID: account.id, job: job) != nil)
    }
    #expect(try await env.repository.fetchProviderKeys(accountID: account.id).count == 2)
  }

  @Test("a refused insert deletes the Keychain item again")
  func createRollsBack() async throws {
    let env = try await Harness()   // already has an OpenAI account: UNIQUE (provider)
    await Self.passingProbe(env)
    let keys = InMemoryKeyStore()
    let lifecycle = Self.lifecycle(env, keyStore: keys)
    let probe = await lifecycle.probe(.openai, key: env.key)
    await #expect(throws: StoreError.self) { try await lifecycle.create(.openai, label: "x", key: env.key, probe: probe) }
    #expect(await keys.refs.isEmpty)
    #expect(try await env.repository.fetchAccounts() == [Harness.account])
  }

  @Test("remove deletes the account (cascade), the Keychain item and the provider's templated settings")
  @MainActor
  func remove() async throws {
    let env = try await Self.empty()
    await Self.passingProbe(env)
    let keys = InMemoryKeyStore()
    let lifecycle = Self.lifecycle(env, keyStore: keys)
    let account = try await lifecycle.create(.openai, label: "Work", key: env.key,
                                             probe: await lifecycle.probe(.openai, key: env.key))
    let settings = Settings(store: InMemorySettingsStore())
    settings.setPopoverExpanded(.openai, true)
    settings.setSnoozedUntil(.openai, 99)
    try await lifecycle.remove(account, settings: settings)
    #expect(try await env.repository.fetchAccounts().isEmpty)
    #expect(try await env.repository.fetchPollState(accountID: account.id, job: .usage) == nil)
    #expect(try await env.repository.fetchProviderKeys(accountID: account.id).isEmpty)
    #expect(await keys.refs.isEmpty)
    #expect(settings.value(SettingsKey.expanded(.openai)) == .bool(false))
    #expect(settings.value(SettingsKey.snoozedUntil(.openai)) == .double(0))
  }

  @Test("the probe gives up after 10 s with the unreachable message")
  func probeTimeout() async throws {
    let env = try await Self.empty()
    let lifecycle = Self.lifecycle(env, transport: HangingTransport())
    let probe = Task { await lifecycle.probe(.openai, key: env.key) }
    await env.clock.waitForSleepers()
    #expect(env.clock.deadlines == [.seconds(10)])
    env.clock.advance(by: .seconds(10))
    #expect(await probe.value.humanMessage == "Could not reach OpenAI. Check your internet connection and try again.")
    #expect(await env.records(.pollFailed).first?.ctx["timeout_s"] == .int(10))
  }

  @Test("Test with a stored key resets an open circuit (04) and logs poll.circuit_close")
  func testResetsCircuit() async throws {
    let env = try await Harness()
    for _ in 0..<3 {
      _ = try await env.repository.recordPollFailure(
        accountID: Harness.account.id, job: .usage, at: Harness.now,
        failure: PollFailure(errorClass: "auth", message: "m", countsTowardCircuit: true),
        circuit: CircuitRule(threshold: 3, until: Harness.now.addingTimeInterval(86400)))
    }
    await Self.passingProbe(env)
    let result = await Self.lifecycle(env).test(Harness.account)
    #expect(result.humanMessage == nil)
    let state = try await env.state(.usage)
    #expect(state.circuitOpenUntil == nil && state.consecutiveFailures == 0)
    #expect(await env.records(.pollCircuitClose).map(\.job) == ["usage"])
  }

  @Test("Test with no Keychain item: keychain.missing and the key-missing message, no request")
  func testMissingKey() async throws {
    let env = try await Harness()
    let result = await Self.lifecycle(env, keyStore: InMemoryKeyStore()).test(Harness.account)
    #expect(result.humanMessage == CoreStrings.keyMissing)
    #expect(await env.records(.keychainMissing).count == 1)
    #expect(await env.transport.calls.isEmpty)
  }

  @Test("replaceKey stores the new key and resets the circuit")
  func replaceKey() async throws {
    let env = try await Harness()
    _ = try await env.repository.recordPollFailure(
      accountID: Harness.account.id, job: .keys, at: Harness.now,
      failure: PollFailure(errorClass: "auth", message: "m", countsTowardCircuit: true),
      circuit: CircuitRule(threshold: 1, until: Harness.now.addingTimeInterval(86400)))
    await Self.passingProbe(env)
    let lifecycle = Self.lifecycle(env)
    let newKey = "sk-" + "admin-" + String(repeating: "Wv4", count: 14)
    try await lifecycle.replaceKey(Harness.account, key: newKey, probe: await lifecycle.probe(.openai, key: newKey))
    #expect(try await env.keys.get(Harness.account.keychainRef) == newKey)
    #expect(try await env.state(.keys).circuitOpenUntil == nil)
    #expect(try await env.repository.fetchProviderKeys(accountID: Harness.account.id).count == 2)
  }

  @Test("startup step 3: an account without a Keychain item is missing and logged; a read failure is not")
  func missingKeys() async throws {
    let env = try await Harness()
    let keys = InMemoryKeyStore()
    let lifecycle = Self.lifecycle(env, keyStore: keys)
    #expect(await lifecycle.missingKeys([Harness.account]) == [Harness.account.keychainRef])
    #expect(await env.records(.keychainMissing).first?.acct == Harness.account.keychainRef)
    await keys.fail(.read, with: .accessDenied(op: .read, status: -25308))
    #expect(await lifecycle.missingKeys([Harness.account]).isEmpty)
    await keys.fail(.read, with: nil)
    try await keys.set(Harness.account.keychainRef, secret: env.key)
    #expect(await lifecycle.missingKeys([Harness.account]).isEmpty)
  }

  @Test("the onboarding anchor is a user ledger_event(kind=anchor) and logs ledger.anchor_set")
  func anchor() async throws {
    let env = try await Harness()
    try await Self.lifecycle(env).setAnchor(Harness.account, cents: 20_000)
    let rows = try await env.database.read { db in try LedgerEventRecord.fetchAll(db) }
    #expect(rows.count == 1)
    #expect(rows.first?.kind == "anchor" && rows.first?.amountCents == 20_000 && rows.first?.source == "user")
    #expect(rows.first?.currency == "USD" && rows.first?.ts == "2026-11-10T12:00:00.000Z")
    let record = try #require(await env.records(.ledgerAnchorSet).first)
    #expect(record.ctx["amount_cents"] == .int(20_000) && record.ctx["source"] == "user" && record.acct == "openai")
  }
}

/// A transport that never answers until cancelled, for the probe timeout.
struct HangingTransport: HTTPTransport {
  func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
    do {
      try await Task.sleep(for: .seconds(3600))
    } catch {
      throw .urlError(URLError(.cancelled))
    }
    throw .urlError(URLError(.timedOut))
  }
}

/// 3.5's small Core additions: UUIDv7, typed amounts, fixture cases, `KeyStore.contains`, summary freshness.
@Suite struct AccountSupportTests {
  @Test("UUIDv7: version 7, RFC variant, time-ordered as text")
  func uuidv7() {
    var rng = SeededRNG(seed: 3)
    let early = UUIDv7.make(at: Date(timeIntervalSince1970: 1_794_312_000), using: &rng)
    let late = UUIDv7.make(at: Date(timeIntervalSince1970: 1_794_312_001), using: &rng)
    #expect(early.count == 36 && early < late)
    let hex = Array(early.replacingOccurrences(of: "-", with: ""))
    #expect(hex[12] == "7" && "89ab".contains(hex[16]))
    #expect(early.hasPrefix(String(format: "%08x", 1_794_312_000_000 >> 16)))
  }

  @Test("typed amounts → cents (en_US and de_DE), half up; junk and negatives → nil")
  func cents() {
    let posix = Locale(identifier: "en_US_POSIX")
    #expect(Formatters.cents(fromInput: "200", locale: posix) == 20_000)
    #expect(Formatters.cents(fromInput: " 12.345 ", locale: posix) == 1_235)
    #expect(Formatters.cents(fromInput: "1,234.5", locale: Locale(identifier: "en_US")) == 123_450)
    #expect(Formatters.cents(fromInput: "1.234,5", locale: Locale(identifier: "de_DE")) == 123_450)
    #expect(Formatters.cents(fromInput: "", locale: posix) == nil)
    #expect(Formatters.cents(fromInput: "abc", locale: posix) == nil)
    #expect(Formatters.cents(fromInput: "-3", locale: posix) == nil)
  }

  @Test("fixture cases parse from TOKENBE_TEST_FIXTURE_CASES text and reach FixtureTransport")
  func fixtureCases() async throws {
    #expect(Transports.cases(from: "openai/projects=401, openai/costs=403,bad,=x") ==
            ["openai/projects": "401", "openai/costs": "403"])
    #expect(Transports.cases(from: nil).isEmpty)
    let transport = Transports.make(fixtureMode: true, version: "t", cases: ["openai/projects": "401"])
    let url = try #require(URL(string: "https://api.openai.com/v1/organization/projects?limit=100"))
    #expect(try await transport.send(HTTPRequest(url: url)).status == 401)
  }

  @Test("contains reports an item without reading it")
  func contains() async throws {
    let keys = InMemoryKeyStore(["a": "secret"])
    #expect(try await keys.contains("a"))
    #expect(try await !keys.contains("b"))
  }

  @Test("summaries take freshness and the circuit from poll_state, and needsKey from missing refs")
  func summaryInputs() {
    let account = FixtureDBBuilder.account()
    let inputs = SummaryInputs(accounts: [account], pollStates: [
      PollStateSummary(accountId: account.id, job: "usage", lastSuccessAt: "2026-11-10T11:00:00.000Z"),
      PollStateSummary(accountId: account.id, job: "keys", circuitOpenUntil: "2026-11-11T12:00:00.000Z"),
      PollStateSummary(accountId: account.id, job: "cost")
    ])
    let summary = AccountSummaryBuilder.summaries(from: inputs, missingKeys: [account.keychainRef]).first
    #expect(summary?.lastSuccessAt == DBTime.date("2026-11-10T11:00:00.000Z"))
    #expect(summary?.freshness[.cost] == .some(nil))
    #expect(summary?.circuitOpenUntil == DBTime.date("2026-11-11T12:00:00.000Z"))
    #expect(summary?.needsKey == true)
    #expect(AccountSummaryBuilder.summaries(from: SummaryInputs(accounts: [account])).first?.lastSuccessAt == nil)
  }
}

/// `AccountLifecycle`'s refusals (PM-0.5-2): no adapter, an unknown provider row, an unreadable key, and a passed
/// test whose circuit reset cannot be written.
@Suite struct AccountLifecycleEdgeTests {
  typealias Harness = OpenAIHarness

  @Test("probe for a provider without an adapter, or test of an unknown provider row: unrecognized, no request")
  func noAdapter() async throws {
    let env = try await Harness()
    let lifecycle = AccountLifecycleTests.lifecycle(env)
    #expect(await lifecycle.probe(.xai, key: "x").humanMessage == CoreStrings.unexpectedResponse("xAI"))
    var odd = Harness.account
    odd.provider = "gemini"
    #expect(await lifecycle.test(odd).humanMessage == CoreStrings.unexpectedResponse("gemini"))
    #expect(await env.transport.calls.isEmpty)
  }

  @Test("test with a key that cannot be read: the key-missing message, no request")
  func keyUnreadable() async throws {
    let env = try await Harness()
    await env.keys.fail(.read, with: .failed(op: .read, status: -25_300))
    let result = await AccountLifecycleTests.lifecycle(env).test(Harness.account)
    #expect(result.humanMessage == CoreStrings.keyMissing)
    #expect(await env.transport.calls.isEmpty)
  }

  @Test("a passed test whose circuit reset fails logs ui.error and still reports the pass")
  func resetFails() async throws {
    let env = try await Harness()
    await AccountLifecycleTests.passingProbe(env)
    try env.database.close()
    let result = await AccountLifecycleTests.lifecycle(env).test(Harness.account)
    #expect(result.humanMessage == nil)
    #expect(await env.records(.uiError).first?.msg == "circuit not reset")
  }
}
