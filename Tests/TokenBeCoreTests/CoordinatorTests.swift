import Foundation
import Testing
@testable import TokenBeCore

/// 14 § Stage 4.1 Tests, `CoordinatorTests`, and 04 § Definition of done: overlap → one network call and one
/// `sched.overlap_skipped`; pause/resume per account; account add/remove; offline; overrun; refresh vs. the circuit;
/// settings changes; the state stream.
@Suite struct CoordinatorTests {
  typealias Harness = SchedulerHarness

  static let timeout = StubTransport.Answer.failure(.urlError(URLError(.timedOut)))
  static let empty = StubTransport.Answer.fixture(OpenAIHarness.fixture("usage_completions.empty"))

  @Test("04 DoD: two concurrent run(usage) on one poller → one network call, one sched.overlap_skipped")
  func pollerOverlap() async throws {
    let env = try await OpenAIHarness()
    await env.on(OpenAIHarness.usage, Self.timeout, Self.empty)
    let poller = AccountPoller(account: OpenAIHarness.account, runner: env.poller, logPipeline: env.store.pipeline)
    let first = Task { await poller.run(.usage) }
    await env.clock.waitForSleepers()
    #expect(await poller.inFlight == [.usage])
    #expect(await poller.run(.usage) == .skipped("overlap"))
    #expect(await env.transport.calls.count == 1)
    let overlaps = await env.records(.schedOverlapSkipped)
    #expect(overlaps.count == 1 && overlaps.first?.job == "usage" && overlaps.first?.acct == "openai")
    #expect(overlaps.first?.lvl == .warn)
    env.clock.advance(by: .seconds(60))
    #expect(await first.value == .succeeded(rows: 0))
    #expect(await poller.inFlight.isEmpty)
  }

