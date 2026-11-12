import Foundation
import Testing
@testable import TokenBeCore

/// `PollCoordinator` inputs beyond `CoordinatorTests` (PM-0.5-2): unreadable capabilities, the store's observation,
/// and small loop rules; 4.2's state additions (next runs, Low Power) and the DEBUG offline monitor.
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

  @Test("the state stream carries each job's next run on the wall clock, and Low Power (4.2)")
  func nextDueAndLowPower() async throws {
    let env = try await Harness()
    await env.answerOK()
    let recorder = StreamRecorder(env.coordinator.states)
    let start = env.env.date.date
    await env.start()
    let id = env.account.id
    // After the first runs: usage again in 300 s, keys in 3600 s, on the wall clock; balance does not apply.
    await eventually("next runs after the first polls") {
      let due = await recorder.last?.nextDue[id]
      return due?[.usage] == start.addingTimeInterval(300) && due?[.keys] == start.addingTimeInterval(3600)
    }
    #expect(await recorder.last?.nextDue[id]?[.balance] == nil)
    #expect(await recorder.last?.isLowPower == false)
    await env.coordinator.setLowPower(true)
    await eventually("Low Power reported") { await recorder.last?.isLowPower == true }
    await env.stop()
  }

  @Test("FixedNetworkMonitor (DEBUG offline seam, Q-036): the coordinator reports offline and skips as offline")
  func fixedOffline() async throws {
    let env = try await Harness()
    await env.answerOK()
    let recorder = StreamRecorder(env.coordinator.states)
    await env.coordinator.follow(FixedNetworkMonitor(online: false))
    await eventually("offline reported") { await recorder.last?.isOnline == false }
    await env.coordinator.sync(await env.inputs())
    await env.coordinator.start()
    await eventually("usage skipped as offline") { await env.reasons().contains("usage=offline") }
    #expect(await env.calls(OpenAIHarness.usage) == 0)
    #expect(FixedNetworkMonitor(online: true).status == NetworkStatus(online: true, interface: "other"))
    await env.stop()
  }
}
