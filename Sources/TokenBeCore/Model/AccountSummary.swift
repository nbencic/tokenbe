import Foundation

/// How an account's remaining amount is known (03 `account.balance_mode`).
public enum BalanceMode: String, CaseIterable, Sendable, Codable {
  case direct
  case anchored
  case spendOnly = "spend_only"
}

/// Spend attributed to one app today (08 popover row 4).
public struct AppSpend: Sendable, Equatable, Hashable {
  public var appName: String
  public var cents: Int64

  public init(appName: String, cents: Int64) {
    self.appName = appName
    self.cents = cents
  }
}

/// Auto-reload configuration (09 `account.auto_reload_*`).
public struct AutoReload: Sendable, Equatable, Hashable {
  public var belowCents: Int64
  public var toCents: Int64?

  public init(belowCents: Int64, toCents: Int64?) {
    self.belowCents = belowCents
    self.toCents = toCents
  }
}

/// Everything the UI shows about one account, computed in Core (04 I3: the UI never computes money).
/// Optionals stay nil until the stage that fills them (14 § Stage 1.1 step 2).
public struct AccountSummary: Sendable, Equatable, Identifiable {
  public var id: String
  public var provider: ProviderID
  public var label: String
  public var mode: BalanceMode
  public var currency: Currency
  public var remainingCents: Int64?
  public var estimateBandCents: Int64?
  public var burn7dCents: Int64?
  public var burnTodayCents: Int64?
  /// Runways in seconds (05 § Runway); a ratio, not money.
  public var runway7d: TimeInterval?
  public var runwayToday: TimeInterval?
  public var runwayMin: TimeInterval?
  public var band: Band
  public var bandSince: Date?
  public var freshness: [Job: Date?]
  public var isStale: Bool
  public var isPaused: Bool
  public var needsKey: Bool
  public var circuitOpenUntil: Date?
  public var todaySpendCents: Int64?
  public var spend30dCents: Int64?
  public var autoReload: AutoReload?
  public var anchorAgeDays: Int?
  public var topApps: [AppSpend]
  public var unpricedCents: Int64

  public init(
    id: String, provider: ProviderID, label: String, mode: BalanceMode, currency: Currency = .usd,
    remainingCents: Int64? = nil, estimateBandCents: Int64? = nil, burn7dCents: Int64? = nil,
    burnTodayCents: Int64? = nil, runway7d: TimeInterval? = nil, runwayToday: TimeInterval? = nil,
    runwayMin: TimeInterval? = nil, band: Band = .unknown, bandSince: Date? = nil, freshness: [Job: Date?] = [:],
    isStale: Bool = false, isPaused: Bool = false, needsKey: Bool = false, circuitOpenUntil: Date? = nil,
    todaySpendCents: Int64? = nil, spend30dCents: Int64? = nil, autoReload: AutoReload? = nil,
    anchorAgeDays: Int? = nil, topApps: [AppSpend] = [], unpricedCents: Int64 = 0
  ) {
    self.id = id
    self.provider = provider
    self.label = label
    self.mode = mode
    self.currency = currency
    self.remainingCents = remainingCents
    self.estimateBandCents = estimateBandCents
    self.burn7dCents = burn7dCents
    self.burnTodayCents = burnTodayCents
    self.runway7d = runway7d
    self.runwayToday = runwayToday
    self.runwayMin = runwayMin
    self.band = band
    self.bandSince = bandSince
    self.freshness = freshness
    self.isStale = isStale
    self.isPaused = isPaused
    self.needsKey = needsKey
    self.circuitOpenUntil = circuitOpenUntil
    self.todaySpendCents = todaySpendCents
    self.spend30dCents = spend30dCents
    self.autoReload = autoReload
    self.anchorAgeDays = anchorAgeDays
    self.topApps = topApps
    self.unpricedCents = unpricedCents
  }

  /// Most recent successful poll of any job, nil before the first one ("No data yet", 08).
  public var lastSuccessAt: Date? {
    freshness.values.compactMap { $0 }.max()
  }

  /// The popover header's `Refreshed …` (14 § Stage 4.1 step 4): the oldest of the accounts' last successes, so
  /// the header never claims fresher data than the stalest card. Accounts never polled are left out; nil when no
  /// account has succeeded yet (Q-034).
  public static func refreshedAt(_ accounts: [AccountSummary]) -> Date? {
    accounts.compactMap(\.lastSuccessAt).min()
  }
}
