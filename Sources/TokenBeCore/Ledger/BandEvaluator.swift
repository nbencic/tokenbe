import Foundation

/// 09 § Alerts: the band thresholds.
public struct BandThresholds: Sendable, Equatable {
  public var watchDays: Int
  public var lowDays: Int
  public var criticalDays: Int
  public var dollarFloorCents: Int64
  public var anchorAgeDays: Int

  /// 09's defaults.
  public init(watchDays: Int = 14, lowDays: Int = 7, criticalDays: Int = 2, dollarFloorCents: Int64 = 500,
              anchorAgeDays: Int = 30) {
    self.watchDays = watchDays
    self.lowDays = lowDays
    self.criticalDays = criticalDays
    self.dollarFloorCents = dollarFloorCents
    self.anchorAgeDays = anchorAgeDays
  }

  @MainActor
  public init(_ settings: Settings) {
    self.init(watchDays: settings.alertsWatchDays, lowDays: settings.alertsLowDays,
              criticalDays: settings.alertsCriticalDays, dollarFloorCents: Int64(settings.alertsDollarFloorCents),
              anchorAgeDays: settings.alertsAnchorAgeDays)
  }

  /// The settings that change a band (09 § Alerts).
  public static let keys: Set<SettingsKey> = [.alertsWatchDays, .alertsLowDays, .alertsCriticalDays,
                                              .alertsDollarFloorCents, .alertsAnchorAgeDays]
}

/// 05 § Bands, evaluated in order, first match wins (14 § Stage 5.3 step 1):
/// 1. `unknown` — `spend_only`, no anchor (or no balance yet), `runway_min == nil`, `M ≥ remaining` while remaining
///    is positive, or V1 broken (`remaining < −burn_7d`: re-anchor);
/// 2. `critical` — `remaining < dollar_floor` or `runway_min < critical_days`;
/// 3. `low` — `runway_min < low_days`; 4. `watch` — `runway_min < watch_days`; 5. `healthy`.
/// Auto-reload (05): with it on and `remaining ≤ auto_reload_below`, the band is forced to `watch` (Q-042).
public enum BandEvaluator {
  public struct Inputs: Sendable, Equatable {
    public var mode: BalanceMode
    public var remaining: Int64?
    public var estimateBand: Int64
    public var burn7d: Int64?
    public var runwayMin: TimeInterval?
    public var autoReload: AutoReload?

    public init(mode: BalanceMode, remaining: Int64?, estimateBand: Int64 = 0, burn7d: Int64? = nil,
                runwayMin: TimeInterval? = nil, autoReload: AutoReload? = nil) {
      self.mode = mode
      self.remaining = remaining
      self.estimateBand = estimateBand
      self.burn7d = burn7d
      self.runwayMin = runwayMin
      self.autoReload = autoReload
    }
  }

  /// The band, and whether V1 failed (the account page then asks for a new anchor).
  public static func band(_ inputs: Inputs, thresholds: BandThresholds) -> (band: Band, needsReanchor: Bool) {
    if let reload = inputs.autoReload, let remaining = inputs.remaining, remaining <= reload.belowCents {
      return (.watch, false)
    }
    guard inputs.mode != .spendOnly, let remaining = inputs.remaining else { return (.unknown, false) }
    if let burn = inputs.burn7d, remaining < -burn { return (.unknown, true) }
    if remaining > 0, inputs.estimateBand >= remaining { return (.unknown, false) }
    guard let runway = inputs.runwayMin else { return (.unknown, false) }
    let day: TimeInterval = 86_400
    if remaining < thresholds.dollarFloorCents || runway < Double(thresholds.criticalDays) * day {
      return (.critical, false)
    }
    if runway < Double(thresholds.lowDays) * day { return (.low, false) }
    if runway < Double(thresholds.watchDays) * day { return (.watch, false) }
    return (.healthy, false)
  }
}

/// Keeps `band_state` in step with the evaluated bands (14 § Stage 5.3 step 2): on a band change it writes the row
/// with its `inputs_json` in one statement (V6) and then logs `ui.band_change {acct, from, to, inputs, trigger}`.
/// An account's first evaluation inserts its row without a log line (nothing changed). A failed write logs
/// `ui.error` and is retried at the next evaluation, because the in-memory band is updated only after the write.
public actor BandRecorder {
  /// What caused the evaluation: `data` (a database change), `settings` (Alerts thresholds), `clock` (time
  /// passing). An account's first evaluation in this process that differs from its persisted row is logged as
  /// `launch` (it changed while TokenBe was not running). `scripts/check-traceability.sh` (E2E-9) joins only `data`
  /// changes to a poll or ledger record (Q-042).
  public enum Trigger: String, Sendable {
    case data, settings, clock, launch
  }

  let store: any BandRepository
  let log: EventLog
  private var known: [String: String] = [:]
  /// Accounts evaluated at least once in this process.
  private var seen: Set<String> = []

  public init(store: any BandRepository, logPipeline: LogPipeline? = nil) {
    self.store = store
    log = EventLog(pipeline: logPipeline)
  }

  public func record(_ summaries: [AccountSummary], persisted: [BandStateRecord], trigger: Trigger, now: Date) async {
    let rows = Dictionary(persisted.map { ($0.accountId, $0.band) }) { first, _ in first }
    for summary in summaries {
      let first = seen.insert(summary.id).inserted
      let previous = known[summary.id] ?? rows[summary.id]
      let band = summary.band.rawValue
      guard previous != band else {
        known[summary.id] = band
        continue
      }
      let inputs = Self.inputs(summary)
      do {
        try await store.recordBand(BandStateRecord(accountId: summary.id, band: band, since: DBTime.string(now),
                                                   inputsJson: inputs.json))
      } catch {
        log.emit(.error, .uiError, cat: .ui, msg: "band_state not written", acct: summary.provider.rawValue, err: error,
                 ctx: ["view": "band"])
        continue
      }
      known[summary.id] = band
      guard let previous else { continue }
      log.emit(.info, .uiBandChange, cat: .ui, msg: "band changed", acct: summary.provider.rawValue, ctx: [
        "from": .string(previous), "to": .string(band), "inputs": .string(inputs.json),
        "trigger": .string((first ? Trigger.launch : trigger).rawValue)
      ])
    }
  }

  /// 07 `inputs` plus 03's floor: remaining, burn_7d, burn_today, runway_min (seconds), floor and M.
  /// The JSON keys are sorted, so the same inputs always give the same text.
  static func inputs(_ summary: AccountSummary) -> (values: [String: Int64?], json: String) {
    let values: [String: Int64?] = [
      "remaining": summary.remainingCents, "burn_7d": summary.burn7dCents, "burn_today": summary.burnTodayCents,
      "runway_min": summary.runwayMin.map { Int64($0) }, "floor": summary.dollarFloorCents,
      "estimate_band": summary.estimateBandCents
    ]
    let json = "{" + values.keys.sorted().map { key in
      "\"\(key)\":" + ((values[key] ?? nil).map { "\($0)" } ?? "null")
    }.joined(separator: ",") + "}"
    return (values, json)
  }
}
