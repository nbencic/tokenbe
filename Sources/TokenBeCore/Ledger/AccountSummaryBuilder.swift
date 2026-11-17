import Foundation

/// Maps `SummaryInputs` to the `[AccountSummary]` the UI shows (04 I3: Core computes, the UI renders).
/// Stage 2.2 fills the identity fields: id, provider, label, balance mode and currency (14 § Stage 2.2); 3.5 adds
/// freshness, the circuit and `needsKey`; 4.1 adds `isPaused` from `account.paused` (PM-3.5-3); 4.2 adds the
/// capabilities, the interval override and the Sources strip (`Freshness` then sets `isStale` at a given time); 5.2
/// today's and the range's spend and the unpriced estimate (`SpendContext`); 7.1 the By-app rows (`Attribution`);
/// 8.1 the By-model rows (`Drift`); 8.2 the chart's daily spend and the cache savings (`SpendChart`, `CacheSavings`).
/// Later stages fill the rest from the
/// inputs they add.
public enum AccountSummaryBuilder {
  /// What the money figures depend on besides the database: the Dashboard range, the time, the price book and the
  /// Alerts thresholds (09): the bands' and the drift's (`tb.alerts.driftThresholdPct`: the harness drift chip, 7.3,
  /// and the By-model table, 8.1).
  public struct SpendContext: Sendable {
    public var range: DashboardRange
    public var now: Date
    public var pricer: Pricer
    public var thresholds: BandThresholds
    public var driftThresholdPct: Int

    public init(range: DashboardRange = .default, now: Date = Date(), pricer: Pricer = Pricer(),
                thresholds: BandThresholds = BandThresholds(), driftThresholdPct: Int = 10) {
      self.range = range
      self.now = now
      self.pricer = pricer
      self.thresholds = thresholds
      self.driftThresholdPct = driftThresholdPct
    }
  }

  /// A stored value the model has no case for. 03's CHECKs rule this out for `provider` and `balance_mode`;
  /// `currency` has no CHECK.
  public struct InvalidRow: Error, Sendable, Equatable, CustomStringConvertible {
    public let column: String
    public let value: String
    public var description: String { "unknown \(column) '\(value)'" }
  }

  /// One summary per account, in input order. A row that cannot be read is left out and reported to `skipped`,
  /// which the caller logs (`ui.error`), so one bad row never hides the other accounts.
  /// `missingKeys` holds the `keychain_ref`s startup step 3 found without a Keychain item (04): those accounts
  /// get `needsKey`, and their card reads `Key missing · Fix…` (08).
  public static func summaries(
    from inputs: SummaryInputs, missingKeys: Set<String> = [], spend: SpendContext = SpendContext(),
    skipped: (AccountRecord, InvalidRow) -> Void = { _, _ in }
  ) -> [AccountSummary] {
    let states = Dictionary(grouping: inputs.pollStates, by: \.accountId)
    return inputs.accounts.compactMap { record in
      switch summary(for: record) {
      case .success(var summary):
        apply(states[record.id] ?? [], to: &summary)
        apply(record, to: &summary)
        summary.sources = SourceStatus.all(capabilities: summary.capabilities, states: states[record.id] ?? [])
        summary.needsKey = missingKeys.contains(record.keychainRef)
        apply(inputs, spend, to: &summary)
        return summary
      case .failure(let invalid):
        skipped(record, invalid)
        return nil
      }
    }
  }

  /// Each job's last success (nil = never polled) and the latest open circuit.
  static func apply(_ states: [PollStateSummary], to summary: inout AccountSummary) {
    for state in states {
      guard let job = Job(rawValue: state.job) else { continue }
      summary.freshness[job] = state.lastSuccessAt.flatMap(DBTime.date)
    }
    summary.circuitOpenUntil = states.compactMap { $0.circuitOpenUntil.flatMap(DBTime.date) }.max()
  }

  /// The stored capabilities and interval override. Unreadable capabilities stay nil: the coordinator logs them
  /// once (`poll.failed`, "account capabilities unreadable"), so the summary does not log again.
  static func apply(_ record: AccountRecord, to summary: inout AccountSummary) {
    if record.autoReloadEnabled, let below = record.autoReloadBelowCents {
      summary.autoReload = AutoReload(belowCents: below, toCents: record.autoReloadToCents)
    }
    summary.capabilities = Result { try Capabilities.decode(json: record.capabilities) }.success
    summary.intervalOverride = IntervalOverride.parse(record.intervalOverrideJson, provider: summary.provider).override
  }

