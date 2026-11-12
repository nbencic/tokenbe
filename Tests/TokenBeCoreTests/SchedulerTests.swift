import Foundation
import Testing
@testable import TokenBeCore

/// 11 § SchedulerTests on a `TestClock`: due ordering, tolerance coalescing, the retry and backoff sequences,
/// Retry-After and its cap, the circuit, decode without retry, Low Power ×4, clock jumps, pause/resume.
@Suite struct SchedulerTests {
  typealias Loop = SchedulerLoop<TestClock.Instant>
  typealias Harness = SchedulerHarness

  static func at(_ seconds: Int) -> TestClock.Instant { TestClock.Instant(offset: .seconds(seconds)) }
  static func key(_ account: String, _ job: Job) -> Loop.Key { Loop.Key(accountID: account, job: job) }

  // MARK: - The table

  @Test("due jobs come earliest first, ties by account and job; in-flight jobs are left out")
  func dueOrdering() {
    var loop = Loop()
    loop.entries[Self.key("b", .usage)] = Loop.Slot(nextDue: Self.at(10), interval: .seconds(60))
    loop.entries[Self.key("a", .keys)] = Loop.Slot(nextDue: Self.at(10), interval: .seconds(60))
    loop.entries[Self.key("a", .usage)] = Loop.Slot(nextDue: Self.at(3), interval: .seconds(60))
    loop.entries[Self.key("c", .balance)] = Loop.Slot(nextDue: Self.at(1), interval: .seconds(60))
    #expect(loop.due(at: Self.at(10), excluding: []) ==
            [Self.key("c", .balance), Self.key("a", .usage), Self.key("a", .keys), Self.key("b", .usage)])
    #expect(loop.due(at: Self.at(10), excluding: [Self.key("a", .usage)]).contains(Self.key("a", .usage)) == false)
    #expect(loop.nextDue(excluding: [Self.key("c", .balance)]) == Self.at(3))
  }

  @Test("two jobs due within 5 s of each other run in one wake; one due 6 s later waits")
  func toleranceCoalescing() {
    var loop = Loop()
    loop.entries[Self.key("a", .usage)] = Loop.Slot(nextDue: Self.at(100), interval: .seconds(300))
    loop.entries[Self.key("a", .keys)] = Loop.Slot(nextDue: Self.at(104), interval: .seconds(3600))
    loop.entries[Self.key("b", .balance)] = Loop.Slot(nextDue: Self.at(106), interval: .seconds(60))
    #expect(loop.due(at: Self.at(100), excluding: []) == [Self.key("a", .usage), Self.key("a", .keys)])
    #expect(Loop.tolerance == .seconds(5))
  }

  @Test("after failed attempts the next one waits interval × 2ⁿ, capped at 15 min; a success resets it")
  func backoffBetweenAttempts() {
    var loop = Loop()
    let key = Self.key("a", .usage)
    loop.upsert(key, interval: .seconds(300), at: Self.at(0))
    var waits: [Duration] = []
    for _ in 0..<3 {
      loop.completed(key, outcome: .failed("server"), at: Self.at(0))
      waits.append(Self.at(0).duration(to: loop.entries[key]!.nextDue))
    }
    #expect(waits == [.seconds(600), .seconds(900), .seconds(900)])
    loop.completed(key, outcome: .succeeded(rows: 0), at: Self.at(0))
    #expect(loop.entries[key]?.nextDue == Self.at(300) && loop.entries[key]?.failures == 0)
  }

  // MARK: - Through the coordinator

  @Test("first tick runs every job at once; then usage every 300 s, keys every 3600 s")
  func cadence() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    #expect(await env.calls(OpenAIHarness.projects) == 1)
    env.advance(by: .seconds(300))
    await env.settled(next: 600)
    #expect(await env.calls(OpenAIHarness.usage) == 2)
    #expect(await env.calls(OpenAIHarness.projects) == 1)
    #expect(await env.records(.pollOk).count == 3)
    #expect(await env.records(.schedTick).map(\.job) == ["keys", "usage", "usage"])
    await env.stop()
  }

  @Test("transport ×3 inside one attempt: retries after 2/4/8 s ± 25 % (seeded), then the next run is on schedule")
  func retrySequence() async throws {
    let env = try await Harness(seed: 42)
    await env.answerOK()
    let timeout = StubTransport.Answer.failure(.urlError(URLError(.timedOut)))
    await env.env.transport.replace("GET", OpenAIHarness.usage, timeout, timeout, timeout,
                                    .fixture(OpenAIHarness.fixture("usage_completions.empty")))
    await env.start()
    var rng = SeededRNG(seed: 42)
    for attempt in 1...3 {
      let delay = try #require(RetryPolicy.nextDelay(attempt: attempt, error: .transport(URLError(.timedOut)),
                                                     using: &rng))
      let clock = env.clock
      let start = clock.now.offset
      await clock.waitUntil("retry \(attempt) sleeping") { $0.deadlines.contains(start + delay) }
      env.advance(by: delay)
    }
    let base = env.clock.now.offset
    await eventually("the attempt succeeded, next usage one interval later") {
      guard await env.coordinator.runningKeys.isEmpty else { return false }
      return await env.entry(.usage)?.nextDue == TestClock.Instant(offset: base + .seconds(300))
    }
    #expect(await env.records(.pollRetry).map(\.attempt) == [1, 2, 3])
    #expect(await env.records(.pollOk).count == 2)
    await env.stop()
  }

  @Test("a failed attempt backs off: next usage at 600 s, then 900 s (cap), back to 300 s after a success")
  func backoffThroughLoop() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, OpenAIHarness.status(400, "{}"),
                                    OpenAIHarness.status(400, "{}"),
                                    .fixture(OpenAIHarness.fixture("usage_completions.empty")))
    await env.start()
    await env.settled(next: 600)
    env.advance(by: .seconds(600))
    await env.settled(next: 1500)
    env.advance(by: .seconds(900))
    await env.settled(next: 1800)
    #expect(await env.entry(.usage)?.failures == 0)
    await env.stop()
  }

  @Test("429 Retry-After is honored (12 s) and capped at 300 s (9999 s)")
  func retryAfter() async throws {
    let env = try await Harness()
    await env.answerOK()
    let empty = StubTransport.Answer.fixture(OpenAIHarness.fixture("usage_completions.empty"))
    await env.env.transport.replace("GET", OpenAIHarness.usage,
                                    OpenAIHarness.status(429, "{}", headers: ["Retry-After": "12"]), empty,
                                    OpenAIHarness.status(429, "{}", headers: ["Retry-After": "9999"]), empty)
    await env.start()
    let clock = env.clock
    await clock.waitUntil("the 12 s retry") { $0.deadlines.contains(.seconds(12)) }
    env.advance(by: .seconds(12))
    await env.settled(next: 312)
    env.advance(by: .seconds(300))
    await clock.waitUntil("the retry capped at 300 s") { $0.deadlines.contains(.seconds(612)) }
    env.advance(by: .seconds(300))
    await env.settled(next: 912)
    #expect(await env.records(.pollRateLimited).map { $0.ctx["retry_after_s"] } == [.int(12), .int(9999)])
    #expect(await env.records(.pollRetry).map { $0.ctx["delay_ms"] } == [.int(12_000), .int(300_000)])
    await env.stop()
  }

  @Test("auth ×3 opens the circuit for 24 h: later due runs are skipped (circuit_open) without a request")
  func circuit() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, .fixture(OpenAIHarness.fixture("projects.401")))
    await env.start()
    await env.settled(next: 600)
    env.advance(by: .seconds(600))
    await env.settled(next: 1500)
    env.advance(by: .seconds(900))
    await env.settled(next: 2400)
    #expect(await env.records(.pollCircuitOpen).count == 1)
    await env.resync()
    env.advance(by: .seconds(900))
    await env.settled(next: 2700)
    #expect(await env.calls(OpenAIHarness.usage) == 3)
    #expect(await env.reasons() == ["usage=circuit_open"])
    await env.stop()
  }

  @Test("decode failure: one request, no retry, the attempt backs off")
  func decodeNoRetry() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.env.transport.replace("GET", OpenAIHarness.usage, OpenAIHarness.ok(#"{"object":"page"}"#))
    await env.start()
    await env.settled(next: 600)
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    #expect(await env.records(.pollRetry).isEmpty)
    #expect(await env.records(.pollSchemaDrift).count == 1)
    await env.stop()
  }

  @Test("Low Power ×4: sched.low_power once per transition; usage every 1200 s; back to 300 s when it ends")
  func lowPower() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    await env.coordinator.setLowPower(true)
    await env.coordinator.setLowPower(true)
    env.advance(by: .seconds(300))
    await env.settled(next: 1500)
    await env.coordinator.setLowPower(false)
    await env.settled(next: 600)
    #expect(await env.records(.schedLowPower).map { $0.ctx["enabled"] } == [.bool(true), .bool(false)])
    await env.stop()
  }

  @Test("a wall-clock jump > 30 s logs sched.clock_jump with both deltas and runs nothing extra")
  func clockJump() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    env.env.date.set(env.env.date.date.addingTimeInterval(7200))
    env.clock.advance(by: .seconds(10))
    await env.resync()
    await eventually("sched.clock_jump") { await env.records(.schedClockJump).count == 1 }
    let jump = try #require(await env.records(.schedClockJump).first)
    #expect(jump.ctx["wall_delta_s"] == .int(7200) && jump.ctx["mono_delta_s"] == .int(10))
    #expect(jump.lvl == .warn)
    await env.settled(next: 300)
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    await env.stop()
  }

  @Test("after a wake 10 intervals late, each job runs once (no catch-up burst)")
  func wakeNoCatchUp() async throws {
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    // The loop's own sleep fires at 300; the wake notification arrives with it.
    env.advance(by: .seconds(3000))
    await env.coordinator.systemDidWake()
    await env.settled(next: 3300)
    #expect(await env.calls(OpenAIHarness.usage) == 2)
    #expect(await env.records(.schedClockJump).first?.ctx["reason"] == .string("wake"))
    await env.stop()
  }

  @Test("global pause: due jobs are skipped (paused); Resume runs them at once")
  func pauseResume() async throws {
    var settings = ScheduleSettings.defaults
    let env = try await Harness()
    await env.answerOK()
    await env.start()
    await env.settled(next: 300)
    settings.pausedUntil = env.env.date.date.addingTimeInterval(3600)
    await env.coordinator.update(settings)
    env.advance(by: .seconds(300))
    await env.settled(next: 600)
    #expect(await env.reasons() == ["usage=paused"])
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    settings.pausedUntil = nil
    await env.coordinator.update(settings)
    await env.settled(next: 600)
    #expect(await env.calls(OpenAIHarness.usage) == 2)
    #expect(await env.calls(OpenAIHarness.projects) == 2)
    await env.stop()
  }

  @Test("the pause ends by itself: the loop wakes at pausedUntil and polls")
  func pauseExpires() async throws {
    var settings = ScheduleSettings.defaults
    let env = try await Harness()
    await env.answerOK()
    settings.pausedUntil = env.env.date.date.addingTimeInterval(100)
    await env.coordinator.update(settings)
    await env.start()
    await env.settled(next: 100)
    #expect(await env.calls(OpenAIHarness.usage) == 0)
    env.advance(by: .seconds(100))
    await env.settled(next: 400)
    #expect(await env.calls(OpenAIHarness.usage) == 1)
    await env.stop()
  }
}
