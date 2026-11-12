import Foundation

/// The polling jobs of an account (03 `poll_state`, 09 interval overrides). Which ones apply to an account follows
/// from its `Capabilities`; which of those the minute-cadence loop runs, and how often, is `interval(…)` (04).
public enum Job: String, CaseIterable, Sendable {
  case usage, cost, balance, keys

  /// The jobs of 04's minute-cadence loop. `cost` is a daily-activity step (04 § Daily activity, Stage 4.3).
  public static let minuteCadence: [Job] = [.usage, .balance, .keys]

  /// Whether an account's capabilities allow this job (`keys` needs `keyNames`).
  public func applies(to capabilities: Capabilities) -> Bool {
    switch self {
    case .usage: capabilities.usage
    case .cost: capabilities.cost
    case .balance: capabilities.balance
    case .keys: capabilities.keyNames
    }
  }

  /// The 09 key that sets this job's period for `provider`, or nil when 04 gives the pair no minute cadence
  /// (`usage` exists for OpenAI and Anthropic only; `cost` runs daily).
  public func intervalKey(for provider: ProviderID) -> SettingsKey? {
    switch (self, provider) {
    case (.usage, .openai): .pollUsageIntervalOpenAIS
    case (.usage, .anthropic): .pollUsageIntervalAnthropicS
    case (.usage, _), (.cost, _): nil
    case (.balance, _): .pollBalanceIntervalS
    case (.keys, _): .pollKeysIntervalS
    }
  }

  /// The job's period for one account: the account's override (09 `account.interval_override_json`) or the global
  /// setting, times `tb.poll.lowPowerMultiplier` while Low Power Mode is on (04). Nil when the job has no minute
  /// cadence for the provider.
  public func interval(for provider: ProviderID, settings: ScheduleSettings, override: IntervalOverride,
                       lowPower: Bool) -> Duration? {
    guard let key = intervalKey(for: provider) else { return nil }
    let seconds = override.seconds[self] ?? settings.seconds(key)
    return .seconds(seconds * (lowPower ? settings.lowPowerMultiplier : 1))
  }
}

/// The 09 values the scheduler reads, as one value the coordinator actor can hold (`Settings` is main-actor).
public struct ScheduleSettings: Sendable, Equatable {
  public var balanceIntervalS: Int
  public var usageIntervalAnthropicS: Int
  public var usageIntervalOpenAIS: Int
  public var keysIntervalS: Int
  public var lowPowerMultiplier: Int
  /// `tb.poll.pausedUntil`; nil when 0 (not paused).
  public var pausedUntil: Date?

  /// The keys whose change the coordinator must see (09 § Sources).
  public static let keys: Set<SettingsKey> = [
    .pollBalanceIntervalS, .pollUsageIntervalAnthropicS, .pollUsageIntervalOpenAIS, .pollKeysIntervalS,
    .pollLowPowerMultiplier, .pollPausedUntil
  ]

  public init(balanceIntervalS: Int, usageIntervalAnthropicS: Int, usageIntervalOpenAIS: Int, keysIntervalS: Int,
              lowPowerMultiplier: Int, pausedUntil: Date?) {
    self.balanceIntervalS = balanceIntervalS
    self.usageIntervalAnthropicS = usageIntervalAnthropicS
    self.usageIntervalOpenAIS = usageIntervalOpenAIS
    self.keysIntervalS = keysIntervalS
    self.lowPowerMultiplier = lowPowerMultiplier
    self.pausedUntil = pausedUntil
  }

  /// 09's defaults, from the spec table (the single source).
  public static let defaults = ScheduleSettings(
    balanceIntervalS: SettingsKey.pollBalanceIntervalS.defaultInt,
    usageIntervalAnthropicS: SettingsKey.pollUsageIntervalAnthropicS.defaultInt,
    usageIntervalOpenAIS: SettingsKey.pollUsageIntervalOpenAIS.defaultInt,
    keysIntervalS: SettingsKey.pollKeysIntervalS.defaultInt,
    lowPowerMultiplier: SettingsKey.pollLowPowerMultiplier.defaultInt, pausedUntil: nil
  )

  @MainActor
  public init(_ settings: Settings) {
    self.init(
      balanceIntervalS: settings.pollBalanceIntervalS, usageIntervalAnthropicS: settings.pollUsageIntervalAnthropicS,
      usageIntervalOpenAIS: settings.pollUsageIntervalOpenAIS, keysIntervalS: settings.pollKeysIntervalS,
      lowPowerMultiplier: settings.pollLowPowerMultiplier,
      pausedUntil: settings.pollPausedUntil > 0 ? Date(timeIntervalSince1970: settings.pollPausedUntil) : nil
    )
  }

  func seconds(_ key: SettingsKey) -> Int {
    switch key {
    case .pollBalanceIntervalS: balanceIntervalS
    case .pollUsageIntervalAnthropicS: usageIntervalAnthropicS
    case .pollUsageIntervalOpenAIS: usageIntervalOpenAIS
    default: keysIntervalS
    }
  }

  /// True while the global pause (`Pause polling for 1 h`, 08) lasts.
  public func isPaused(at time: Date) -> Bool {
    pausedUntil.map { $0 > time } ?? false
  }
}

/// 09 `account.interval_override_json`: `{usage?, cost?, balance?, keys?}` in seconds. Each value is clamped to the
/// range of the global key it overrides (Q-034); an unreadable document counts as no override.
public struct IntervalOverride: Sendable, Equatable {
  public var seconds: [Job: Int]

  public init(seconds: [Job: Int] = [:]) {
    self.seconds = seconds
  }

  /// What reading a stored document did, so the caller can log a repair (`app.settings_changed clamped=true`).
  public struct Parsed: Sendable, Equatable {
    public var override: IntervalOverride
    /// True when a value was out of range or the document could not be read.
    public var repaired: Bool
  }

  public static func parse(_ json: String?, provider: ProviderID) -> Parsed {
    guard let json, !json.isEmpty else { return Parsed(override: IntervalOverride(), repaired: false) }
    let raw: [String: Int]
    do {
      raw = try JSONDecoder().decode([String: Int].self, from: Data(json.utf8))
    } catch {
      // Reported by the caller as a repaired value (09: out of range → clamp + log); nothing else to undo.
      return Parsed(override: IntervalOverride(), repaired: true)
    }
    var result = IntervalOverride()
    var repaired = false
    for (name, value) in raw {
      guard let job = Job(rawValue: name) else {
        repaired = true
        continue
      }
      guard let bounds = job.overrideBounds(for: provider) else {
        // `cost`, or `usage` for a provider without a minute cadence: allowed by 09, nothing reads it.
        continue
      }
      let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
      repaired = repaired || clamped != value
      result.seconds[job] = clamped
    }
    return Parsed(override: result, repaired: repaired)
  }

  /// The document the Accounts tab stores; nil when nothing is overridden.
  public func json() -> String? {
    guard !seconds.isEmpty else { return nil }
    let pairs = seconds.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\"\($0.key.rawValue)\":\($0.value)" }
    return "{" + pairs.joined(separator: ",") + "}"
  }
}

extension Job {
  /// The range of the global key an override stands in for (Q-034).
  public func overrideBounds(for provider: ProviderID) -> ClosedRange<Int>? {
    intervalKey(for: provider).flatMap(\.spec.intBounds)
  }
}

extension SettingsKey {
  /// The registered default of an Int key (09).
  var defaultInt: Int {
    if case .int(let value) = spec.defaultValue { return value }
    return 0
  }
}
