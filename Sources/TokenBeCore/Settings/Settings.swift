import Foundation
import Observation

/// The only way to read or write a setting (09). Validates on write — out-of-range or invalid values are clamped and
/// logged with `clamped=true` — keeps `critical < low < watch`, announces every change (`Settings.didChange` and
/// `changes`), and binds `tb.log.level` to the log pipeline's minimum level.
@Observable @MainActor
public final class Settings {
  public enum Source: String, Sendable {
    case user, system
  }

  /// Posted with `userInfo[Settings.changedKeyName]` = the key's full name (09).
  public static let didChange = Notification.Name("dev.bathyon.tokenbe.Settings.didChange")
  public static let changedKeyName = "key"
  /// Lower to higher: `critical < low < watch` (09 § Alerts).
  public static let thresholdKeys: [SettingsKey] = [.alertsCriticalDays, .alertsLowDays, .alertsWatchDays]

  @ObservationIgnored private let store: any SettingsStore
  @ObservationIgnored private let pipeline: LogPipeline?
  @ObservationIgnored private var subscribers: [Int: AsyncStream<SettingsKey>.Continuation] = [:]
  @ObservationIgnored private var nextSubscriber = 0
  /// Current values by full key name. Observed: views that read any setting update when it changes.
  private var values: [String: SettingValue] = [:]

  /// Registers every default of 09, validates what is stored (invalid values are replaced and logged as
  /// `source=system`), repairs the threshold order, and applies `tb.log.level`.
  /// `logPipeline` is for tests; the app logs through `Log`.
  public init(store: any SettingsStore, logPipeline: LogPipeline? = nil) {
    self.store = store
    self.pipeline = logPipeline
    store.registerDefaults(Self.registrationDefaults())
    loadAll()
    bindLogLevel()
  }

  /// Every default of 09, templated keys expanded for every provider. The 09 table is the only source.
  public static func registrationDefaults() -> [String: SettingValue] {
    var defaults: [String: SettingValue] = [:]
    for key in SettingsKey.allCases { defaults[key.rawValue] = key.spec.defaultValue }
    for key in TemplatedSettingsKey.allCases { defaults[key.name] = key.spec.defaultValue }
    return defaults
  }

  // MARK: - Reading

  public func value(_ key: SettingsKey) -> SettingValue {
    values[key.rawValue] ?? key.spec.defaultValue
  }

  public func value(_ key: TemplatedSettingsKey) -> SettingValue {
    if let cached = values[key.name] { return cached }
    return key.spec.validate(store.value(forKey: key.name, as: key.spec.type) ?? key.spec.defaultValue).value
  }

  public func bool(_ key: SettingsKey) -> Bool {
    if case .bool(let flag) = value(key) { return flag }
    return false
  }

  public func int(_ key: SettingsKey) -> Int {
    if case .int(let number) = value(key) { return number }
    return 0
  }

  public func double(_ key: SettingsKey) -> Double {
    if case .double(let number) = value(key) { return number }
    return 0
  }

  public func string(_ key: SettingsKey) -> String {
    if case .string(let text) = value(key) { return text }
    return ""
  }

  public func strings(_ key: SettingsKey) -> [String] {
    if case .strings(let list) = value(key) { return list }
    return []
  }

  public func isPopoverExpanded(_ provider: ProviderID) -> Bool {
    if case .bool(let flag) = value(SettingsKey.expanded(provider)) { return flag }
    return false
  }

  public func snoozedUntil(_ provider: ProviderID) -> Double {
    if case .double(let epoch) = value(SettingsKey.snoozedUntil(provider)) { return epoch }
    return 0
  }

  // MARK: - Writing

  public func set(_ key: SettingsKey, _ value: SettingValue, source: Source = .user) {
    var (validated, clamped) = key.spec.validate(value)
    if Self.thresholdKeys.contains(key) {
      let ordered = orderedThreshold(key, validated)
      clamped = clamped || ordered != validated
      validated = ordered
    }
    guard apply(name: key.rawValue, old: self.value(key), new: validated, clamped: clamped, source: source) else { return }
    if key == .logLevel { bindLogLevel() }
    publish(key)
  }

  public func set(_ key: TemplatedSettingsKey, _ value: SettingValue, source: Source = .user) {
    let (validated, clamped) = key.spec.validate(value)
    guard apply(name: key.name, old: self.value(key), new: validated, clamped: clamped, source: source) else { return }
    notify(name: key.name)
  }

  public func setPopoverExpanded(_ provider: ProviderID, _ expanded: Bool) {
    set(SettingsKey.expanded(provider), .bool(expanded))
  }

  public func setSnoozedUntil(_ provider: ProviderID, _ epoch: Double) {
    set(SettingsKey.snoozedUntil(provider), .double(epoch))
  }

