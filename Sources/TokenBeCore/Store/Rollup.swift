import Foundation
import GRDB

/// The retention windows of 03 § Retention tiers: two come from 09 (`tb.retention.*`), two are fixed by 03.
public struct RetentionPolicy: Sendable, Equatable {
  /// 09 `tb.retention.hourlyDays`: hourly `usage_bucket` rows older than this are summed into daily rows.
  public var hourlyDays: Int
  /// 09 `tb.retention.rawHarnessDays`: `harness_event` rows older than this are deleted.
  public var rawHarnessDays: Int
  /// 03: daily rows older than 400 days are also summed into monthly rows.
  public static let monthlyAfterDays = 400
  /// 03: `balance_snapshot` keeps every row for 7 days.
  public static let balanceFullRateDays = 7

  public init(hourlyDays: Int, rawHarnessDays: Int) {
    self.hourlyDays = hourlyDays
    self.rawHarnessDays = rawHarnessDays
  }
}

/// What one tier of one roll-up did: `db.rollup {tier, rows_in, rows_out}` (07).
public struct RollupCount: Sendable, Equatable {
  /// `hourly`, `monthly`, `harness_event` or `balance_snapshot`.
  public var tier: String
  /// Rows read (hourly, monthly) or examined (purge, thinning).
  public var rowsIn: Int
  /// Rows written (hourly, monthly) or deleted (purge, thinning).
  public var rowsOut: Int

  public init(tier: String, rowsIn: Int = 0, rowsOut: Int = 0) {
    self.tier = tier
    self.rowsIn = rowsIn
    self.rowsOut = rowsOut
  }

  /// Adds another account's counts of the same tier.
  static func += (lhs: inout RollupCount, rhs: RollupCount) {
    lhs.rowsIn += rhs.rowsIn
    lhs.rowsOut += rhs.rowsOut
  }
}

/// The retention job's writes (03 § Retention tiers; 14 § Stage 9.1). Each roll-up is one transaction per tier per
/// account (12 § R7). Every cut-off is a UTC day boundary (`YYYY-MM-DDT00:00:00.000Z`), so a day is never split.
public protocol RetentionRepository: Sendable {
  /// Sums the account's `1h` rows that start before `before` into `1d` rows, then deletes them. Provider rows become
  /// `source = 'rollup'`; harness rows stay `source = 'harness'`, so `Spend.counts` still tells them apart (Q-055).
  /// Days holding one of the account's `anchor` ledger events stay hourly: `spend_since_anchor` reads the hours after
  /// the anchor's time (05). Adds to a daily row that exists, so a late hour of a rolled day is not lost.
  func rollupHourly(accountID: String, before: String) async throws -> RollupCount
  /// Recomputes the account's `1mo` rows from the `1d` rows that start before `before` (a month boundary); the daily
  /// rows stay (03). Only a month whose sums changed is written, so a second run writes nothing.
  func rollupMonthly(accountID: String, before: String) async throws -> RollupCount
  /// Deletes `harness_event` rows whose `ts` is before `before`; their usage is already in the harness buckets (03).
  func purgeHarnessEvents(before: String) async throws -> RollupCount
  /// Keeps the first and the last snapshot of each UTC day and currency before `before`, and deletes the others
  /// (03 keeps the first; the day's last is the balance `BalanceDay` reads, Q-055).
  func thinBalanceSnapshots(accountID: String, before: String) async throws -> RollupCount
}

/// The `roll-ups` step of the daily activity (04 § Daily activity; 03 § Retention tiers; 14 § Stage 9.1):
/// hourly → daily, daily → monthly, then the `harness_event` purge and the `balance_snapshot` thinning. One
/// `db.rollup {tier, rows_in, rows_out}` per tier, summed over the accounts. A failed roll-up throws before the purge,
/// so raw events are only deleted after a roll-up that succeeded; the daily activity retries the step next time.
/// `incremental_vacuum` (03 "after roll-up") is the activity's last step.
public struct Rollup: Sendable {
  let store: any RetentionRepository & AccountRepository
  let log: EventLog

