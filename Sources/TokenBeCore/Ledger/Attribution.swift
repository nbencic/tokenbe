import Foundation
import GRDB

/// One account's usage of one provider key on one UTC day, by source (06 § Attribution precedence).
public struct KeyUsageDay: Sendable, Equatable {
  public var accountId: String
  /// `YYYY-MM-DD`, UTC.
  public var day: String
  /// `''` for usage the provider did not group by key.
  public var providerKeyId: String
  public var source: String
  /// Σ `est_cost_cents` of the priced buckets.
  public var estCents: Int64
  /// Token classes and requests.
  public var classes: TokenClasses

  public init(accountId: String, day: String, providerKeyId: String, source: String, estCents: Int64,
              classes: TokenClasses) {
    self.accountId = accountId
    self.day = day
    self.providerKeyId = providerKeyId
    self.source = source
    self.estCents = estCents
    self.classes = classes
  }

  static func fetch(_ db: GRDB.Database, since: String) throws -> [KeyUsageDay] {
    try Row.fetchAll(db, sql: """
      SELECT account_id, substr(bucket_start, 1, 10) AS day, provider_key_id, source,
             SUM(COALESCE(est_cost_cents, 0)) AS est, SUM(input_uncached) AS iu, SUM(cache_write_5m) AS cw5,
             SUM(cache_write_1h) AS cw1, SUM(cache_read) AS cr, SUM(output) AS out, SUM(reasoning) AS rsn,
             SUM(requests) AS req
      FROM usage_bucket WHERE bucket_start >= ?
      GROUP BY account_id, day, provider_key_id, source ORDER BY account_id, day, provider_key_id, source
      """, arguments: [since]).map {
      KeyUsageDay(accountId: $0["account_id"], day: $0["day"], providerKeyId: $0["provider_key_id"],
                  source: $0["source"], estCents: $0["est"], classes: TokenClasses(
                    inputUncached: $0["iu"], cacheWrite5m: $0["cw5"], cacheWrite1h: $0["cw1"], cacheRead: $0["cr"],
                    output: $0["out"], reasoning: $0["rsn"], requests: $0["req"]))
    }
  }
}

/// The provider's cost of one key on one UTC day (`cost_bucket`, `group_kind = 'api_key_id'`).
public struct KeyCostDay: Sendable, Equatable {
  public var accountId: String
  public var day: String
  public var providerKeyId: String
  public var amountCents: Int64

  public init(accountId: String, day: String, providerKeyId: String, amountCents: Int64) {
    self.accountId = accountId
    self.day = day
    self.providerKeyId = providerKeyId
    self.amountCents = amountCents
  }
}

/// How a row's spend was attributed (08 By-app badge, 06 precedence): a provider key (`key`), a key's total split
/// among the harness apps that used it (`split`), harness lines as the only spend (`harness`), a balance delta
/// (`inferred`).
public enum AttributionKind: String, Sendable, Equatable {
  case key, split, harness, inferred
}

/// One row of the By-app table (08 `20N-0`), of popover row 4 and of Apps this period: one provider key of one
/// account, and the app it is bound to (14 § 0.3 `AppRow`).
public struct AppRow: Sendable, Equatable, Identifiable {
  /// `<account id>/<provider key id>[/<app tag>/<kind>]`.
  public var id: String {
    appTag.map { "\(accountID)/\(providerKeyID)/\($0)/\(kind.rawValue)" } ?? "\(accountID)/\(providerKeyID)"
  }
  /// What the UI names the row's elements by: the key for a key row, else the app tag (7.2).
  public var elementID: String { appTag ?? providerKeyID }
  public var accountID: String
  /// `''` for the usage the provider did not group by key (the `Unassigned` row, Q-048).
  public var providerKeyID: String
  /// The bound app (or the `unassigned` sentinel for `''`); nil for an unbound key.
  public var appID: String?
  /// The app's display name; nil for an unbound key (the UI names it from `keyName`/`keyHint`, Q-048).
  public var appName: String?
  /// The provider's name for the key (`provider_key.name`).
  public var keyName: String?
  /// The harness app tag of a `split`, `harness` or `inferred` row (06); nil for a key row.
  public var appTag: String?
  /// The last 4 characters of the provider's redacted key (`…a9f2`); nil when unknown.
  public var keyHint: String?
  public var kind: AttributionKind
  public var tokens: TokenClasses
  public var spend: SpendFigure
  /// `spend ÷ total`, in whole percent rounded half up; 0 when the total is 0.
  public var sharePercent: Int

