import Foundation
import Testing
@testable import TokenBeCore

/// 11 `PollStateTests`: consecutive_failures, circuit_open_until, cursor persistence, last_raw ≤ 64 KiB and
/// redacted, and V2 on the usage write (04 § Invariants), on the real database.
@Suite struct PollStateTests {
  typealias Harness = OpenAIHarness
  static let time = Harness.now

  static func failure(_ countsTowardCircuit: Bool) -> PollFailure {
    PollFailure(errorClass: countsTowardCircuit ? "auth" : "server", message: "m",
                countsTowardCircuit: countsTowardCircuit)
  }

  func fail(_ env: Harness, _ countsTowardCircuit: Bool) async throws -> PollStateRecord? {
    try await env.repository.recordPollFailure(
      accountID: Harness.account.id, job: .usage, at: Self.time, failure: Self.failure(countsTowardCircuit),
      circuit: CircuitRule(threshold: 3, until: Self.time.addingTimeInterval(86400))
    )
  }

  @Test("the account's four rows exist; attempt and success set their timestamps")
  func seededAndTimestamps() async throws {
    let env = try await Harness()
    for job in Job.allCases { #expect(try await env.repository.fetchPollState(accountID: Harness.account.id, job: job) != nil) }
    try await env.repository.recordPollAttempt(accountID: Harness.account.id, job: .cost, at: Self.time)
    try await env.repository.recordPollSuccess(accountID: Harness.account.id, job: .cost, at: Self.time, lastRaw: "{}")
    let state = try await env.state(.cost)
    #expect(state.lastAttemptAt == "2026-11-10T12:00:00.000Z" && state.lastSuccessAt == "2026-11-10T12:00:00.000Z")
    #expect(state.lastRaw == Data("{}".utf8))
  }

  @Test("failures count up; the circuit opens at the third circuit failure only")
  func circuit() async throws {
    let env = try await Harness()
    #expect(try await fail(env, false)?.circuitOpenUntil == nil)
    #expect(try await fail(env, false)?.circuitOpenUntil == nil)
    let third = try await fail(env, false)
    #expect(third?.consecutiveFailures == 3 && third?.circuitOpenUntil == nil)

    let auth = try await Harness()
    #expect(try await fail(auth, true)?.circuitOpenUntil == nil)
    #expect(try await fail(auth, true)?.circuitOpenUntil == nil)
    let opened = try await fail(auth, true)
    #expect(opened?.consecutiveFailures == 3)
    #expect(opened?.circuitOpenUntil == "2026-11-11T12:00:00.000Z")
    #expect(opened?.lastErrorClass == "auth" && opened?.lastErrorMessage == "m")
  }

  @Test("only consecutive auth failures open the circuit; another class in between restarts the streak",
        arguments: [([false, false, true], false), ([true, false, true, true], false), ([true, true, true], true),
                    ([false, true, true, true], true)])
  func mixedClasses(_ sequence: [Bool], opens: Bool) async throws {
    let env = try await Harness()
    var last: PollStateRecord?
    for auth in sequence { last = try await fail(env, auth) }
    #expect((last?.circuitOpenUntil != nil) == opens, "\(sequence)")
  }

  @Test("success resets failures, error, circuit and cursor, and returns the row as it was")
  func successResets() async throws {
    let env = try await Harness()
    for _ in 0..<3 { _ = try await fail(env, true) }
    try await env.repository.writeUsagePage(UsagePageWrite(accountID: Harness.account.id, rows: [], expected: TokenClasses(),
                                                         cursor: "c", lastRaw: "page"))
    let before = try await env.repository.recordPollSuccess(accountID: Harness.account.id, job: .usage, at: Self.time,
                                                          lastRaw: nil)
    #expect(before?.circuitOpenUntil != nil && before?.cursor == "c")
    let state = try await env.state(.usage)
    #expect(state.consecutiveFailures == 0 && state.circuitOpenUntil == nil && state.cursor == nil)
    #expect(state.lastErrorClass == nil && state.lastErrorMessage == nil)
    #expect(state.lastRaw == Data("page".utf8), "nil keeps the previous last_raw")
  }

  @Test("a failure keeps the cursor, so paging resumes")
  func failureKeepsCursor() async throws {
    let env = try await Harness()
    try await env.repository.writeUsagePage(UsagePageWrite(accountID: Harness.account.id, rows: [], expected: TokenClasses(),
                                                         cursor: "1794139200 page2", lastRaw: "p1"))
    _ = try await fail(env, false)
    #expect(try await env.state(.usage).cursor == "1794139200 page2")
  }

  @Test("V2: rows that do not add up to the page roll back, cursor included")
  func writeCompleteness() async throws {
    let env = try await Harness()
    let row = OpenAITests.usageRows[0]
    var duplicate = row
    duplicate.output = 1
    let expected = row.classes + duplicate.classes
    await #expect(throws: StoreError.writeIncomplete(expected: expected.tokens, written: duplicate.classes.tokens)) {
      try await env.repository.writeUsagePage(UsagePageWrite(
        accountID: Harness.account.id, rows: [row, duplicate], expected: expected, cursor: "next", lastRaw: "x"
      ))
    }
    #expect(try await env.repository.fetchUsageBuckets(accountID: Harness.account.id).isEmpty)
    #expect(try await env.state(.usage).cursor == nil)
  }

  @Test("a full usage poll stores last_raw redacted and within 64 KiB")
  func lastRawThroughPoll() async throws {
    let env = try await Harness()
    await env.on(Harness.usage, "usage_completions.ok", "usage_completions.page2")
    #expect(await env.run(.usage) == .succeeded(rows: 4))
    let raw = utf8Text(try #require(try await env.state(.usage).lastRaw))
    #expect(raw.utf8.count <= RawBody.limit && raw.contains("1794308400"))
    #expect(!raw.contains(env.key))
  }

  @Test("RawBody cuts on a character boundary")
  func truncation() {
    let text = String(repeating: "é", count: 10)
    #expect(RawBody.truncated(text, limit: 5) == "éé")
    #expect(RawBody.truncated("abc", limit: 5) == "abc")
  }
}
