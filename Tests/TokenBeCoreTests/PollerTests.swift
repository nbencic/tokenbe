import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 3.4 Tests, `PollerTests`: the retry sequence on a `TestClock` with a seeded generator, the circuit
/// after three auth failures, decode without retry, and the `poll.*` events of 07.
@Suite struct PollerTests {
  typealias Harness = OpenAIHarness

  /// Lets `count` retry sleeps pass.
  static func pass(_ env: Harness, sleeps count: Int) async {
    for _ in 0..<count {
      await env.clock.waitForSleepers()
      env.clock.advance(by: .seconds(400))
    }
  }

  @Test("transport ×3 then ok: three poll.retry records with the policy's jittered delays, then poll.ok")
  func transientRetries() async throws {
    let env = try await Harness(seed: 42)
    let offline = StubTransport.Answer.failure(.urlError(URLError(.timedOut)))
    await env.on(Harness.usage, offline, offline, offline, .fixture(Harness.fixture("usage_completions.empty")))
    let run = Task { await env.run(.usage) }
    await Self.pass(env, sleeps: 3)
    #expect(await run.value == .succeeded(rows: 0))
    var rng = SeededRNG(seed: 42)
    let expected = (1...3).compactMap {
      RetryPolicy.nextDelay(attempt: $0, error: .transport(URLError(.timedOut)), using: &rng)
    }
    let retries = await env.records(.pollRetry)
    #expect(retries.map(\.ctx["delay_ms"]) == expected.map { .int(LogPipeline.milliseconds($0)) })
    #expect(retries.map(\.attempt) == [1, 2, 3])
    #expect(retries.allSatisfy { $0.acct == "openai" && $0.job == "usage" && $0.err?.type.contains("transport") == true })
    #expect(await env.records(.pollStart).count == 1 && env.clock.sleeperCount == 0)
  }