  public init(accountID: String, providerKeyID: String, appID: String?, appName: String?, keyName: String?,
              keyHint: String?, kind: AttributionKind = .key, tokens: TokenClasses, spend: SpendFigure,
              sharePercent: Int = 0, appTag: String? = nil) {
    self.accountID = accountID
    self.providerKeyID = providerKeyID
    self.appID = appID
    self.appName = appName
    self.keyName = keyName
    self.keyHint = keyHint
    self.kind = kind
    self.tokens = tokens
    self.spend = spend
    self.sharePercent = sharePercent
    self.appTag = appTag
  }
}

/// The By-app table's `Total` row (08): Σ of the rows' requests, tokens and spend, computed in Core (04 I3).
public struct AppRowsTotal: Sendable, Equatable {
  public var tokens: TokenClasses
  public var spend: SpendFigure

  public init(tokens: TokenClasses = TokenClasses(), spend: SpendFigure = SpendFigure(cents: 0, isEstimate: false)) {
    self.tokens = tokens
    self.spend = spend
  }
}

/// One app's spend across accounts (08 Overview `Apps this period`): its rows summed per currency, never across
/// currencies (05).
public struct AppTotal: Sendable, Equatable, Identifiable {
  /// `<app id or account/key>/<currency>`.
  public var id: String
  /// A row of the app: the name and kind come from it.
  public var row: AppRow
  public var currency: Currency
  public var spend: SpendFigure
}

/// 06 § Attribution precedence, the key path (14 § Stage 7.1 step 1). For an account whose provider reports usage per
/// key (`capabilities.perKeyUsage`), each UTC day's spend (`Spend.daily`: the provider's cost on a closed day with a
/// cost row, else the usage estimate) is attributed to the day's provider keys:
/// - a closed day with the provider's per-key cost rows: each key's cost;
/// - a closed day with only the account's total: the total split by each key's estimate (by tokens when no key has
///   an estimate);
/// - the open day and days without cost rows: each key's estimate.
/// Whatever the per-key figures leave of the day's spend (rounding, rows without a key) goes to the day's largest
/// key, so Σ rows == the account's spend for the range, always (08 `Total`). Keys map to apps through
/// `app_binding(kind = provider_key)`. A key's day that harness lines reported for is split among their apps
/// (`split`, 7.2); an account without a usage API takes its rows from harness lines (`Attribution+Harness`).
public enum Attribution {
  /// The rows of one account over `days`, by spend (largest first), then name.
  public static func rows(_ account: AccountSummary, days: [String], today: String,
                          inputs: SummaryInputs) -> [AppRow] {
    let rows: Accumulator
    if account.capabilities?.perKeyUsage == true {
      rows = keyRows(account, days: days, today: today, inputs: inputs)
    } else if account.capabilities?.usage == false {
      rows = harnessRows(account, days: days, today: today, inputs: inputs)
    } else {
      return []
    }
    let total = rows.cents.values.reduce(0, +)
    return Set(rows.cents.keys).union(rows.tokens.keys).map { key in
      let spend = SpendFigure(cents: rows.cents[key] ?? 0, isEstimate: rows.estimate[key] ?? false)
      var row = describe(key, accountID: account.id, inputs: inputs, tokens: rows.tokens[key] ?? TokenClasses(),
                         spend: spend)
      row.sharePercent = percent(spend.cents, of: total)
      return row
    }.sorted(by: order)
  }

