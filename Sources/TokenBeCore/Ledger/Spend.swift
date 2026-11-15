import Foundation

/// One account's usage on one UTC day (05 § Spend definitions), summed in SQL from `usage_bucket` by source.
public struct UsageDay: Sendable, Equatable, Codable {
  public var accountId: String
  /// `YYYY-MM-DD`, UTC.
  public var day: String
  public var source: String
  /// Σ `est_cost_cents` of the priced buckets.
  public var estCents: Int64
  /// Σ every token class of the unpriced buckets (05 `unpriced_cents`).
  public var unpricedTokens: Int64

  public init(accountId: String, day: String, source: String, estCents: Int64, unpricedTokens: Int64 = 0) {
    self.accountId = accountId
    self.day = day
    self.source = source
    self.estCents = estCents
    self.unpricedTokens = unpricedTokens
  }
}

/// A model with priced usage on a UTC day (05: `median_in_rate_of_priced_models_in_window`).
public struct PricedModelDay: Sendable, Equatable, Codable {
  public var accountId: String
  public var day: String
  public var model: String

  public init(accountId: String, day: String, model: String) {
    self.accountId = accountId
    self.day = day
    self.model = model
  }
}

/// An account's provider cost for one UTC day: the `cost_bucket` row with `group_kind = 'total'` (05 `spend_truth`).
public struct CostDay: Sendable, Equatable, Codable {
  public var accountId: String
  public var day: String
  public var amountCents: Int64

  public init(accountId: String, day: String, amountCents: Int64) {
    self.accountId = accountId
    self.day = day
    self.amountCents = amountCents
  }
}

/// A spend figure and whether any of it is an estimate (usage × price book), which the UI marks with `≈` (Q-040).
public struct SpendFigure: Sendable, Equatable {
  public var cents: Int64
  public var isEstimate: Bool

  public init(cents: Int64, isEstimate: Bool) {
    self.cents = cents
    self.isEstimate = isEstimate
  }
}

/// The numbers strip's unpriced cell (05 `unpriced_cents`): tokens with no price, valued at the median input rate
/// of the window's priced models. `cents` is nil when the window has no priced model to take a rate from.
public struct UnpricedFigure: Sendable, Equatable {
  public var tokens: Int64
  public var cents: Int64?

  public init(tokens: Int64, cents: Int64?) {
    self.tokens = tokens
    self.cents = cents
  }
}

/// 05 § Spend definitions over UTC days (14 § Stage 5.2 step 4). Closed days with a provider cost row use the
/// provider's cost (truth); the open day, and closed days without a cost row, use the usage estimate (Q-040).
public enum Spend {
  /// The usage sources that count as `spend_est` (05): provider rows and their retention roll-ups; harness rows only
  /// for an account without a usage API.
  static func counts(_ source: String, usageAPI: Bool) -> Bool {
    source == "harness" ? !usageAPI : true
  }

  /// The UTC days of a Dashboard range ending today: `Today` is today, `7 d` today and the 6 days before (Q-040).
  public static func days(_ range: DashboardRange, now: Date) -> [String] {
    let count = switch range {
    case .today: 1
    case .sevenDays: 7
    case .thirtyDays: 30
    case .ninetyDays: 90
    }
    return (0..<count).reversed().map { DailyOnce.utcDay(now.addingTimeInterval(TimeInterval(-86_400 * $0))) }
  }

