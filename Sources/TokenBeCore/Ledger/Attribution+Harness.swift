import Foundation
import GRDB

/// One account's harness lines on one UTC day for one app tag and resolved key (06 precedence weights).
public struct HarnessDay: Sendable, Equatable {
  public var accountId: String
  public var day: String
  public var appTag: String
  /// `''` when the line's key hint resolved to no key.
  public var providerKeyId: String
  /// Σ `est_cost_cents` (unpriced lines count 0).
  public var estCents: Int64
  /// Σ classes; `requests` is the number of lines.
  public var classes: TokenClasses

  public init(accountId: String, day: String, appTag: String, providerKeyId: String = "", estCents: Int64,
              classes: TokenClasses) {
    self.accountId = accountId
    self.day = day
    self.appTag = appTag
    self.providerKeyId = providerKeyId
    self.estCents = estCents
    self.classes = classes
  }

  static func fetch(_ db: GRDB.Database, since: String) throws -> [HarnessDay] {
    func sum(_ field: String) -> String { "SUM(COALESCE(json_extract(classes_json, '$.\(field)'), 0))" }
    return try Row.fetchAll(db, sql: """
      SELECT account_id, substr(ts, 1, 10) AS day, app_tag, COALESCE(provider_key_id, '') AS key_id,
             SUM(COALESCE(est_cost_cents, 0)) AS est, COUNT(*) AS lines, \(sum("input_uncached")) AS iu,
             \(sum("cache_write_5m")) AS cw5, \(sum("cache_write_1h")) AS cw1, \(sum("cache_read")) AS cr,
             \(sum("output")) AS out, \(sum("reasoning")) AS rsn
      FROM harness_event WHERE account_id IS NOT NULL AND ts >= ?
      GROUP BY account_id, day, app_tag, key_id ORDER BY account_id, day, app_tag, key_id
      """, arguments: [since]).map {
      HarnessDay(accountId: $0["account_id"], day: $0["day"], appTag: $0["app_tag"], providerKeyId: $0["key_id"],
                 estCents: $0["est"], classes: TokenClasses(
                   inputUncached: $0["iu"], cacheWrite5m: $0["cw5"], cacheWrite1h: $0["cw1"], cacheRead: $0["cr"],
                   output: $0["out"], reasoning: $0["rsn"], requests: $0["lines"]))
    }
  }
}

/// An account's last balance on a UTC day in one currency (`balance_snapshot`, 03).
public struct BalanceDay: Sendable, Equatable {
  public var accountId: String
  public var day: String
  public var currency: String
  public var amountCents: Int64

  public init(accountId: String, day: String, currency: String, amountCents: Int64) {
    self.accountId = accountId
    self.day = day
    self.currency = currency
    self.amountCents = amountCents
  }

  static func fetch(_ db: GRDB.Database, since: String) throws -> [BalanceDay] {
    try Row.fetchAll(db, sql: """
      SELECT b.account_id, substr(b.ts, 1, 10) AS day, b.currency, b.amount_cents FROM balance_snapshot b
      WHERE b.ts >= ? AND b.ts = (SELECT max(c.ts) FROM balance_snapshot c WHERE c.account_id = b.account_id
        AND c.currency = b.currency AND substr(c.ts, 1, 10) = substr(b.ts, 1, 10))
      ORDER BY b.account_id, day, b.currency
      """, arguments: [since]).map {
      BalanceDay(accountId: $0["account_id"], day: $0["day"], currency: $0["currency"], amountCents: $0["amount_cents"])
    }
  }
}

/// 06 § Attribution precedence 1 (split) and 2 (substitute, inferred), and the reconciliation (`ledger.harness_drift`),
/// 14 § Stage 7.2 step 5. Every day's spend is `Spend.daily`'s, so the rows still add up to the provider total.
extension Attribution {
  /// A row's identity while the days are summed: the key, the app tag, the kind.
  struct RowKey: Hashable {
    var key: String
    var app: String?
    var kind: AttributionKind
  }

  /// Σ cents, estimate flag and tokens per row.
  struct Accumulator {
    var cents: [RowKey: Int64] = [:]
    var estimate: [RowKey: Bool] = [:]
    var tokens: [RowKey: TokenClasses] = [:]

    mutating func add(_ row: RowKey, cents amount: Int64, estimate isEstimate: Bool, tokens classes: TokenClasses) {
      cents[row, default: 0] += amount
      estimate[row] = (estimate[row] ?? false) || isEstimate
      tokens[row, default: TokenClasses()] += classes
    }
  }

  /// Splits `amount` among the harness apps of `lines` by their estimate (by tokens when none has one); Σ == amount.
  static func splitByApp(_ amount: Int64, lines: [HarnessDay]) -> [String: Int64] {
    var estimates: [String: Int64] = [:]
    var tokens: [String: Int64] = [:]
    for line in lines {
      estimates[line.appTag, default: 0] += line.estCents
      tokens[line.appTag, default: 0] += line.classes.tokens + line.classes.requests
    }
    let weights = estimates.values.contains { $0 > 0 } ? estimates : tokens
    var shares = split(amount, by: weights)
    let left = amount - shares.values.reduce(0, +)
    if left != 0, let top = largest(weights) { shares[top, default: 0] += left }
    return shares
  }