  /// The key path: each day's share per key, split among the key's harness apps when they reported that day.
  static func keyRows(_ account: AccountSummary, days: [String], today: String, inputs: SummaryInputs) -> Accumulator {
    let usageAPI = account.capabilities?.usage ?? true
    let daily = Spend.daily(account, today: today, inputs: inputs)
    let wanted = Set(days)
    let usage = Dictionary(grouping: inputs.keyUsageDays.filter {
      $0.accountId == account.id && wanted.contains($0.day)
        && Spend.counts($0.source, usageAPI: usageAPI, currency: account.currency)
    }, by: \.day)
    let costs = Dictionary(grouping: inputs.keyCostDays.filter { $0.accountId == account.id && wanted.contains($0.day) },
                           by: \.day)
    let harness = Dictionary(grouping: inputs.harnessDays.filter {
      $0.accountId == account.id && wanted.contains($0.day) && !$0.providerKeyId.isEmpty
    }) { "\($0.day)/\($0.providerKeyId)" }
    var rows = Accumulator()
    for day in days {
      guard let figure = daily[day] else { continue }
      let dayUsage = usage[day] ?? []
      for (key, amount) in dayShares(figure: figure, usage: dayUsage, costs: costs[day] ?? []) {
        if let lines = harness["\(day)/\(key)"] {
          for (app, cents) in splitByApp(amount, lines: lines) {
            let classes = lines.filter { $0.appTag == app }.reduce(TokenClasses()) { $0 + $1.classes }
            rows.add(RowKey(key: key, app: app, kind: .split), cents: cents, estimate: true, tokens: classes)
          }
        } else {
          let classes = dayUsage.filter { $0.providerKeyId == key }.reduce(TokenClasses()) { $0 + $1.classes }
          rows.add(RowKey(key: key, app: nil, kind: .key), cents: amount, estimate: figure.isEstimate, tokens: classes)
        }
      }
    }
    return rows
  }

  /// One day's spend per key; Σ == `figure.cents`.
  static func dayShares(figure: SpendFigure, usage: [KeyUsageDay], costs: [KeyCostDay]) -> [String: Int64] {
    var estimates: [String: Int64] = [:]
    var tokenCounts: [String: Int64] = [:]
    for row in usage {
      estimates[row.providerKeyId, default: 0] += row.estCents
      tokenCounts[row.providerKeyId, default: 0] += row.classes.tokens
    }
    var shares: [String: Int64]
    if !figure.isEstimate, !costs.isEmpty {
      shares = Dictionary(costs.map { ($0.providerKeyId, $0.amountCents) }, uniquingKeysWith: +)
    } else if !figure.isEstimate {
      let weights = estimates.values.contains { $0 > 0 } ? estimates : tokenCounts
      shares = split(figure.cents, by: weights)
    } else {
      shares = estimates
    }
    let left = figure.cents - shares.values.reduce(0, +)
    if left != 0 {
      let weights = shares.isEmpty ? tokenCounts : shares
      shares[largest(weights) ?? "", default: 0] += left
    }
    return shares
  }

  /// `amount` split in proportion to `weights` (floors), the remainder to the largest weight. Zero weights: all to
  /// the largest key (or none when there are no keys; the caller adds the remainder).
  static func split(_ amount: Int64, by weights: [String: Int64]) -> [String: Int64] {
    let sum = weights.values.reduce(0, +)
    guard sum > 0 else { return [:] }
    var shares = weights.mapValues { Int64((Int128($0) * Int128(amount)) / Int128(sum)) }
    let left = amount - shares.values.reduce(0, +)
    if left != 0, let top = largest(weights) { shares[top, default: 0] += left }
    return shares
  }

  /// The key with the largest value; ties go to the smallest key id, so the result never depends on order.
  static func largest(_ values: [String: Int64]) -> String? {
    values.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
  }

