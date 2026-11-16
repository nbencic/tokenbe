import Foundation

/// How an account's remaining amount is known (03 `account.balance_mode`).
public enum BalanceMode: String, CaseIterable, Sendable, Codable {
  case direct
  case anchored
  case spendOnly = "spend_only"
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
  /// Today's spend (UTC day; 05: the usage estimate for the open day). Nil before the first usage or cost poll.
  public var todaySpend: SpendFigure?
  /// Spend over the Dashboard range (`tb.ui.dashboardRange`), for the numbers strip and the Overview subline.
  public var rangeSpend: SpendFigure?
  public var spend30dCents: Int64?
  public var autoReload: AutoReload?
  public var anchorAgeDays: Int?
  /// The By-app table over the Dashboard range (08 `20N-0`; `Attribution.rows`); Σ spend == `rangeSpend`.
  public var byApp: [AppRow] = []
  /// The By-app table's `Total` (Σ `byApp`); equals `rangeSpend` (06 precedence, 08).
  public var byAppTotal: AppRowsTotal?
  /// Popover row 4 (08): the rows by today's spend.
  public var todayApps: [AppRow] = []
  /// The account has harness lines in the window (7.2): its spend is known even with no polled job (xAI anchored).
  public var hasHarness = false
  /// Harness lines for this account today (UTC), for the Sources strip's `Harness · … · 12 lines today` (08).
  public var harnessLinesToday = 0
  /// The closed days in the range whose harness spend drifted from the balance delta, newest first (06 precedence 2;
  /// the account page's drift chip, 7.3).
  public var harnessDrift: [HarnessDrift] = []
  /// The numbers strip's `Unpriced in range` (05 `unpriced_cents`); nil before the first poll.
  public var unpriced: UnpricedFigure?
  /// 09 `tb.alerts.dollarFloorCents` at evaluation (logged with a band change, 03 `inputs_json`).
  public var dollarFloorCents: Int64?
  /// The latest anchor's time (anchored accounts); nil without one.
  public var anchorAt: Date?
  /// V1 broke (`remaining < −burn_7d`): the band is `unknown` and the account page asks for a new anchor (04).
  public var needsReanchor: Bool = false
  /// Auto-reload is on and `remaining ≤ auto_reload_below`: runway reads `reloads at $X`, band `watch` (05).
  public var reloadPending: Bool = false
  /// The provider reports the account unavailable (D-deepseek-unavailable): band `critical`, account header chip.
  public var providerUnavailable: Bool = false
  /// `account.capabilities`; nil when the stored JSON cannot be read (the coordinator logs that once).
  public var capabilities: Capabilities?
  /// `account.interval_override_json`, clamped (09); the stale threshold uses the same interval as the scheduler.
  public var intervalOverride: IntervalOverride
  /// The account page's Sources strip (08 `HP-0`), one per job, in `Job.allCases` order (14 § Stage 4.2).
  public var sources: [SourceStatus]

  public init(
    id: String, provider: ProviderID, label: String, mode: BalanceMode, currency: Currency = .usd,
    remainingCents: Int64? = nil, estimateBandCents: Int64? = nil, burn7dCents: Int64? = nil,
    burnTodayCents: Int64? = nil, runway7d: TimeInterval? = nil, runwayToday: TimeInterval? = nil,
    runwayMin: TimeInterval? = nil, band: Band = .unknown, bandSince: Date? = nil, freshness: [Job: Date?] = [:],
    isStale: Bool = false, isPaused: Bool = false, needsKey: Bool = false, circuitOpenUntil: Date? = nil,
    todaySpend: SpendFigure? = nil, rangeSpend: SpendFigure? = nil, spend30dCents: Int64? = nil, autoReload: AutoReload? = nil,
    anchorAgeDays: Int? = nil, unpriced: UnpricedFigure? = nil, capabilities: Capabilities? = nil,
    intervalOverride: IntervalOverride = IntervalOverride(), sources: [SourceStatus] = []
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
    self.todaySpend = todaySpend
    self.rangeSpend = rangeSpend
    self.spend30dCents = spend30dCents
    self.autoReload = autoReload
    self.anchorAgeDays = anchorAgeDays
    self.unpriced = unpriced
    self.capabilities = capabilities
    self.intervalOverride = intervalOverride
    self.sources = sources
  }

  /// Anchored and no anchor yet: the banner and the runway board offer `Set anchor…` (08).
  public var needsAnchor: Bool { mode == .anchored && anchorAt == nil }

  /// Row 2's `todaySpend` metric (09 `tb.popover.pinnedMetric`).
  public var todaySpendCents: Int64? { todaySpend?.cents }

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
