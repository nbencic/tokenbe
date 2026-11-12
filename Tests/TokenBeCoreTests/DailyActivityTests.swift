import Foundation
import Synchronization
import Testing
@testable import TokenBeCore

/// 14 § Stage 4.3 Tests, `DailyActivityTests`: a failing step does not stop later steps; steps run in registry order;
/// the weekly gate (every 7th run) and its retry; overlapping runs; the `cost polls` step's skips and failures.
@Suite struct DailyActivityTests {
  struct Broken: Error {}

  /// Records the order steps ran in.
  final class Trace: Sendable {
    let names = Mutex<[String]>([])
    func add(_ name: String) { names.withLock { $0.append(name) } }
    var all: [String] { names.withLock { $0 } }
  }

  static func harness() -> (LogPipeline, CapturingLogSink) {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], version: "test")
    pipeline.startConsumer()
    return (pipeline, sink)
  }

  static func step(_ name: String, _ trace: Trace, gate: DailyStep.Gate = .everyRun, fails: Bool = false) -> DailyStep {
    DailyStep(name, gate: gate) { _ in
      trace.add(name)
      if fails { throw Broken() }
    }
  }

  @Test("steps run in registry order; one failing does not stop later ones; start/end and per-step durations logged")
  func orderAndFailure() async {
    let (pipeline, sink) = Self.harness()
    let trace = Trace()
    let activity = DailyActivity(steps: [Self.step("cost polls", trace), Self.step("db backup", trace, fails: true)],
                                 logPipeline: pipeline)
    await activity.register(Self.step("incremental_vacuum", trace))
    #expect(await activity.stepNames == ["cost polls", "db backup", "incremental_vacuum"])
    let summary = await activity.run(runNumber: 1)
    #expect(trace.all == ["cost polls", "db backup", "incremental_vacuum"])
    #expect(summary == DailyActivity.Summary(runNumber: 1, ran: ["cost polls", "incremental_vacuum"],
                                             failed: ["db backup"], skipped: []))
    await pipeline.drain()
    let records = await sink.records
    #expect(records.map(\.evt) == [.schedDailyStart, .schedDailyStepFailed, .schedDailyEnd])
    #expect(records[1].lvl == .error && records[1].ctx["step"] == "db backup" && records[1].err?.type == "Broken")
    let end = records[2]
    #expect(end.lvl == .warn, "a failed step makes the end record a warning")
    #expect(end.ctx["steps_ok"] == .int(2) && end.ctx["steps_failed"] == .int(1) && end.ctx["run"] == .int(1))
    #expect(end.ctx["cost_polls_ms"] != nil && end.ctx["db_backup_ms"] != nil && end.ctx["incremental_vacuum_ms"] != nil)
    #expect(end.durMs != nil)
  }

  @Test("a clean run ends at info")
  func cleanRun() async {
    let (pipeline, sink) = Self.harness()
    let activity = DailyActivity(steps: [Self.step("db backup", Trace())], logPipeline: pipeline)
    #expect(await activity.run(runNumber: 3)?.failed == [])
    await pipeline.drain()
    #expect(await sink.records.last?.lvl == .info)
  }

  @Test("weekly gate: the integrity check runs on every 7th run; a failure is retried at the next run only")
  func weeklyGate() async {
    let trace = Trace()
    let failing = Mutex(true)
    let integrity = DailyStep("weekly integrity_check", gate: .everyNthRun(7)) { run in
      trace.add("integrity \(run)")
      if failing.withLock({ $0 }) { throw Broken() }
    }
    // Every activity gets a test pipeline: the global `Log` belongs to `LogFacadeTests`.
    let activity = DailyActivity(steps: [integrity], logPipeline: Self.harness().0)
    for run in 1...6 {
      #expect(await activity.run(runNumber: run)?.skipped == ["weekly integrity_check"])
    }
    #expect(await activity.run(runNumber: 7)?.failed == ["weekly integrity_check"])
    failing.withLock { $0 = false }
    #expect(await activity.run(runNumber: 8)?.ran == ["weekly integrity_check"], "retried at the next activity")
    #expect(await activity.run(runNumber: 9)?.skipped == ["weekly integrity_check"], "then back to the gate")
    #expect(await activity.run(runNumber: 14)?.ran == ["weekly integrity_check"])
    #expect(trace.all == ["integrity 7", "integrity 8", "integrity 14"])
  }

  @Test("a run requested while one is running is skipped and logged (sched.overlap_skipped, job daily)")
  func overlap() async {
    let (pipeline, sink) = Self.harness()
    let release = Mutex<CheckedContinuation<Void, Never>?>(nil)
    let started = Mutex(false)
    let slow = DailyStep("db backup") { _ in
      await withCheckedContinuation { continuation in
        release.withLock { $0 = continuation }
        started.withLock { $0 = true }
      }
    }
    let activity = DailyActivity(steps: [slow], logPipeline: pipeline)
    let first = Task { await activity.run(runNumber: 1) }
    await eventually("the first run is inside its step") { started.withLock { $0 } }
    #expect(await activity.run(runNumber: 1) == nil)
    release.withLock { $0?.resume() }
    #expect(await first.value?.ran == ["db backup"])
    await pipeline.drain()
    let skipped = await sink.records.filter { $0.evt == .schedOverlapSkipped }
    #expect(skipped.count == 1 && skipped.first?.job == "daily")
  }

  @Test("durations: step names become ctx keys; milliseconds from a Duration")
  func helpers() {
    #expect(DailyActivity.durationKey("weekly integrity_check") == "weekly_integrity_check_ms")
    #expect(DailyActivity.milliseconds(.milliseconds(1_234)) == 1_234)
  }

  // MARK: - cost polls

  static func costPolls(_ env: OpenAIHarness, paused: Bool = false) -> CostPolls {
    CostPolls(store: env.repository, poller: env.poller, isPaused: { paused }, logPipeline: env.store.pipeline,
              now: env.date.provider)
  }

  @Test("cost polls: an account with the cost capability runs its cost job once")
  func costPollRuns() async throws {
    let env = try await OpenAIHarness()
    await env.on(OpenAIHarness.costs, "costs.ok")
    try await Self.costPolls(env).run()
    #expect(try await env.state(.cost).lastSuccessAt == "2026-11-10T12:00:00.000Z")
    #expect(await env.records(.pollOk).contains { $0.job == "cost" })
  }

  @Test("cost polls: a failed poll fails the step (retried next activity)")
  func costPollFails() async throws {
    let env = try await OpenAIHarness()
    await env.on(OpenAIHarness.costs, "costs.403")
    await #expect(throws: CostPolls.Failed(providers: ["openai"])) { try await Self.costPolls(env).run() }
    #expect(CostPolls.Failed(providers: ["openai"]).description == "cost poll failed for openai")
  }

  @Test("cost polls skip: the global pause, a paused account, an open circuit, no cost capability")
  func costPollSkips() async throws {
    let env = try await OpenAIHarness()
    try await Self.costPolls(env, paused: true).run()
    var account = OpenAIHarness.account
    account.paused = true
    try await env.repository.updateAccount(account)
    try await Self.costPolls(env).run()
    account.paused = false
    try await env.repository.updateAccount(account)
    let circuit = CircuitRule(threshold: 1, until: OpenAIHarness.now.addingTimeInterval(3600))
    _ = try await env.repository.recordPollFailure(
      accountID: account.id, job: .cost, at: OpenAIHarness.now,
      failure: PollFailure(errorClass: "auth", message: "m", countsTowardCircuit: true), circuit: circuit)
    try await Self.costPolls(env).run()
    let reasons = await env.records(.schedSkip).map { $0.ctx["reason"] }
    #expect(reasons == [.string("paused"), .string("paused"), .string("circuit_open")])
    var noCost = account
    noCost.capabilities = try Capabilities(usage: true, cost: false, balance: false, perKeyUsage: true, keyNames: true,
                                           balanceModeDefault: .anchored, usageLag: .seconds(60),
                                           currencyHint: .usd).json()
    try await env.repository.updateAccount(noCost)
    try await env.repository.resetCircuit(accountID: account.id)
    try await Self.costPolls(env).run()
    #expect(await env.transport.calls.isEmpty, "no request in any of these runs")
  }
}
