import Foundation
import GRDB

/// A failed job attempt, as `poll_state` records it (04 § Retry policy).
public struct PollFailure: Sendable, Equatable {
  /// `auth`, `transport`, `server`, `rate_limited`, `decode`, `provider_rule`, `keychain`, `store` (Q-029).
  public var errorClass: String
  /// Already redacted (R8).
  public var message: String
  /// The body that failed to decode, redacted; nil keeps the previous `last_raw`.
  public var lastRaw: String?
  /// True for `auth`: the circuit opens when this failure makes `circuitThreshold` in a row.
  public var countsTowardCircuit: Bool

  public init(errorClass: String, message: String, lastRaw: String? = nil, countsTowardCircuit: Bool = false) {
    self.errorClass = errorClass
    self.message = message
    self.lastRaw = lastRaw
    self.countsTowardCircuit = countsTowardCircuit
  }
}

/// `poll_state` rows (03): one per account and job, seeded with the account.
public protocol PollRepository: Sendable {
  func fetchPollState(accountID: String, job: Job) async throws -> PollStateRecord?
  /// `last_attempt_at`.
  func recordPollAttempt(accountID: String, job: Job, at time: Date) async throws
  /// Clears the error, the failure count, the circuit and the cursor; stores `last_raw` when given. Returns the
  /// row as it was before, so the caller can log `poll.circuit_close`.
  @discardableResult
  func recordPollSuccess(accountID: String, job: Job, at time: Date, lastRaw: String?) async throws -> PollStateRecord?
  /// `consecutive_failures + 1` and the error; when the failure counts toward the circuit and the count reaches
  /// `circuitThreshold`, `circuit_open_until = circuitUntil`. The cursor is kept, so paging resumes (Q-029).
  /// Returns the updated row.
  func recordPollFailure(accountID: String, job: Job, at time: Date, failure: PollFailure, circuitThreshold: Int,
                         circuitUntil: Date) async throws -> PollStateRecord?
}

extension GRDBRepository {
  public func fetchPollState(accountID: String, job: Job) async throws -> PollStateRecord? {
    try await database.read { db in
      try PollStateRecord.fetchOne(db, key: ["account_id": accountID, "job": job.rawValue])
    }
  }

  public func recordPollAttempt(accountID: String, job: Job, at time: Date) async throws {
    try await database.write("recordPollAttempt") { db in
      try db.execute(sql: "UPDATE poll_state SET last_attempt_at = ? WHERE account_id = ? AND job = ?",
                     arguments: [DBTime.string(time), accountID, job.rawValue])
    }
  }

  @discardableResult
  public func recordPollSuccess(accountID: String, job: Job, at time: Date,
                                lastRaw: String?) async throws -> PollStateRecord? {
    try await database.write("recordPollSuccess") { db in
      let before = try PollStateRecord.fetchOne(db, key: ["account_id": accountID, "job": job.rawValue])
      try db.execute(sql: """
        UPDATE poll_state SET last_success_at = ?, last_error_class = NULL, last_error_message = NULL,
          consecutive_failures = 0, circuit_open_until = NULL, cursor = NULL, last_raw = COALESCE(?, last_raw)
        WHERE account_id = ? AND job = ?
        """, arguments: [DBTime.string(time), lastRaw.map { Data($0.utf8) }, accountID, job.rawValue])
      return before
    }
  }

  public func recordPollFailure(accountID: String, job: Job, at time: Date, failure: PollFailure,
                                circuitThreshold: Int, circuitUntil: Date) async throws -> PollStateRecord? {
    try await database.write("recordPollFailure") { db in
      let key: [String: (any DatabaseValueConvertible)?] = ["account_id": accountID, "job": job.rawValue]
      guard var state = try PollStateRecord.fetchOne(db, key: key) else { return nil }
      state.consecutiveFailures += 1
      state.lastErrorClass = failure.errorClass
      state.lastErrorMessage = failure.message
      if let lastRaw = failure.lastRaw { state.lastRaw = Data(lastRaw.utf8) }
      if failure.countsTowardCircuit && state.consecutiveFailures >= Int64(circuitThreshold) {
        state.circuitOpenUntil = DBTime.string(circuitUntil)
      }
      try state.update(db)
      return state
    }
  }
}