  /// 05 § Spend definitions, once the account has had a usage or cost poll (before that the card reads "No data
  /// yet", 08).
  static func apply(_ inputs: SummaryInputs, _ context: SpendContext, to summary: inout AccountSummary) {
    let anchor = Remaining.anchor(accountID: summary.id, events: inputs.ledgerEvents)
    summary.anchorAt = anchor.flatMap { DBTime.date($0.ts) }
    summary.dollarFloorCents = context.thresholds.dollarFloorCents
    if let state = inputs.bandStates.first(where: { $0.accountId == summary.id }) {
      summary.bandSince = DBTime.date(state.since)
    }
    let harness = inputs.harnessDays.filter { $0.accountId == summary.id }
    summary.hasHarness = !harness.isEmpty
    summary.harnessLinesToday = Int(harness.filter { $0.day == DailyOnce.utcDay(context.now) }
      .reduce(Int64(0)) { $0 + $1.classes.requests })
    // Harness lines are data too (7.2): an anchored xAI account has no polled job, only harness spend (PM-6.2-2).
    guard (summary.freshness[.usage] ?? nil) != nil || (summary.freshness[.cost] ?? nil) != nil
      || (summary.freshness[.balance] ?? nil) != nil || summary.hasHarness else {
      // Before the first poll: the anchor alone is not a runway yet (`No data yet`, 08), so the band is unknown.
      return
    }
    let now = context.now
    let today = DailyOnce.utcDay(now)
    let rangeDays = Spend.days(context.range, now: now)
    summary.rangeDays = rangeDays
    summary.cacheSavings = CacheSavings.figure(summary, days: rangeDays, inputs: inputs, pricer: context.pricer)
    let daily = Spend.daily(summary, today: today, inputs: inputs)
    summary.todaySpend = Spend.sum([daily[today]].compactMap { $0 })
    summary.dailySpend = daily.filter { rangeDays.contains($0.key) }
    summary.rangeSpend = Spend.sum(rangeDays.compactMap { daily[$0] })
    summary.spend30dCents = Spend.sum(Spend.days(.thirtyDays, now: now).compactMap { daily[$0] }).cents
    summary.unpriced = Spend.unpriced(summary, days: Spend.days(context.range, now: now), inputs: inputs,
                                      pricer: context.pricer)
    summary.byApp = Attribution.rows(summary, days: Spend.days(context.range, now: now), today: today, inputs: inputs)
    summary.byAppTotal = Attribution.total(summary.byApp)
    summary.todayApps = Attribution.rows(summary, days: [today], today: today, inputs: inputs)
    summary.harnessDrift = Attribution.harnessDrifts(summary, days: Spend.days(context.range, now: now), today: today,
                                                     inputs: inputs, thresholdPct: context.driftThresholdPct)
    summary.byModel = Drift.rows(summary, days: Spend.days(context.range, now: now), today: today, inputs: inputs,
                                 thresholdPct: context.driftThresholdPct)
    summary.burn7dCents = Burn.sevenDay(daily: daily, now: now)
    summary.burnTodayCents = Burn.today(daily: daily, now: now)
    applyLedger(anchor: anchor, inputs: inputs, context: context, daily: daily, to: &summary)
  }

  /// 05 § Remaining, § Estimate band, § Runway and § Bands.
  static func applyLedger(anchor: LedgerEventRecord?, inputs: SummaryInputs, context: SpendContext,
                          daily: [String: SpendFigure], to summary: inout AccountSummary) {
    let now = context.now
    let today = DailyOnce.utcDay(now)
    let sinceAnchor = anchor.map { Spend.sinceAnchor(summary, anchor: $0, today: today, inputs: inputs) }
    summary.remainingCents = Remaining.cents(mode: summary.mode, accountID: summary.id, currency: summary.currency,
                                             inputs: inputs, spendSinceAnchor: sinceAnchor?.cents)
    summary.providerUnavailable = summary.mode == .direct
      && Remaining.providerUnavailable(accountID: summary.id, inputs: inputs)
    if summary.mode == .anchored, let anchor, let sinceAnchor, let anchorAt = summary.anchorAt {
      let anchorDays = Spend.days(.ninetyDays, now: now).filter { $0 >= String(anchor.ts.prefix(10)) }
      let unpriced = Spend.unpriced(summary, days: anchorDays, inputs: inputs, pricer: context.pricer).cents ?? 0
      let age = Int64(max(0, now.timeIntervalSince(anchorAt)))
      summary.anchorAgeDays = Int(age / 86_400)
      summary.estimateBandCents = EstimateBand.cents(EstimateBand.Inputs(
        spendSinceAnchor: sinceAnchor.cents, burn7d: summary.burn7dCents,
        usageLagSeconds: summary.capabilities?.usageLag.components.seconds ?? 0, unpricedCents: unpriced,
        anchorAgeSeconds: age, anchorAgeDays: context.thresholds.anchorAgeDays
      ))
    } else if summary.mode == .direct, summary.remainingCents != nil {
      summary.estimateBandCents = 0
    }
    let paces = Runway.paces(remaining: summary.remainingCents, burn7d: summary.burn7dCents,
                             burnToday: summary.burnTodayCents)
    summary.runway7d = paces.sevenDay
    summary.runwayToday = paces.today
    summary.runwayMin = paces.minimum
    let evaluated = BandEvaluator.band(BandEvaluator.Inputs(
      mode: summary.mode, remaining: summary.remainingCents, estimateBand: summary.estimateBandCents ?? 0,
      burn7d: summary.burn7dCents, runwayMin: summary.runwayMin, autoReload: summary.autoReload,
      providerUnavailable: summary.providerUnavailable
    ), thresholds: context.thresholds)
    summary.band = evaluated.band
    summary.needsReanchor = evaluated.needsReanchor
    if let reload = summary.autoReload, let remaining = summary.remainingCents {
      summary.reloadPending = remaining <= reload.belowCents
    }
  }

  public static func summary(for record: AccountRecord) -> Result<AccountSummary, InvalidRow> {
    guard let provider = ProviderID(rawValue: record.provider) else {
      return .failure(InvalidRow(column: "provider", value: record.provider))
    }
    guard let mode = BalanceMode(rawValue: record.balanceMode) else {
      return .failure(InvalidRow(column: "balance_mode", value: record.balanceMode))
    }
    guard let currency = Currency(rawValue: record.currency) else {
      return .failure(InvalidRow(column: "currency", value: record.currency))
    }
    return .success(AccountSummary(id: record.id, provider: provider, label: record.label, mode: mode,
                                   currency: currency, isPaused: record.paused))
  }
}

extension Result {
  /// The value, or nil for a failure the caller has accounted for.
  var success: Success? {
    if case .success(let value) = self { return value }
    return nil
  }
}
