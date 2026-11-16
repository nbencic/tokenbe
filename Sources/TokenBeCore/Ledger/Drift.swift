import Foundation
import GRDB

/// One model's usage on one UTC day, by source (the By-model table, 14 § Stage 8.1), summed in SQL from
/// `usage_bucket`. Priced and unpriced buckets are kept apart, so an unpriced model never reads as `$0` (A6).
public struct ModelUsageDay: Sendable, Equatable {
  public var accountId: String
  /// `YYYY-MM-DD`, UTC.
  public var day: String
  public var model: String
  public var source: String
  /// Σ `est_cost_cents` of the priced buckets.
  public var estCents: Int64
  /// Buckets with `unpriced = 1` (05: their `est_cost_cents` is NULL).
  public var unpricedBuckets: Int64
  /// Token classes and requests of every bucket, priced or not.
  public var classes: TokenClasses

  public init(accountId: String, day: String, model: String, source: String, estCents: Int64,
              unpricedBuckets: Int64 = 0, classes: TokenClasses) {
    self.accountId = accountId
    self.day = day
    self.model = model
    self.source = source
    self.estCents = estCents
    self.unpricedBuckets = unpricedBuckets
    self.classes = classes
  }

  static func fetch(_ db: GRDB.Database, since: String) throws -> [ModelUsageDay] {
    try Row.fetchAll(db, sql: """
      SELECT account_id, substr(bucket_start, 1, 10) AS day, model, source,
             SUM(CASE WHEN unpriced = 0 THEN COALESCE(est_cost_cents, 0) ELSE 0 END) AS est,
             SUM(CASE WHEN unpriced = 1 OR est_cost_cents IS NULL THEN 1 ELSE 0 END) AS unpriced_buckets,
             SUM(input_uncached) AS iu, SUM(cache_write_5m) AS cw5, SUM(cache_write_1h) AS cw1,
             SUM(cache_read) AS cr, SUM(output) AS out, SUM(reasoning) AS rsn, SUM(requests) AS req
      FROM usage_bucket WHERE bucket_start >= ?
      GROUP BY account_id, day, model, source ORDER BY account_id, day, model, source
      """, arguments: [since]).map {
      ModelUsageDay(accountId: $0["account_id"], day: $0["day"], model: $0["model"], source: $0["source"],
                    estCents: $0["est"], unpricedBuckets: $0["unpriced_buckets"], classes: TokenClasses(
                      inputUncached: $0["iu"], cacheWrite5m: $0["cw5"], cacheWrite1h: $0["cw1"], cacheRead: $0["cr"],
                      output: $0["out"], reasoning: $0["rsn"], requests: $0["req"]))
    }
  }
}

/// The provider's cost of one line item on one UTC day (`cost_bucket`, `group_kind = 'line_item'`, OpenAI; 05 § Drift).
public struct LineItemCostDay: Sendable, Equatable {
  public var accountId: String
  public var day: String
  public var lineItem: String
  public var amountCents: Int64

  public init(accountId: String, day: String, lineItem: String, amountCents: Int64) {
    self.accountId = accountId
    self.day = day
    self.lineItem = lineItem
    self.amountCents = amountCents
  }

  static func fetch(_ db: GRDB.Database, since: String) throws -> [LineItemCostDay] {
    try Row.fetchAll(db, sql: """
      SELECT account_id, day, group_key, SUM(amount_cents) AS amount FROM cost_bucket
      WHERE group_kind = 'line_item' AND day >= ? GROUP BY account_id, day, group_key
      ORDER BY account_id, day, group_key
      """, arguments: [String(since.prefix(10))]).map {
      LineItemCostDay(accountId: $0["account_id"], day: $0["day"], lineItem: $0["group_key"], amountCents: $0["amount"])
    }
  }
}

/// A model's drift (05 § Drift) over the closed days of the range that have a provider cost row for it: the
/// estimate and the provider's cost over exactly those days, so the cell's help can name both figures (Q-051).
public struct ModelDrift: Sendable, Equatable {
  public var days: Int
  public var estCents: Int64
  public var providerCents: Int64
  /// `(est − provider) / provider` in hundredths of a percent, rounded half away from zero.
  public var basisPoints: Int64
  /// `|drift| > tb.alerts.driftThresholdPct` (09), compared in integers.
  public var flagged: Bool