  public init(store: any RetentionRepository & AccountRepository, logPipeline: LogPipeline? = nil) {
    self.store = store
    self.log = EventLog(pipeline: logPipeline)
  }

  /// Runs every tier for `policy` at `now`. Returns the four tiers' counts in order.
  @discardableResult
  public func run(_ policy: RetentionPolicy, now: Date) async throws -> [RollupCount] {
    let cut = Cutoffs(policy, now: now)
    let accounts = try await store.fetchAccounts().map(\.id)
    var hourly = RollupCount(tier: "hourly")
    for account in accounts { hourly += try await store.rollupHourly(accountID: account, before: cut.hourly) }
    emit(hourly, before: cut.hourly)
    var monthly = RollupCount(tier: "monthly")
    for account in accounts {
      monthly += try await store.rollupMonthly(accountID: account, before: cut.monthly)
    }
    emit(monthly, before: cut.monthly)
    let purged = try await store.purgeHarnessEvents(before: cut.harness)
    emit(purged, before: cut.harness)
    var thinned = RollupCount(tier: "balance_snapshot")
    for account in accounts {
      thinned += try await store.thinBalanceSnapshots(accountID: account, before: cut.balance)
    }
    emit(thinned, before: cut.balance)
    return [hourly, monthly, purged, thinned]
  }

  private func emit(_ count: RollupCount, before: String) {
    log.emit(.info, .dbRollup, cat: .db, msg: "retention roll-up", ctx: [
      "tier": .string(count.tier), "rows_in": .int(count.rowsIn), "rows_out": .int(count.rowsOut),
      "before": .string(before)
    ])
  }

  /// The four cut-offs as `bucket_start` / `ts` strings: the start of the UTC day `days` before `now`; the monthly
  /// one is the first of that day's month, so only whole months older than 400 days are summed.
  struct Cutoffs: Equatable {
    var hourly: String
    var monthly: String
    var harness: String
    var balance: String

    init(_ policy: RetentionPolicy, now: Date) {
      func day(_ days: Int) -> String { DailyOnce.utcDay(now.addingTimeInterval(-86_400 * Double(days))) }
      hourly = day(policy.hourlyDays) + Self.midnight
      monthly = String(day(RetentionPolicy.monthlyAfterDays).prefix(7)) + "-01" + Self.midnight
      harness = day(policy.rawHarnessDays) + Self.midnight
      balance = day(RetentionPolicy.balanceFullRateDays) + Self.midnight
    }

    static let midnight = "T00:00:00.000Z"
  }
}

extension GRDBRepository {
  /// The summed columns of a roll-up, in `usage_bucket` order.
  static let tokenColumns = ["input_uncached", "cache_write_5m", "cache_write_1h", "cache_read", "output", "reasoning",
                             "requests"]

  public func rollupHourly(accountID: String, before: String) async throws -> RollupCount {
    try await database.write("rollupHourly") { db in
      let rows = """
        FROM usage_bucket WHERE account_id = ? AND bucket_width = '1h' AND bucket_start < ?
          AND substr(bucket_start, 1, 10) NOT IN (
            SELECT substr(ts, 1, 10) FROM ledger_event WHERE account_id = ? AND kind = 'anchor')
        """
      let arguments: StatementArguments = [accountID, before, accountID]
      let sums = Self.tokenColumns.map { "SUM(\($0))" }.joined(separator: ", ")
      let adds = Self.tokenColumns.map { "\($0) = \($0) + excluded.\($0)" }.joined(separator: ", ")
      try db.execute(sql: """
        INSERT INTO usage_bucket (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source,
          \(Self.tokenColumns.joined(separator: ", ")), est_cost_cents, unpriced, provisional, fetched_at)
        SELECT account_id, substr(bucket_start, 1, 10) || 'T00:00:00.000Z', '1d', model, provider_key_id, service_tier,
          CASE source WHEN 'harness' THEN 'harness' ELSE 'rollup' END, \(sums), SUM(est_cost_cents),
          CASE WHEN SUM(est_cost_cents) IS NULL THEN MAX(unpriced) ELSE 0 END, MAX(provisional), MAX(fetched_at)
        \(rows)
        GROUP BY account_id, substr(bucket_start, 1, 10), model, provider_key_id, service_tier,
          CASE source WHEN 'harness' THEN 'harness' ELSE 'rollup' END
        ON CONFLICT (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source) DO UPDATE SET
          \(adds),
          est_cost_cents = CASE WHEN est_cost_cents IS NULL AND excluded.est_cost_cents IS NULL THEN NULL
            ELSE COALESCE(est_cost_cents, 0) + COALESCE(excluded.est_cost_cents, 0) END,
          unpriced = CASE WHEN est_cost_cents IS NULL AND excluded.est_cost_cents IS NULL
            THEN max(unpriced, excluded.unpriced) ELSE 0 END,
          provisional = max(provisional, excluded.provisional), fetched_at = max(fetched_at, excluded.fetched_at)
        """, arguments: arguments)
      let written = db.changesCount
      try db.execute(sql: "DELETE \(rows)", arguments: arguments)
      return RollupCount(tier: "hourly", rowsIn: db.changesCount, rowsOut: written)
    }
  }

