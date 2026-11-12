import Foundation
import Synchronization
import Testing
@testable import TokenBeCore

/// `NetworkMonitor` for tests (14 § 0.3, PM-3.1-4): the test sets the status; every change after the first is
/// yielded, like `NWPathMonitorAdapter`.
final class ManualNetworkMonitor: NetworkMonitor {
  private let continuation = Mutex<AsyncStream<NetworkStatus>.Continuation?>(nil)

  func statuses() -> AsyncStream<NetworkStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: NetworkStatus.self)
    self.continuation.withLock { $0 = continuation }
    return stream
  }

  func set(online: Bool) {
    _ = continuation.withLock { $0?.yield(NetworkStatus(online: online, interface: online ? "wifi" : "none")) }
  }
}

/// A `PollCoordinator` over `OpenAIHarness`: one OpenAI account (usage every 300 s, keys every 3600 s), a stub
/// transport, a `TestClock` shared by the loop and the poller's retries, and a wall clock that `advance(by:)` moves
/// in step (so only a test that means to jump the wall clock causes a `sched.clock_jump`).
struct SchedulerHarness {
  let env: OpenAIHarness
  let coordinator: PollCoordinator<TestClock>
  let network = ManualNetworkMonitor()

  init(settings: ScheduleSettings = .defaults, seed: UInt64 = 7) async throws {
    env = try await OpenAIHarness(seed: seed)
    env.store.pipeline.minimumLevel = .debug
    coordinator = PollCoordinator(clock: env.clock, runner: env.poller, settings: settings,
                                  logPipeline: env.store.pipeline, now: env.date.provider)
  }

  var clock: TestClock { env.clock }
  var account: AccountRecord { OpenAIHarness.account }

  /// Every job answers `ok` (usage with an empty page).
  func answerOK() async {
    await env.on(OpenAIHarness.projects, "projects.ok")
    await env.on(OpenAIHarness.apiKeys, "api_keys.ok")
    await env.on(OpenAIHarness.usage, "usage_completions.empty")
  }

  /// The stored inputs, as the store's observation yields them.
  func inputs() async -> SummaryInputs {
    for await value in env.repository.observeSummaryInputs() { return value }
    return SummaryInputs(accounts: [])
  }

  /// Syncs the stored accounts, then starts the loop.
  func start() async {
    await coordinator.follow(network)
    await coordinator.sync(await inputs())
    await coordinator.start()
  }

  func resync() async {
    await coordinator.sync(await inputs())
  }

  func advance(by duration: Duration) {
    env.date.set(env.date.date.addingTimeInterval(PollCoordinator<TestClock>.seconds(duration)))
    env.clock.advance(by: duration)
  }

  /// Nothing in flight, and the loop asleep until `deadline` (seconds since the clock's start).
  func settled(next deadline: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
    let coordinator = coordinator
    let clock = clock
    await eventually("settled, next wake at \(deadline) s", sourceLocation: sourceLocation) {
      await coordinator.runningKeys.isEmpty && clock.deadlines == [.seconds(deadline)]
    }
  }

  /// Usage has sent its first request and sleeps in its first retry (a transport error answered): the job is in
  /// flight for sure, and advancing the clock past 10 s finishes it. Waiting on the dispatch alone races the request.
  func usageRetrying(sourceLocation: SourceLocation = #_sourceLocation) async {
    let clock = clock
    let transport = env.transport
    await eventually("usage asleep in its first retry", sourceLocation: sourceLocation) {
      let now = clock.now.offset
      let sent = await transport.calls.contains { $0.url.path() == OpenAIHarness.usage }
      return sent && clock.deadlines.contains { $0 > now && $0 <= now + .seconds(10) }
    }
  }

  func calls(_ path: String) async -> Int {
    await env.transport.calls.filter { $0.url.path() == path }.count
  }

  func records(_ evt: Evt) async -> [LogRecord] {
    await env.records(evt)
  }

  func reasons() async -> [String] {
    await records(.schedSkip).compactMap {
      if case .string(let reason) = $0.ctx["reason"] { return "\($0.job ?? "")=\(reason)" }
      return nil
    }
  }

  func entry(_ job: Job) async -> SchedulerLoop<TestClock.Instant>.Slot? {
    await coordinator.schedule.entries[SchedulerLoop<TestClock.Instant>.Key(accountID: account.id, job: job)]
  }

  func stop() async {
    await coordinator.shutdown()
  }
}