  /// Spend of one account per UTC day (05): a closed day with a provider `total` cost row is that cost (truth);
  /// the open day, and closed days without a cost row, are Σ `est_cost_cents` (estimate). Days without data are
  /// absent. The strip, burn and `spend_since_anchor` all use this one rule (Q-040, PM-5.2-1).
  public static func daily(_ account: AccountSummary, today: String, inputs: SummaryInputs) -> [String: SpendFigure] {
    var result: [String: SpendFigure] = [:]
    if account.capabilities?.cost ?? false {
      for cost in inputs.costDays where cost.accountId == account.id && cost.day < today {
        result[cost.day, default: SpendFigure(cents: 0, isEstimate: false)].cents += cost.amountCents
      }
    }
    let truthDays = Set(result.keys)
    let usageAPI = account.capabilities?.usage ?? true
    for row in inputs.usageDays where row.accountId == account.id && !truthDays.contains(row.day)
      && counts(row.source, usageAPI: usageAPI) {
      result[row.day, default: SpendFigure(cents: 0, isEstimate: true)].cents += row.estCents
    }
    return result
  }

  /// Spend of one account over `days`.
  public static func spend(_ account: AccountSummary, days: [String], today: String,
                           inputs: SummaryInputs) -> SpendFigure {
    sum(days.compactMap { daily(account, today: today, inputs: inputs)[$0] })
  }

  static func sum(_ figures: [SpendFigure]) -> SpendFigure {
    SpendFigure(cents: figures.reduce(0) { $0 + $1.cents }, isEstimate: figures.contains(where: \.isEstimate))
  }

  /// 05 `spend_since_anchor`: every day after the anchor's UTC day by the daily rule, plus the estimate of the
  /// anchor day's remainder (buckets starting at or after the anchor, `SummaryInputs.anchorDayUsage`).
  public static func sinceAnchor(_ account: AccountSummary, anchor: LedgerEventRecord, today: String,
                                 inputs: SummaryInputs) -> SpendFigure {
    let anchorDay = String(anchor.ts.prefix(10))
    let after = daily(account, today: today, inputs: inputs).filter { $0.key > anchorDay }.map(\.value)
    let usageAPI = account.capabilities?.usage ?? true
    let remainder = inputs.anchorDayUsage.filter {
      $0.accountId == account.id && counts($0.source, usageAPI: usageAPI)
    }.map { SpendFigure(cents: $0.estCents, isEstimate: true) }
    return sum(after + remainder)
  }

  /// 05 `unpriced_cents(window)`: Σ unpriced tokens × the median input rate of the window's priced models, rounded
  /// half up to cents once. Never added to spend.
  public static func unpriced(_ account: AccountSummary, days: [String], inputs: SummaryInputs,
                              pricer: Pricer) -> UnpricedFigure {
    let (accountID, provider, usage) = (account.id, account.provider, inputs.usageDays)
    let usageAPI = account.capabilities?.usage ?? true
    let wanted = Set(days)
    let tokens = usage.filter { $0.accountId == accountID && wanted.contains($0.day) && counts($0.source, usageAPI: usageAPI) }
      .reduce(Int64(0)) { $0 + $1.unpricedTokens }
    guard tokens > 0 else { return UnpricedFigure(tokens: 0, cents: 0) }
    let models = Set(inputs.pricedModels.filter { $0.accountId == accountID && wanted.contains($0.day) }.map(\.model))
    let rates = models.compactMap { pricer.lookup(provider: provider, model: $0)?.entry.input }
    guard let rate = median(rates) else { return UnpricedFigure(tokens: tokens, cents: nil) }
    let picodollars = Int128(tokens) * Int128(rate)
    let perCent: Int128 = 10_000_000_000
    return UnpricedFigure(tokens: tokens, cents: Int64(clamping: (picodollars + perCent / 2) / perCent))
  }

  /// The median; for an even count, the mean of the two middle values, rounded down. Nil when empty.
  static func median(_ values: [Int64]) -> Int64? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  }

  /// The Overview subline's `Total spend` (05 § Currency): USD accounts summed; other currencies counted.
  public static func totalUSD(_ accounts: [AccountSummary]) -> (spend: SpendFigure, nonUSD: Int) {
    let usd = accounts.filter { $0.currency == .usd }
    return (sum(usd.compactMap(\.rangeSpend)), accounts.count - usd.count)
  }
}
