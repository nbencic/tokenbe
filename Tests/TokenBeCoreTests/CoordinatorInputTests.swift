import Foundation
import Testing
@testable import TokenBeCore

/// `PollCoordinator` inputs beyond `CoordinatorTests` (PM-0.5-2): unreadable capabilities, the store's observation,
/// and small loop rules.
@Suite struct CoordinatorInputTests {
  typealias Harness = SchedulerHarness

  @Test("unreadable capabilities: the account runs no job and poll.failed is logged once")
  func unreadableCapabilities() async throws {
    let env = try await Harness()
    var account = env.account
    account.capabilities = "{"
    await env.coordinator.sync(SummaryInputs(accounts: [account]))
    await env.coordinator.sync(SummaryInputs(accounts: [account]))
    #expect(await env.coordinator.schedule.entries.isEmpty)
    #expect(await env.records(.pollFailed).map(\.msg) == ["account capabilities unreadable"])
  }

  @Test("follow(inputs): the store's observation brings the account in and polls it")
  func followsStore() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.coordinator.follow(env.env.repository.observeSummaryInputs())
    await env.coordinator.start()
    await env.settled(next: 300)
    #expect(await env.coordinator.accountIDs == [env.account.id])
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    await env.stop()
  }

  @Test("an override naming no job is repaired; a skipped outcome waits one interval; keys describe themselves")
  func smallRules() {
    #expect(IntervalOverride.parse(#"{"weekly":60}"#, provider: .openai).repaired)
    var loop = SchedulerLoop<TestClock.Instant>()
    let key = SchedulerLoop<TestClock.Instant>.Key(accountID: "a", job: .keys)
    loop.upsert(key, interval: .seconds(600), at: TestClock.Instant(offset: .zero))
    loop.completed(key, outcome: .skipped("overlap"), at: TestClock.Instant(offset: .seconds(10)))
    #expect(loop.entries[key]?.nextDue == TestClock.Instant(offset: .seconds(610)))
    #expect("\(key)" == "a/keys")
  }
}