  /// Account removal (09 § Reset semantics): drops the provider's templated keys.
  public func removeProviderKeys(_ provider: ProviderID) {
    for key in [SettingsKey.expanded(provider), SettingsKey.snoozedUntil(provider)] {
      let old = value(key)
      store.remove(forKey: key.name)
      values[key.name] = nil
      guard old != key.spec.defaultValue else { continue }
      logChange(name: key.name, old: old, new: key.spec.defaultValue, clamped: false, source: .user)
      notify(name: key.name)
    }
  }

  /// `Reset all settings…` (09): removes every `tb.*` key except `tb.ui.onboardingDone`, re-registers the
  /// defaults and logs `app.settings_reset`. Keychain, database and logs are untouched.
  public func resetAll() {
    let keep = SettingsKey.uiOnboardingDone.rawValue
    let removed = store.storedKeys().filter { $0.hasPrefix("tb.") && $0 != keep }
    for key in removed { store.remove(forKey: key) }
    store.registerDefaults(Self.registrationDefaults())
    values = [:]
    loadAll()
    bindLogLevel()
    emit(.appSettingsReset, msg: "settings reset", ctx: ["keys_removed": .int(removed.count)])
    for key in SettingsKey.allCases { publish(key) }
  }

  // MARK: - Observing

  /// A new stream of changed keys for each caller (several subscribers can listen at once).
  public var changes: AsyncStream<SettingsKey> {
    let (stream, continuation) = AsyncStream.makeStream(of: SettingsKey.self, bufferingPolicy: .bufferingNewest(64))
    let id = nextSubscriber
    nextSubscriber += 1
    subscribers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor in self?.subscribers[id] = nil }
    }
    return stream
  }

  // MARK: - Internals

  /// Loads every key, replacing invalid stored values, then repairs the threshold order.
  private func loadAll() {
    for key in SettingsKey.allCases {
      let raw = store.value(forKey: key.rawValue, as: key.spec.type) ?? key.spec.defaultValue
      let (validated, clamped) = key.spec.validate(raw)
      values[key.rawValue] = validated
      if clamped {
        store.set(validated, forKey: key.rawValue)
        logChange(name: key.rawValue, old: raw, new: validated, clamped: true, source: .system)
      }
    }
    let critical = int(.alertsCriticalDays)
    let low = int(.alertsLowDays)
    let watch = int(.alertsWatchDays)
    guard !(critical < low && low < watch) else { return }
    for key in Self.thresholdKeys {
      let old = value(key)
      values[key.rawValue] = key.spec.defaultValue
      store.set(key.spec.defaultValue, forKey: key.rawValue)
      logChange(name: key.rawValue, old: old, new: key.spec.defaultValue, clamped: true, source: .system)
    }
  }

  /// Clamps one threshold so that `critical < low < watch` holds with the other two.
  private func orderedThreshold(_ key: SettingsKey, _ value: SettingValue) -> SettingValue {
    guard case .int(let number) = value else { return value }
    let critical = int(.alertsCriticalDays)
    let low = int(.alertsLowDays)
    let watch = int(.alertsWatchDays)
    switch key {
    case .alertsCriticalDays: return .int(min(number, low - 1))
    case .alertsLowDays: return .int(max(critical + 1, min(number, watch - 1)))
    case .alertsWatchDays: return .int(max(number, low + 1))
    default: return value
    }
  }

  /// Stores and logs the change; returns false when there was nothing to do (same value, not clamped).
  private func apply(name: String, old: SettingValue, new: SettingValue, clamped: Bool, source: Source) -> Bool {
    guard new != old || clamped else { return false }
    if new != old {
      store.set(new, forKey: name)
      values[name] = new
    }
    logChange(name: name, old: old, new: new, clamped: clamped, source: source)
    return true
  }

  private func logChange(name: String, old: SettingValue, new: SettingValue, clamped: Bool, source: Source) {
    emit(.appSettingsChanged, msg: "setting changed", ctx: [
      "key": .string(name), "old": old.logValue, "new": new.logValue,
      "clamped": .bool(clamped), "source": .string(source.rawValue)
    ])
  }

  /// Both settings events are `info` (07).
  private func emit(_ evt: Evt, msg: String, ctx: [String: LogValue]) {
    if let pipeline {
      pipeline.emit(.info, evt, cat: .app, msg: msg, ctx: ctx)
    } else {
      Log.info(evt, cat: .app, msg: msg, ctx: ctx)
    }
  }

  private func publish(_ key: SettingsKey) {
    for continuation in subscribers.values { continuation.yield(key) }
    notify(name: key.rawValue)
  }

  private func notify(name: String) {
    NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: [Self.changedKeyName: name])
  }

  /// `tb.log.level` → minimum level of the log pipeline (14 § Stage 0.3 step 3).
  private func bindLogLevel() {
    let level = LogLevel(rawValue: string(.logLevel)) ?? .info
    if let pipeline {
      pipeline.minimumLevel = level
    } else {
      Log.minimumLevel = level
    }
  }
}
