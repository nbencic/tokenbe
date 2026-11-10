import Foundation
import GRDB

/// What `AccountSummaryBuilder` turns into the popover's and the Dashboard's `[AccountSummary]` (14 § Stage 2.2).
/// The set grows stage by stage: 2.2 observes `account` only, for the identity fields (Q-025); poll_state,
/// band_state, the latest balance, the ledger and recent buckets join with the stages that fill those fields.
public struct SummaryInputs: Sendable, Equatable {
  /// Oldest first, like `fetchAccounts()`.
  public var accounts: [AccountRecord]

  public init(accounts: [AccountRecord]) {
    self.accounts = accounts
  }

  static func fetch(_ db: Database) throws -> SummaryInputs {
    SummaryInputs(accounts: try AccountRecord.order(Column("created_at"), Column("id")).fetchAll(db))
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
