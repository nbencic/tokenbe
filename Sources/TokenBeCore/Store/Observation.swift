import Foundation
import GRDB

/// What `AccountSummaryBuilder` turns into the popover's and the Dashboard's `[AccountSummary]` (14 § Stage 2.2).
/// The set grows stage by stage: 2.2 observes `account`, 3.5 adds each job's last success and circuit from
/// `poll_state` (card freshness, `never` before the first poll), and 4.2 each job's last error (the account page's
/// Sources strip); 5.2 the daily usage, cost and priced-model aggregates of the last 91 UTC days (the numbers strip);
/// band_state, the latest balance and the ledger join with the stages that fill those fields (PM-2.2-3).
public struct SummaryInputs: Sendable, Equatable {
  /// Oldest first, like `fetchAccounts()`.
  public var accounts: [AccountRecord]
  /// The columns of `poll_state` a summary needs (never `last_raw`), by account then job.
  public var pollStates: [PollStateSummary]
  /// Per account, UTC day and source: Σ `est_cost_cents` and Σ unpriced tokens (05 § Spend definitions).
  public var usageDays: [UsageDay]
  /// Per account and UTC day, the models with priced usage (05 `unpriced_cents`' median rate).
  public var pricedModels: [PricedModelDay]
  /// Per account and UTC day, the provider's `total` cost row (05 `spend_truth`).
  public var costDays: [CostDay]

  /// How far back the aggregates reach: the longest Dashboard range (90 d) plus today.
  public static let window: TimeInterval = 91 * 86_400

  public init(accounts: [AccountRecord], pollStates: [PollStateSummary] = [], usageDays: [UsageDay] = [],
              pricedModels: [PricedModelDay] = [], costDays: [CostDay] = []) {
    self.accounts = accounts
    self.pollStates = pollStates
    self.usageDays = usageDays
    self.pricedModels = pricedModels
    self.costDays = costDays
  }

  static func fetch(_ db: Database) throws -> SummaryInputs {
    let since = Date().addingTimeInterval(-window)
    let start = DBTime.string(since)
    return SummaryInputs(
      accounts: try AccountRecord.order(Column("created_at"), Column("id")).fetchAll(db),
      pollStates: try PollStateSummary.fetchAll(db, sql: """
        SELECT account_id, job, last_success_at, circuit_open_until, last_error_class, last_error_message
        FROM poll_state ORDER BY account_id, job
        """),
      usageDays: try Row.fetchAll(db, sql: """
        SELECT account_id, substr(bucket_start, 1, 10) AS day, source, SUM(COALESCE(est_cost_cents, 0)) AS est,
               SUM(CASE WHEN unpriced = 1
                   THEN input_uncached + cache_write_5m + cache_write_1h + cache_read + output + reasoning
                   ELSE 0 END) AS unpriced_tokens
        FROM usage_bucket WHERE bucket_start >= ? GROUP BY account_id, day, source ORDER BY account_id, day, source
        """, arguments: [start]).map {
          UsageDay(accountId: $0["account_id"], day: $0["day"], source: $0["source"], estCents: $0["est"],
                   unpricedTokens: $0["unpriced_tokens"])
        },
      pricedModels: try Row.fetchAll(db, sql: """
        SELECT DISTINCT account_id, substr(bucket_start, 1, 10) AS day, model FROM usage_bucket
        WHERE bucket_start >= ? AND unpriced = 0 AND est_cost_cents IS NOT NULL ORDER BY account_id, day, model
        """, arguments: [start]).map { PricedModelDay(accountId: $0["account_id"], day: $0["day"], model: $0["model"]) },
      costDays: try Row.fetchAll(db, sql: """
        SELECT account_id, day, SUM(amount_cents) AS amount FROM cost_bucket
        WHERE group_kind = 'total' AND day >= ? GROUP BY account_id, day ORDER BY account_id, day
        """, arguments: [DailyOnce.utcDay(since)]).map {
          CostDay(accountId: $0["account_id"], day: $0["day"], amountCents: $0["amount"])
        }
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
