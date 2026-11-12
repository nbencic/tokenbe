import Foundation
import GRDB

/// What `AccountSummaryBuilder` turns into the popover's and the Dashboard's `[AccountSummary]` (14 § Stage 2.2).
/// The set grows stage by stage: 2.2 observes `account`, 3.5 adds each job's last success and circuit from
/// `poll_state` (card freshness, `never` before the first poll), and 4.2 each job's last error (the account page's
/// Sources strip); band_state, the latest balance, the ledger and
/// recent buckets join with the stages that fill those fields (PM-2.2-3).
public struct SummaryInputs: Sendable, Equatable {
  /// Oldest first, like `fetchAccounts()`.
  public var accounts: [AccountRecord]
  /// The columns of `poll_state` a summary needs (never `last_raw`), by account then job.
  public var pollStates: [PollStateSummary]

  public init(accounts: [AccountRecord], pollStates: [PollStateSummary] = []) {
    self.accounts = accounts
    self.pollStates = pollStates
  }

  static func fetch(_ db: Database) throws -> SummaryInputs {
    SummaryInputs(
      accounts: try AccountRecord.order(Column("created_at"), Column("id")).fetchAll(db),
      pollStates: try PollStateSummary.fetchAll(db, sql: """
        SELECT account_id, job, last_success_at, circuit_open_until, last_error_class, last_error_message
        FROM poll_state ORDER BY account_id, job
        """)
    )
  }
}

/// One job's freshness, circuit and last error (03 `poll_state`).
public struct PollStateSummary: Sendable, Equatable, Codable, FetchableRecord {
  public var accountId: String
  public var job: String
  public var lastSuccessAt: String?
  public var circuitOpenUntil: String?
  /// Set by a failed attempt, cleared by a success (`Repository+Poll`).
  public var lastErrorClass: String?
  /// The failure's human message (Q-036).
  public var lastErrorMessage: String?

  public init(accountId: String, job: String, lastSuccessAt: String? = nil, circuitOpenUntil: String? = nil,
              lastErrorClass: String? = nil, lastErrorMessage: String? = nil) {
    self.accountId = accountId
    self.job = job
    self.lastSuccessAt = lastSuccessAt
    self.circuitOpenUntil = circuitOpenUntil
    self.lastErrorClass = lastErrorClass
    self.lastErrorMessage = lastErrorMessage
  }

  enum CodingKeys: String, CodingKey {
    case accountId = "account_id"
    case job
    case lastSuccessAt = "last_success_at"
    case circuitOpenUntil = "circuit_open_until"
    case lastErrorClass = "last_error_class"
    case lastErrorMessage = "last_error_message"
  }
}

/// The UI's read path (04 I2): `ValueObservation` on the pool's reader connections.
public protocol ObservationRepository: Sendable {
  /// Yields the current inputs at once, then again after every committed change to them (duplicates dropped).
  /// The stream ends when the caller stops iterating; a read failure logs `ui.error {view, err}` and ends it.
  func observeSummaryInputs() -> AsyncStream<SummaryInputs>
}

extension GRDBRepository {
  public nonisolated func observeSummaryInputs() -> AsyncStream<SummaryInputs> {
    database.observeSummaryInputs()
  }
}

extension AppDatabase {
  func observeSummaryInputs() -> AsyncStream<SummaryInputs> {
    let observation = ValueObservation.tracking(SummaryInputs.fetch).removeDuplicates()
    let pool = pool
    let log = log
    return AsyncStream { continuation in
      let task = Task {
        do {
          for try await inputs in observation.values(in: pool) {
            continuation.yield(inputs)
          }
        } catch {
          // Cancellation is the caller going away, not a failure.
          if !Task.isCancelled {
            log.emit(.error, .uiError, msg: "summary observation failed", err: error, ctx: [
              "view": .string("summary")
            ])
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