  @Test("refreshNow while usage is in flight: no second request, one sched.overlap_skipped; keys runs again")
  func refreshOverlap() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, Self.timeout, Self.empty)
    await env.start()
    let coordinator = env.coordinator
    await env.usageRetrying()
    await eventually("keys done") { await coordinator.runningKeys.map(\.job) == [.usage] }
    await env.coordinator.refreshNow()
    await eventually("keys ran again") { await env.calls(OpenAIHarness.projects) == 2 }
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    #expect(await env.records(.schedOverlapSkipped).map(\.job) == ["usage"])
    env.advance(by: .seconds(60))
    await env.settled(next: 360)
    await env.stop()
  }

  @Test("a new account is polled at once; a removed one is dropped and its running job cancelled")
  func addRemove() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, Self.timeout, Self.empty)
    await env.coordinator.sync(SummaryInputs(accounts: []))
    await env.coordinator.start()
    #expect(await env.coordinator.accountIDs.isEmpty)
    await env.resync()
    let coordinator = env.coordinator
    await env.usageRetrying()
    #expect(await env.calls(OpenAIHarness.projects) == 1)
    await env.coordinator.sync(SummaryInputs(accounts: []))
    await eventually("the account is gone") { await coordinator.runningKeys.isEmpty }
    #expect(await env.coordinator.schedule.entries.isEmpty)
    await eventually("the cancelled retry sleep is gone") { env.clock.deadlines == [.seconds(86_400)] }
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    #expect(await env.records(.pollFailed).isEmpty)
    await env.stop()
  }

  @Test("stop(account) awaits its running jobs, and a later sync does not bring the account back")
  func stopBeforeRemove() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, Self.timeout, Self.empty)
    await env.start()
    await env.usageRetrying()
    await env.coordinator.stop(env.account.id)
    #expect(await env.coordinator.runningKeys.isEmpty)
    await env.resync()
    #expect(await env.coordinator.accountIDs.isEmpty)
    await env.coordinator.sync(SummaryInputs(accounts: []))
    await env.resync()
    #expect(await env.coordinator.accountIDs == [env.account.id], "forgotten once the store dropped it")
    await env.stop()
  }

  @Test("account.paused: due jobs are skipped (paused); unpausing runs them at once")
  func accountPaused() async throws {
    let env = try await Harness()
    await env.answerOK()
    var paused = env.account
    paused.paused = true
    try await env.env.repository.updateAccount(paused)
    await env.start()
    await env.settled(next: 300)
    #expect(await env.calls(OpenAIHarness.usage) == 0)
    #expect(await env.reasons() == ["keys=paused", "usage=paused"])
    paused.paused = false
    try await env.env.repository.updateAccount(paused)
    await env.resync()
    await env.settled(next: 300)
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    #expect(await env.calls(OpenAIHarness.projects) == 1)
    await env.stop()
  }

  @Test("offline: due jobs are skipped (offline); back online they run at once")
  func offline() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    env.network.set(online: false)
    let coordinator = env.coordinator
    await eventually("offline") { await coordinator.online == false }
    env.advance(by: .seconds(300))
    await env.settled(next: 600)
    #expect(await env.reasons() == ["usage=offline"])
    env.network.set(online: true)
    await eventually("the held-back usage ran on reconnect") { await env.calls(OpenAIHarness.usage) == 2 }
    await env.settled(next: 600)
    await env.stop()
  }

  @Test("a job running past 2 × its interval is cancelled with sched.overrun {phase} and retried at the next tick")
  func overrun() async throws {
    var settings = ScheduleSettings.defaults
    settings.usageIntervalOpenAIS = 60
    let env = try await Harness(settings: settings)
    await env.answerOK()
    // Retry-After 300 keeps the attempt asleep well past the 120 s limit.
    await env.env.transport.replace("GET", OpenAIHarness.usage,
                                    OpenAIHarness.status(429, "{}", headers: ["Retry-After": "300"]), Self.empty)
    await env.start()
    let clock = env.clock
    await clock.waitUntil("the retry sleep and the overrun limit") {
      $0.deadlines.contains(.seconds(300)) && $0.deadlines.contains(.seconds(120))
    }
    env.advance(by: .seconds(120))
    await env.settled(next: 180)
    let overrun = try #require(await env.records(.schedOverrun).first)
    #expect(overrun.lvl == .error && overrun.job == "usage" && overrun.ctx["phase"] == .string("fetch"))
    #expect(overrun.durMs == 120_000)
    #expect(await env.calls(OpenAIHarness.usage) == 2, "the retry at the next tick")
    await env.stop()
  }

  @Test("refreshNow does not bypass an open circuit (04: polls stop until the key is re-tested)")
  func refreshKeepsCircuit() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    let until = DBTime.string(env.env.date.date.addingTimeInterval(86_400))
    try await env.env.database.write("circuit") { db in
      try db.execute(sql: "UPDATE poll_state SET circuit_open_until = ? WHERE job = 'usage'", arguments: [until])
    }
    await env.resync()
    await env.coordinator.refreshNow(env.account.id)
    await env.settled(next: 300)
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    #expect(await env.reasons() == ["usage=circuit_open"])
    _ = try await env.env.repository.resetCircuit(accountID: env.account.id)
    await env.resync()
    await env.settled(next: 300)
    #expect(await env.calls(OpenAIHarness.usage) == 2, "a reset circuit runs at once")
    await env.stop()
  }

  @Test("an interval override from the account row wins, clamped to 09's range with app.settings_changed")
  func override() async throws {
    let env = try await Harness()
    await env.answerOK()
    var account = env.account
    account.intervalOverrideJson = #"{"usage":30,"keys":900}"#
    try await env.env.repository.updateAccount(account)
    await env.start()
    await env.settled(next: 60)
    #expect(await env.entry(.usage)?.interval == .seconds(60))
    #expect(await env.entry(.keys)?.interval == .seconds(900))
    let repaired = try #require(await env.records(.appSettingsChanged).first)
    #expect(repaired.ctx["clamped"] == .bool(true) && repaired.ctx["new"] == .string(#"{"keys":900,"usage":60}"#))
    await env.stop()
  }

  @MainActor
  @Test("follow(settings): an interval change reaches the coordinator and pulls the next run in")
  func followsSettings() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    let settings = Settings(store: InMemorySettingsStore())
    let follower = env.coordinator.follow(settings)
    settings.pollUsageIntervalOpenAIS = 60
    await env.settled(next: 60)
    settings.pollPausedUntil = env.env.date.date.addingTimeInterval(3600).timeIntervalSince1970
    let coordinator = env.coordinator
    await eventually("paused") { await coordinator.settings.pausedUntil != nil }
    follower.cancel()
    await env.stop()
  }

  @Test("the state stream reports in-flight jobs and the pause")
  func states() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, Self.timeout, Self.empty)
    let recorder = StreamRecorder(env.coordinator.states)
    await env.start()
    await env.usageRetrying()
    await eventually("usage in flight") { await recorder.last?.inFlightCount == 1 }
    env.advance(by: .seconds(60))
    await eventually("idle") { await recorder.last?.inFlightCount == 0 }
    var settings = ScheduleSettings.defaults
    let until = env.env.date.date.addingTimeInterval(3600)
    settings.pausedUntil = until
    await env.coordinator.update(settings)
    await eventually("paused") { await recorder.last?.pausedUntil == until }
    #expect(await recorder.last?.isPaused == true)
    #expect(await recorder.last?.isOnline == true)
    await env.stop()
  }

  @Test("interval overrides: parse, clamp, ignore cost, serialize sorted")
  func overrideParsing() {
    #expect(IntervalOverride.parse(nil, provider: .openai) == .init(override: IntervalOverride(), repaired: false))
    #expect(IntervalOverride.parse("not json", provider: .openai).repaired)
    let parsed = IntervalOverride.parse(#"{"usage":99999,"cost":5,"keys":1200}"#, provider: .openai)
    #expect(parsed.override.seconds == [.usage: 3600, .keys: 1200] && parsed.repaired)
    #expect(parsed.override.json() == #"{"keys":1200,"usage":3600}"#)
    #expect(IntervalOverride().json() == nil)
  }

  @Test("intervals: 09 keys per job and provider, × the Low Power multiplier; cost has no minute cadence")
  func intervals() {
    let settings = ScheduleSettings.defaults
    let none = IntervalOverride()
    #expect(Job.usage.interval(for: .openai, settings: settings, override: none, lowPower: false) == .seconds(300))
    #expect(Job.usage.interval(for: .anthropic, settings: settings, override: none, lowPower: true) == .seconds(240))
    #expect(Job.usage.interval(for: .deepseek, settings: settings, override: none, lowPower: false) == nil)
    #expect(Job.balance.interval(for: .xai, settings: settings, override: none, lowPower: false) == .seconds(60))
    #expect(Job.keys.interval(for: .openrouter, settings: settings, override: none, lowPower: false) == .seconds(3600))
    #expect(Job.cost.interval(for: .openai, settings: settings, override: none, lowPower: false) == nil)
    #expect(Job.minuteCadence == [.usage, .balance, .keys])
  }
}