  public init(days: Int, estCents: Int64, providerCents: Int64, basisPoints: Int64, flagged: Bool) {
    self.days = days
    self.estCents = estCents
    self.providerCents = providerCents
    self.basisPoints = basisPoints
    self.flagged = flagged
  }
}

/// One row of the By-model table (08 § Account detail 5, Paper `G7-0`) over the Dashboard range.
public struct ModelRow: Sendable, Equatable, Identifiable {
  public var model: String
  public var tokens: TokenClasses
  /// Σ the estimate over the range; nil when any of the model's buckets in the range is unpriced (A6).
  public var estCents: Int64?
  public var unpriced: Bool
  /// Σ the provider cost rows mapped to the model, closed days of the range; nil when there is none (`—`).
  public var providerCents: Int64?
  /// Nil (`—`) without a provider cost row, for an unpriced model, or when the provider's cost is 0 (05).
  public var drift: ModelDrift?

  public var id: String { model }

  public init(model: String, tokens: TokenClasses, estCents: Int64?, unpriced: Bool, providerCents: Int64?,
              drift: ModelDrift?) {
    self.model = model
    self.tokens = tokens
    self.estCents = estCents
    self.unpriced = unpriced
    self.providerCents = providerCents
    self.drift = drift
  }
}

/// 05 § Drift (14 § Stage 8.1): the By-model table, and the daily `ledger.drift` check of yesterday. Not the harness
/// drift of 06 precedence 2 (`Attribution.harnessDrifts`, Q-050).
public enum Drift {
  /// The usage model a line item names (05: "by exact model name within the line item string"): the longest of
  /// `models` that occurs in it bounded on both sides by the string's ends or a character no model name uses, so
  /// `gpt-4o-mini, input` maps to `gpt-4o-mini`, never to `gpt-4o` (Q-051). Nil when none occurs.
  public static func lineItemModel(_ lineItem: String, models: [String]) -> String? {
    models.filter { !$0.isEmpty && occurs($0, in: lineItem) }
      .max { ($0.count, $1) < ($1.count, $0) }
  }

  static func occurs(_ model: String, in text: String) -> Bool {
    var searchStart = text.startIndex
    while let range = text.range(of: model, range: searchStart..<text.endIndex) {
      let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
      let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
      if !(before.map(isNameCharacter) ?? false) && !(after.map(isNameCharacter) ?? false) { return true }
      searchStart = text.index(after: range.lowerBound)
    }
    return false
  }