  @Test("transport ×4: the attempt fails after three retries with poll.failed {attempts: 4}")
  func retriesExhausted() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, .failure(.urlError(URLError(.timedOut))))
    let run = Task { await env.run(.usage) }
    await Self.pass(env, sleeps: 3)
    #expect(await run.value == .failed("transport"))
    #expect(await env.transport.calls.count == 4)
    let failed = try #require(await env.records(.pollFailed).first)
    #expect(failed.ctx["attempts"] == .int(4) && failed.lvl == .error)
    #expect(try await env.state(.usage).consecutiveFailures == 1)
  }

  @Test("429 with Retry-After 12: poll.rate_limited, one retry after 12 s, then ok")
  func rateLimited() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, "usage_completions.429", "usage_completions.empty")
    let run = Task { await env.run(.usage) }
    await env.clock.waitForSleepers()
    #expect(env.clock.deadlines == [.seconds(12)])
    env.clock.advance(by: .seconds(12))
    #expect(await run.value == .succeeded(rows: 0))
    #expect(await env.records(.pollRateLimited).first?.ctx["retry_after_s"] == .int(12))
    #expect(await env.records(.pollRetry).first?.ctx["delay_ms"] == .int(12_000))
  }

  @Test("429 twice: the attempt fails after its one retry")
  func rateLimitedTwice() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, "usage_completions.429")
    let run = Task { await env.run(.usage) }
    await Self.pass(env, sleeps: 1)
    #expect(await run.value == .failed("rate_limited"))
    #expect(await env.records(.pollRateLimited).count == 2)
  }

  @Test("auth ×3: no retries, poll.auth_failed each time, the circuit opens for 24 h; a success closes it")
  func circuit() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, "projects.401")
    for _ in 0..<3 { #expect(await env.run(.usage) == .failed("auth")) }
    #expect(await env.transport.calls.count == 3)
    #expect(await env.records(.pollAuthFailed).map(\.ctx["http_status"]) == [.int(401), .int(401), .int(401)])
    let opened = await env.records(.pollCircuitOpen)
    #expect(opened.count == 1)
    #expect(opened.first?.ctx["until"] == "2026-11-11T12:00:00.000Z")
    let state = try await env.state(.usage)
    #expect(state.circuitOpenUntil == "2026-11-11T12:00:00.000Z" && state.consecutiveFailures == 3)
    #expect(state.lastErrorMessage?.hasPrefix("HTTP 401: ") == true)
    #expect(state.lastErrorMessage?.contains("synthetic 401") == true)

    await env.transport.replace("GET", Harness.usage, .fixture(Harness.fixture("usage_completions.empty")))
    #expect(await env.run(.usage) == .succeeded(rows: 0))
    #expect(await env.records(.pollCircuitClose).count == 1)
    #expect(try await env.state(.usage).circuitOpenUntil == nil)
  }

  @Test("5xx is retried; decode is not")
  func decodeNoRetry() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, Harness.ok(#"{"data":"not a list"}"#))
    #expect(await env.run(.usage) == .failed("decode"))
    #expect(await env.transport.calls.count == 1)
    #expect(await env.records(.pollRetry).isEmpty)
    #expect(await env.records(.pollSchemaDrift).count == 1)
  }

  @Test("a job the capabilities do not allow is skipped with poll.provider_rule and no request")
  func providerRule() async throws {
    let env = try await Harness()
    #expect(await env.run(.balance) == .skipped("openai_no_balance_api"))
    #expect(await env.records(.pollProviderRule).first?.ctx["rule"] == "openai_no_balance_api")
    #expect(await env.transport.calls.isEmpty)
    #expect(try await env.state(.balance).lastAttemptAt == nil)
  }

  @Test("no Keychain item: keychain.missing, failure recorded, no request")
  func missingKey() async throws {
    let env = try await Harness()
    try await env.keys.delete(Harness.account.keychainRef)
    #expect(await env.run(.usage) == .failed("keychain"))
    #expect(await env.records(.keychainMissing).first?.acct == Harness.account.keychainRef)
    #expect(await env.transport.calls.isEmpty)
    #expect(try await env.state(.usage).lastErrorClass == "keychain")
  }

  /// An adapter whose usage page has two rows on one primary key, so V2 fails.
  struct DuplicateRowsAdapter: ProviderAdapter {
    let id = ProviderID.openai
    func probe(key: String, transport: any HTTPTransport) async -> ProbeResult {
      ProbeResult(capabilities: OpenAIAdapter.capabilities, currency: .usd)
    }
    func pollUsage(_ context: PollContext) async throws(PollError) -> UsagePage {
      let row = OpenAITests.usageRows[0]
      return UsagePage(rows: [row, row], nextCursor: nil, rawBody: "{}")
    }
  }

  @Test("V2 violated: poll.write_incomplete, poll.failed, nothing written (04 § Invariants)")
  func writeIncomplete() async throws {
    let env = try await Harness()
    let poller = Poller(store: env.repository, keyStore: env.keys, registry: ProviderRegistry(adapters: [DuplicateRowsAdapter()]),
                        transport: env.transport, clock: env.clock, logPipeline: env.store.pipeline, now: env.date.provider)
    #expect(await poller.runOnce(account: Harness.account, job: .usage) == .failed("store"))
    let record = try #require(await env.records(.pollWriteIncomplete).first)
    let tokens = OpenAITests.usageRows[0].classes.tokens
    #expect(record.ctx["expected"] == .int(Int(tokens * 2)) && record.ctx["written"] == .int(Int(tokens)))
    #expect(record.lvl == .error)
    #expect(await env.records(.pollFailed).count == 1)
    #expect(try await env.repository.fetchUsageBuckets(accountID: Harness.account.id).isEmpty)
  }

  @Test("each run logs poll.start then poll.ok with rows and duration; the key never reaches a record")
  func startAndOK() async throws {
    let env = try await Harness()
    await env.on(Harness.projects, "projects.ok")
    await env.on(Harness.apiKeys, "api_keys.ok")
    #expect(await env.run(.keys) == .succeeded(rows: 2))
    await env.store.pipeline.drain()
    let events = await env.store.sink.events().filter { $0.rawValue.hasPrefix("poll.") }
    #expect(events == [.pollStart, .pollOk])
    let success = try #require(await env.records(.pollOk).first)
    #expect(success.durMs != nil && success.ctx["cursor"] == .null && success.cat == .poll("openai"))
    #expect(!(await env.allLines()).contains(env.key))
  }

  @Test("a cancelled job records nothing and returns skipped")
  func cancelled() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, .failure(.urlError(URLError(.timedOut))))
    let run = Task { await env.run(.usage) }
    await env.clock.waitForSleepers()
    run.cancel()
    #expect(await run.value == .skipped("cancelled"))
    #expect(try await env.state(.usage).consecutiveFailures == 0)
  }
}