  public func rollupMonthly(accountID: String, before: String) async throws -> RollupCount {
    try await database.write("rollupMonthly") { db in
      let rows = "FROM usage_bucket WHERE account_id = ? AND bucket_width = '1d' AND bucket_start < ?"
      let sums = Self.tokenColumns.map { "SUM(\($0))" }.joined(separator: ", ")
      let sets = Self.tokenColumns.map { "\($0) = excluded.\($0)" }.joined(separator: ", ")
      let differs = (Self.tokenColumns + ["est_cost_cents", "unpriced", "provisional"])
        .map { "\($0) IS NOT excluded.\($0)" }.joined(separator: " OR ")
      let read = try Int.fetchOne(db, sql: "SELECT COUNT(*) \(rows)", arguments: [accountID, before]) ?? 0
      try db.execute(sql: """
        INSERT INTO usage_bucket (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source,
          \(Self.tokenColumns.joined(separator: ", ")), est_cost_cents, unpriced, provisional, fetched_at)
        SELECT account_id, substr(bucket_start, 1, 7) || '-01T00:00:00.000Z', '1mo', model, provider_key_id,
          service_tier, source, \(sums), SUM(est_cost_cents),
          CASE WHEN SUM(est_cost_cents) IS NULL THEN MAX(unpriced) ELSE 0 END, MAX(provisional), MAX(fetched_at)
        \(rows)
        GROUP BY account_id, substr(bucket_start, 1, 7), model, provider_key_id, service_tier, source
        ON CONFLICT (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source) DO UPDATE SET
          \(sets), est_cost_cents = excluded.est_cost_cents, unpriced = excluded.unpriced,
          provisional = excluded.provisional, fetched_at = excluded.fetched_at
        WHERE \(differs)
        """, arguments: [accountID, before])
      return RollupCount(tier: "monthly", rowsIn: read, rowsOut: db.changesCount)
    }
  }

  public func purgeHarnessEvents(before: String) async throws -> RollupCount {
    try await database.write("purgeHarnessEvents") { db in
      let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM harness_event") ?? 0
      try db.execute(sql: "DELETE FROM harness_event WHERE ts < ?", arguments: [before])
      return RollupCount(tier: "harness_event", rowsIn: total, rowsOut: db.changesCount)
    }
  }

  public func thinBalanceSnapshots(accountID: String, before: String) async throws -> RollupCount {
    try await database.write("thinBalanceSnapshots") { db in
      let old = "FROM balance_snapshot WHERE account_id = ? AND ts < ?"
      let read = try Int.fetchOne(db, sql: "SELECT COUNT(*) \(old)", arguments: [accountID, before]) ?? 0
      try db.execute(sql: """
        DELETE \(old) AND (ts, currency) NOT IN (
          SELECT MIN(ts), currency \(old) GROUP BY substr(ts, 1, 10), currency
          UNION SELECT MAX(ts), currency \(old) GROUP BY substr(ts, 1, 10), currency)
        """, arguments: [accountID, before, accountID, before, accountID, before])
      return RollupCount(tier: "balance_snapshot", rowsIn: read, rowsOut: db.changesCount)
    }
  }
}