  /// Letters, digits and the separators model ids use (`gpt-4o-2024-08-06`, `claude-3.5`, `deepseek/chat:free`).
  static func isNameCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || "-_.:/".contains(character)
  }

  /// The table over `days`, today included for the usage columns; the provider cost and the drift take closed days
  /// only (`day < today`). Sources follow `Spend.counts` (harness rows only for a USD account without a usage API).
  /// Sorted by estimate, largest first, unpriced models last, then by name.
  public static func rows(_ account: AccountSummary, days: [String], today: String, inputs: SummaryInputs,
                          thresholdPct: Int) -> [ModelRow] {
    let usageAPI = account.capabilities?.usage ?? true
    let usage = inputs.modelUsageDays.filter {
      $0.accountId == account.id && Spend.counts($0.source, usageAPI: usageAPI, currency: account.currency)
    }
    let wanted = Set(days)
    let inRange = usage.filter { wanted.contains($0.day) }
    let costs = mappedCosts(account, models: Array(Set(usage.map(\.model))).sorted(), inputs: inputs)
    var rows: [ModelRow] = []
    for model in Set(inRange.map(\.model)) {
      let mine = inRange.filter { $0.model == model }
      let unpriced = mine.contains { $0.unpricedBuckets > 0 }
      let closed = days.filter { $0 < today }
      let provider = closed.compactMap { costs[DayModel(day: $0, model: model)] }
      rows.append(ModelRow(
        model: model, tokens: mine.reduce(TokenClasses()) { $0 + $1.classes },
        estCents: unpriced ? nil : mine.reduce(0) { $0 + $1.estCents }, unpriced: unpriced,
        providerCents: provider.isEmpty ? nil : provider.reduce(0, +),
        drift: unpriced ? nil : drift(mine, days: closed, model: model, costs: costs, thresholdPct: thresholdPct)
      ))
    }
    return rows.sorted { ($0.estCents ?? -1, $1.model) > ($1.estCents ?? -1, $0.model) }
  }

  struct DayModel: Hashable {
    var day: String
    var model: String
  }

  /// The account's line-item cost per day and model, for an account with a cost API (05 `spend_truth`).
  static func mappedCosts(_ account: AccountSummary, models: [String],
                          inputs: SummaryInputs) -> [DayModel: Int64] {
    guard account.capabilities?.cost ?? false else { return [:] }
    var result: [DayModel: Int64] = [:]
    var mapping: [String: String?] = [:]
    for cost in inputs.lineItemCostDays where cost.accountId == account.id {
      let model = mapping[cost.lineItem] ?? lineItemModel(cost.lineItem, models: models)
      mapping[cost.lineItem] = model
      guard let model else { continue }
      result[DayModel(day: cost.day, model: model), default: 0] += cost.amountCents
    }
    return result
  }

  /// 05: over the closed `days` with a cost row for the model, `(Σ est − Σ cost) / Σ cost`; nil when there is no
  /// such day or the cost is not positive.
  static func drift(_ usage: [ModelUsageDay], days: [String], model: String, costs: [DayModel: Int64],
                    thresholdPct: Int) -> ModelDrift? {
    let matched = days.filter { costs[DayModel(day: $0, model: model)] != nil }
    let provider = matched.reduce(Int64(0)) { $0 + (costs[DayModel(day: $1, model: model)] ?? 0) }
    guard !matched.isEmpty, provider > 0 else { return nil }
    let wanted = Set(matched)
    let estimate = usage.filter { wanted.contains($0.day) }.reduce(Int64(0)) { $0 + $1.estCents }
    let delta = Int128(estimate) - Int128(provider)
    let truth = Int128(provider)
    let scaled = delta * 10_000
    let basisPoints = (scaled + (scaled >= 0 ? truth / 2 : -truth / 2)) / truth
    let magnitude = delta < 0 ? -delta : delta
    return ModelDrift(days: matched.count, estCents: estimate, providerCents: provider,
                      basisPoints: Int64(clamping: basisPoints),
                      flagged: magnitude * 100 > Int128(thresholdPct) * truth)
  }

  /// The daily step after the cost polls (04 § Daily activity; 14 § Stage 8.1): each model whose estimate
  /// drifted from the provider's cost yesterday (UTC) logs `ledger.drift {acct, model, drift_pct}` once per
  /// account, model and day (`once`), at `warn` (07). Returns the `account/model` pairs it logged.
  @discardableResult
  public static func report(_ inputs: SummaryInputs, now: Date, thresholdPct: Int, once: DailyOnce,
                            log: EventLog = EventLog()) -> [String] {
    let today = DailyOnce.utcDay(now)
    let yesterday = DailyOnce.utcDay(now.addingTimeInterval(-86_400))
    var logged: [String] = []
    for account in AccountSummaryBuilder.summaries(from: inputs, spend: .init(now: now)) {
      for row in rows(account, days: [yesterday], today: today, inputs: inputs, thresholdPct: thresholdPct) {
        guard let drift = row.drift, drift.flagged,
              once.first("\(account.id) \(row.model) \(yesterday)", on: now) else { continue }
        log.emit(.warn, .ledgerDrift, cat: .ledger, msg: "usage estimate drifted from the provider cost",
                 acct: account.provider.rawValue, ctx: [
                   "model": .string(row.model), "drift_pct": .double(Double(drift.basisPoints) / 100)
                 ])
        logged.append("\(account.id)/\(row.model)")
      }
    }
    return logged
  }
}
