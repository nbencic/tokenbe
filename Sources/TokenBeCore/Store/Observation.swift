import Foundation
import GRDB

/// What `AccountSummaryBuilder` turns into the popover's and the Dashboard's `[AccountSummary]` (14 § Stage 2.2).
/// The set grows stage by stage: 2.2 observes `account`, 3.5 adds each job's last success and circuit from
/// `poll_state` (card freshness, `never` before the first poll), and 4.2 each job's last error (the account page's
/// Sources strip); 5.2 the daily usage, cost and priced-model aggregates of the last 91 UTC days (the numbers strip);
/// 5.3 the ledger, the latest balance, `band_state` and the anchor day's remainder, and the aggregates reach back
/// to the oldest current anchor (PM-2.2-3); 7.1 apps, bindings, provider keys and the per-key daily aggregates (the
/// By-app table, Apps this period, popover row 4).
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
  /// Every `ledger_event` row, oldest first.
  public var ledgerEvents: [LedgerEventRecord]
  /// The latest `balance_snapshot` of each account (direct providers).
  public var balances: [BalanceSnapshotRecord]
  /// `band_state`, one row per evaluated account.
  public var bandStates: [BandStateRecord]
  /// Per account and source, Σ `est_cost_cents` of the buckets on the latest anchor's UTC day that start at or after
  /// the anchor (05: "the anchor day's remainder"); `day` is the anchor day.
  public var anchorDayUsage: [UsageDay]
  /// Every `app` row, the `unassigned` sentinel included (03).
  public var apps: [AppRecord]
  /// Every `app_binding` row (03).
  public var bindings: [AppBindingRecord]
  /// Every `provider_key` row: names and hints for the By-app table (08) and Keys & apps.
  public var providerKeys: [ProviderKeyRecord]
  /// Per account, UTC day, provider key and source: Σ `est_cost_cents`, requests and token classes (06 precedence).
  public var keyUsageDays: [KeyUsageDay]
  /// Per account, UTC day and provider key: the provider's `cost_bucket` rows with `group_kind = 'api_key_id'`.
  public var keyCostDays: [KeyCostDay]
  /// 7.2: per account, UTC day, app tag and resolved key, the harness lines' estimate, classes and count (06
  /// precedence: split and substitute weights).
  public var harnessDays: [HarnessDay] = []
  /// 7.2: each account's last balance of each UTC day, per currency (inference and drift, 06).
  public var balanceDays: [BalanceDay] = []
  /// 7.2: harness lines stored for a provider with no account (O-12).
  public var harnessWithoutAccount = 0
  /// 8.1: per account, UTC day, model and source, the usage of the By-model table (05 § Drift).
  public var modelUsageDays: [ModelUsageDay] = []
  /// 8.1: per account, UTC day and line item, the provider's `cost_bucket` rows with `group_kind = 'line_item'`.
  public var lineItemCostDays: [LineItemCostDay] = []

  /// How far back the aggregates reach: the longest Dashboard range (90 d) plus today.
  public static let window: TimeInterval = 91 * 86_400

  public init(accounts: [AccountRecord], pollStates: [PollStateSummary] = [], usageDays: [UsageDay] = [],
              pricedModels: [PricedModelDay] = [], costDays: [CostDay] = [], ledgerEvents: [LedgerEventRecord] = [],
              balances: [BalanceSnapshotRecord] = [], bandStates: [BandStateRecord] = [],
              anchorDayUsage: [UsageDay] = [], apps: [AppRecord] = [], bindings: [AppBindingRecord] = [],
              providerKeys: [ProviderKeyRecord] = [], keyUsageDays: [KeyUsageDay] = [],
              keyCostDays: [KeyCostDay] = []) {
    self.accounts = accounts
    self.pollStates = pollStates
    self.usageDays = usageDays
    self.pricedModels = pricedModels
    self.costDays = costDays
    self.ledgerEvents = ledgerEvents
    self.balances = balances
    self.bandStates = bandStates
    self.anchorDayUsage = anchorDayUsage
    self.apps = apps
    self.bindings = bindings
    self.providerKeys = providerKeys
    self.keyUsageDays = keyUsageDays
    self.keyCostDays = keyCostDays
  }

  static func fetch(_ db: Database) throws -> SummaryInputs {
    let ledger = try LedgerEventRecord.order(Column("ts"), Column("id")).fetchAll(db)
    // The aggregates reach back 91 days, or to the oldest current anchor if that is older (05 spend_since_anchor).
    let anchors = Set(ledger.map(\.accountId)).compactMap { Remaining.anchor(accountID: $0, events: ledger) }
    let oldestAnchorDay = anchors.map { String($0.ts.prefix(10)) + "T00:00:00.000Z" }.min()
    let since = Date().addingTimeInterval(-window)
    let start = min(DBTime.string(since), oldestAnchorDay ?? DBTime.string(since))
    var inputs = SummaryInputs(
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
        """, arguments: [String(start.prefix(10))]).map {
          CostDay(accountId: $0["account_id"], day: $0["day"], amountCents: $0["amount"])
        },
      ledgerEvents: ledger,
      balances: try BalanceSnapshotRecord.fetchAll(db, sql: """
        SELECT b.* FROM balance_snapshot b
        WHERE b.ts = (SELECT max(ts) FROM balance_snapshot WHERE account_id = b.account_id) ORDER BY b.account_id
        """),
      bandStates: try BandStateRecord.order(Column("account_id")).fetchAll(db),
      anchorDayUsage: try anchors.sorted { $0.accountId < $1.accountId }.flatMap { anchor in
        try Row.fetchAll(db, sql: """
          SELECT source, SUM(COALESCE(est_cost_cents, 0)) AS est FROM usage_bucket
          WHERE account_id = ? AND bucket_start >= ? AND substr(bucket_start, 1, 10) = ? GROUP BY source ORDER BY source
          """, arguments: [anchor.accountId, anchor.ts, String(anchor.ts.prefix(10))]).map {
          UsageDay(accountId: anchor.accountId, day: String(anchor.ts.prefix(10)), source: $0["source"], estCents: $0["est"])
        }
      }
    )
    try inputs.fetchAttribution(db, since: DBTime.string(since))
    return inputs
  }

  /// 7.1: apps, bindings, provider keys and the per-key daily aggregates of the window (the By-app table); 7.2 the
  /// harness and balance days; 8.1 the per-model usage and line-item cost days (the By-model table).
  mutating func fetchAttribution(_ db: Database, since: String) throws {
    apps = try AppRecord.order(Column("display_name"), Column("name")).fetchAll(db)
    bindings = try AppBindingRecord.order(Column("account_id"), Column("kind"), Column("value")).fetchAll(db)
    providerKeys = try ProviderKeyRecord.order(Column("account_id"), Column("provider_key_id")).fetchAll(db)
    keyUsageDays = try KeyUsageDay.fetch(db, since: since)
    keyCostDays = try Row.fetchAll(db, sql: """
      SELECT account_id, day, group_key, SUM(amount_cents) AS amount FROM cost_bucket
      WHERE group_kind = 'api_key_id' AND day >= ? GROUP BY account_id, day, group_key
      ORDER BY account_id, day, group_key
      """, arguments: [String(since.prefix(10))]).map {
        KeyCostDay(accountId: $0["account_id"], day: $0["day"], providerKeyId: $0["group_key"],
                   amountCents: $0["amount"])
      }
    harnessDays = try HarnessDay.fetch(db, since: since)
    balanceDays = try BalanceDay.fetch(db, since: since)
    harnessWithoutAccount = try Int.fetchOne(db, sql: "SELECT count(*) FROM harness_event WHERE account_id IS NULL") ?? 0
    modelUsageDays = try ModelUsageDay.fetch(db, since: since)
    lineItemCostDays = try LineItemCostDay.fetch(db, since: since)
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