  /// 06 precedence 2 for an account without a usage API: each day's harness spend (USD accounts) split by app with
  /// badge `harness`; an inferred day's balance delta to its single app with badge `inferred`.
  static func harnessRows(_ account: AccountSummary, days: [String], today: String,
                          inputs: SummaryInputs) -> Accumulator {
    let daily = Spend.daily(account, today: today, inputs: inputs)
    let inferred = inferredDays(account, today: today, inputs: inputs)
    let single = harnessApps(account.id, inputs: inputs).first
    let lines = Dictionary(grouping: inputs.harnessDays.filter { $0.accountId == account.id }, by: \.day)
    var rows = Accumulator()
    for day in days {
      guard let figure = daily[day] else { continue }
      if inferred[day] != nil, let single {
        rows.add(RowKey(key: "", app: single, kind: .inferred), cents: figure.cents, estimate: true, tokens: TokenClasses())
        continue
      }
      let dayLines = lines[day] ?? []
      guard !dayLines.isEmpty else {
        rows.add(RowKey(key: "", app: nil, kind: .harness), cents: figure.cents, estimate: figure.isEstimate,
                 tokens: TokenClasses())
        continue
      }
      for (app, cents) in splitByApp(figure.cents, lines: dayLines) {
        let classes = dayLines.filter { $0.appTag == app }.reduce(TokenClasses()) { $0 + $1.classes }
        rows.add(RowKey(key: "", app: app, kind: .harness), cents: cents, estimate: figure.isEstimate, tokens: classes)
      }
    }
    return rows
  }

  /// The tags bound to the account by `harness_tag` (06 processLine), sorted.
  static func harnessApps(_ accountID: String, inputs: SummaryInputs) -> [String] {
    inputs.bindings.filter { $0.accountId == accountID && $0.kind == "harness_tag" }.map(\.value).sorted()
  }

  /// D-deepseek-single-app (06): for an account without a usage API that has exactly one harness app, each closed day
  /// with no harness lines and no top-up takes the day's balance delta, when the balance fell; in the account's
  /// currency (Q-049).
  public static func inferredDays(_ account: AccountSummary, today: String, inputs: SummaryInputs) -> [String: Int64] {
    guard account.capabilities?.usage == false, harnessApps(account.id, inputs: inputs).count == 1 else { return [:] }
    let withLines = Set(inputs.harnessDays.filter { $0.accountId == account.id }.map(\.day))
    let topUps = Set(inputs.ledgerEvents.filter { $0.accountId == account.id && $0.kind == "topup" }
      .map { String($0.ts.prefix(10)) })
    var result: [String: Int64] = [:]
    for (day, delta) in balanceDeltas(account, inputs: inputs)
    where day < today && !withLines.contains(day) && !topUps.contains(day) && delta > 0 {
      result[day] = delta
    }
    return result
  }

  /// Per closed UTC day with a balance: the previous day's last balance minus this day's, in the account's currency.
  static func balanceDeltas(_ account: AccountSummary, inputs: SummaryInputs) -> [String: Int64] {
    let days = inputs.balanceDays.filter { $0.accountId == account.id && $0.currency == account.currency.rawValue }
      .sorted { $0.day < $1.day }
    var result: [String: Int64] = [:]
    for (previous, current) in zip(days, days.dropFirst()) {
      result[current.day] = previous.amountCents - current.amountCents
    }
    return result
  }

  /// 06 precedence 2 reconciliation: on a closed day of a USD direct account without a usage API, with harness lines
  /// and no top-up, Σ harness `est_cost_cents` against the balance delta. Returns `harness − delta` (cents) when it
  /// differs from the delta by more than `thresholdPct` % of the delta (09 `tb.alerts.driftThresholdPct`; Q-049).
  public static func harnessDrift(_ account: AccountSummary, day: String, inputs: SummaryInputs,
                                  thresholdPct: Int) -> Int64? {
    guard account.capabilities?.usage == false, account.mode == .direct, account.currency == .usd,
          let delta = balanceDeltas(account, inputs: inputs)[day], delta > 0,
          !inputs.ledgerEvents.contains(where: { $0.accountId == account.id && $0.kind == "topup" && $0.ts.hasPrefix(day) })
    else { return nil }
    let lines = inputs.harnessDays.filter { $0.accountId == account.id && $0.day == day }
    guard !lines.isEmpty else { return nil }
    let difference = lines.reduce(Int64(0)) { $0 + $1.estCents } - delta
    return abs(difference) * 100 > Int64(thresholdPct) * delta ? difference : nil
  }

  /// The daily activity's `harness drift` step: one `ledger.harness_drift {acct, day, delta_cents}` per account whose
  /// harness spend yesterday (UTC, the last closed day) drifted from its balance delta. Returns the accounts logged.
  @discardableResult
  public static func reportDrift(_ inputs: SummaryInputs, now: Date, thresholdPct: Int,
                                 log: EventLog = EventLog()) -> [String] {
    let day = DailyOnce.utcDay(now.addingTimeInterval(-86_400))
    var logged: [String] = []
    for account in AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: now)) {
      guard let delta = harnessDrift(account, day: day, inputs: inputs, thresholdPct: thresholdPct) else { continue }
      log.emit(.warn, .ledgerHarnessDrift, cat: .ledger, msg: "harness spend drifted from the balance delta",
               acct: account.provider.rawValue, ctx: ["day": .string(day), "delta_cents": .int(Int(delta))])
      logged.append(account.id)
    }
    return logged
  }
}