  static func percent(_ part: Int64, of total: Int64) -> Int {
    guard total > 0 else { return 0 }
    return Int((Int128(part) * 200 + Int128(total)) / (Int128(total) * 2))
  }

  static func describe(_ row: RowKey, accountID: String, inputs: SummaryInputs, tokens: TokenClasses,
                       spend: SpendFigure) -> AppRow {
    let key = row.key
    let providerKey = inputs.providerKeys.first { $0.accountId == accountID && $0.providerKeyId == key }
    let appID: String? = if let tag = row.app {
      inputs.apps.first { $0.name == tag }?.id
    } else if key.isEmpty {
      unassignedID
    } else {
      inputs.bindings.first { $0.accountId == accountID && $0.kind == "provider_key" && $0.value == key }?.appId
    }
    let app = appID.flatMap { id in inputs.apps.first { $0.id == id } }
    let hint = providerKey?.redacted.flatMap { $0.count >= 4 ? String($0.suffix(4)) : nil }
    return AppRow(accountID: accountID, providerKeyID: key, appID: app?.id, appName: app?.displayName ?? row.app,
                  keyName: providerKey?.name, keyHint: hint, kind: row.kind, tokens: tokens, spend: spend,
                  appTag: row.app)
  }

  /// Largest spend first, then the name the UI shows, then the key id.
  static func order(_ lhs: AppRow, _ rhs: AppRow) -> Bool {
    if lhs.spend.cents != rhs.spend.cents { return lhs.spend.cents > rhs.spend.cents }
    let lhsName = lhs.appName ?? lhs.keyName ?? "", rhsName = rhs.appName ?? rhs.keyName ?? ""
    return (lhsName, lhs.providerKeyID, lhs.kind.rawValue) < (rhsName, rhs.providerKeyID, rhs.kind.rawValue)
  }

  /// The `Total` row of `rows`; nil when there are none.
  public static func total(_ rows: [AppRow]) -> AppRowsTotal? {
    guard !rows.isEmpty else { return nil }
    return AppRowsTotal(tokens: rows.reduce(TokenClasses()) { $0 + $1.tokens }, spend: Spend.sum(rows.map(\.spend)))
  }

  /// 03's sentinel app (V4).
  public static let unassignedID = "app_unassigned"

  /// Popover row 4 (08): the top 3 rows by today's spend; with more than 3, the third entry is `other`, the sum of
  /// the rest (Q-048). Rows without spend are left out.
  public static func top(_ rows: [AppRow], limit: Int = 3) -> (rows: [AppRow], other: SpendFigure?) {
    let spending = rows.filter { $0.spend.cents > 0 }
    guard spending.count > limit else { return (spending, nil) }
    let rest = spending.dropFirst(limit - 1)
    return (Array(spending.prefix(limit - 1)), Spend.sum(rest.map(\.spend)))
  }

  /// Overview `Apps this period` (08): every account's rows summed per app and currency (an unbound key is its own
  /// entry), largest first, at most `limit`.
  public static func totals(_ accounts: [AccountSummary], limit: Int = 8) -> [AppTotal] {
    var totals: [String: AppTotal] = [:]
    var seen: [String] = []
    for account in accounts {
      for row in account.byApp {
        let id = "\(row.appID ?? row.id)/\(row.kind.rawValue)/\(account.currency.rawValue)"
        if totals[id] == nil {
          seen.append(id)
          totals[id] = AppTotal(id: id, row: row, currency: account.currency,
                                spend: SpendFigure(cents: 0, isEstimate: false))
        }
        if var total = totals[id] {
          total.spend = Spend.sum([total.spend, row.spend])
          totals[id] = total
        }
      }
    }
    let spending = seen.compactMap { totals[$0] }.filter { $0.spend.cents > 0 }
    return Array(spending.sorted { $0.spend.cents > $1.spend.cents }.prefix(limit))
  }
}
