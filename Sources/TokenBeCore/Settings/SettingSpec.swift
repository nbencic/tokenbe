import Foundation

/// Provider identifiers (03 `account.provider` CHECK). Declared here for templated keys; adapters arrive in Phase 3.
public enum ProviderID: String, CaseIterable, Sendable {
  case openai, anthropic, openrouter, deepseek, xai
}

/// Type, default, validation rule and tab of one setting (09).
public struct SettingSpec: Sendable {
  public enum Tab: String, Sendable {
    case general, sources, alerts, privacy, advanced
  }

  public enum Pattern: Sendable {
    /// `modifier(+modifier)*+key`, modifiers `ctrl alt shift cmd` (each once), key `a–z 0–9 f1–f12 space`; empty = none.
    case shortcut
    /// `NSStringFromRect` output `{{x, y}, {w, h}}`; empty = no saved frame.
    case rect
    /// `HH:mm`, 24-hour.
    case clockTime
    /// An absolute `https` URL with a host.
    case httpsURL
    /// `MAJOR.MINOR.PATCH` with optional pre-release/build; empty = none.
    case semver
  }

  public enum Rule: Sendable {
    case none
    case intRange(ClosedRange<Int>)
    /// One of `critical < low < watch` (09 § Alerts); the range is the key's own bound, the order is repaired by `Settings`.
    case threshold(ClosedRange<Int>)
    case doubleMin(Double)
    case oneOf([String])
    case pattern(Pattern)
    /// `[String]` of `ProviderID` raw values, each once.
    case providerIDs
    /// Read-only: always the default (`tb.ingest.folderPath`).
    case fixed
  }

  public let type: SettingType
  public let defaultValue: SettingValue
  public let rule: Rule
  public let tab: Tab

  public init(type: SettingType, defaultValue: SettingValue, rule: Rule, tab: Tab) {
    self.type = type
    self.defaultValue = defaultValue
    self.rule = rule
    self.tab = tab
  }

  /// `~/Library/Application Support/TokenBe/ingest` (06), fixed in V1.
  public static var ingestFolderPath: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/TokenBe/ingest", isDirectory: true).path
  }

  /// The value to store and whether it had to be changed ("clamped", 09). Wrong types fall back to the default.
  public func validate(_ value: SettingValue) -> (value: SettingValue, clamped: Bool) {
    guard let typed = coerced(value) else { return (defaultValue, true) }
    switch rule {
    case .none: return (typed, false)
    case .intRange(let range), .threshold(let range): return bounded(typed, range)
    case .doubleMin(let minimum): return atLeast(typed, minimum)
    case .oneOf(let allowed): return accepted(typed) { allowed.contains($0) }
    case .pattern(let pattern): return accepted(typed) { SettingSpec.matches($0, pattern) }
    case .providerIDs: return providers(typed)
    case .fixed: return (defaultValue, typed != defaultValue)
    }
  }

  private func bounded(_ value: SettingValue, _ range: ClosedRange<Int>) -> (value: SettingValue, clamped: Bool) {
    guard case .int(let number) = value else { return (defaultValue, true) }
    let clamped = min(max(number, range.lowerBound), range.upperBound)
    return (.int(clamped), clamped != number)
  }

  private func atLeast(_ value: SettingValue, _ minimum: Double) -> (value: SettingValue, clamped: Bool) {
    guard case .double(let number) = value, number.isFinite else { return (defaultValue, true) }
    return number < minimum ? (.double(minimum), true) : (value, false)
  }

  private func accepted(_ value: SettingValue, _ isValid: (String) -> Bool) -> (value: SettingValue, clamped: Bool) {
    guard case .string(let text) = value, isValid(text) else { return (defaultValue, true) }
    return (value, false)
  }

  private func providers(_ value: SettingValue) -> (value: SettingValue, clamped: Bool) {
    guard case .strings(let list) = value else { return (defaultValue, true) }
    var seen = Set<String>()
    let cleaned = list.filter { ProviderID(rawValue: $0) != nil && seen.insert($0).inserted }
    return (.strings(cleaned), cleaned != list)
  }

  /// The value in this spec's type; an `int` is accepted for a `double` setting.
  private func coerced(_ value: SettingValue) -> SettingValue? {
    switch (type, value) {
    case (.bool, .bool), (.int, .int), (.double, .double), (.string, .string), (.strings, .strings): value
    case (.double, .int(let number)): .double(Double(number))
    default: nil
    }
  }

  static func matches(_ text: String, _ pattern: Pattern) -> Bool {
    switch pattern {
    case .shortcut:
      if text.isEmpty { return true }
      let parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
      guard parts.count >= 2, let key = parts.last else { return false }
      let modifiers = parts.dropLast()
      let allowed: Set<String> = ["ctrl", "alt", "shift", "cmd"]
      guard Set(modifiers).count == modifiers.count, modifiers.allSatisfy(allowed.contains) else { return false }
      return key.wholeMatch(of: /[a-z0-9]|f([1-9]|1[0-2])|space/) != nil
    case .rect:
      return text.isEmpty
        || text.wholeMatch(of: /\{\{-?\d+(\.\d+)?, -?\d+(\.\d+)?\}, \{\d+(\.\d+)?, \d+(\.\d+)?\}\}/) != nil
    case .clockTime:
      return text.wholeMatch(of: /([01]\d|2[0-3]):[0-5]\d/) != nil
    case .httpsURL:
      guard let url = URL(string: text), url.scheme == "https", let host = url.host() else { return false }
      return !host.isEmpty
    case .semver:
      return text.isEmpty || text.wholeMatch(of: /\d+\.\d+\.\d+(-[0-9A-Za-z.\-]+)?(\+[0-9A-Za-z.\-]+)?/) != nil
    }
  }
}

/// A per-provider key of 09: `tb.popover.expanded.<provider>`, `tb.alerts.snoozedUntil.<provider>`.
public struct TemplatedSettingsKey: Hashable, Sendable {
  public enum Template: String, CaseIterable, Sendable {
    case popoverExpanded = "tb.popover.expanded"
    case alertsSnoozedUntil = "tb.alerts.snoozedUntil"
  }

  public let template: Template
  public let provider: ProviderID

  public var name: String { "\(template.rawValue).\(provider.rawValue)" }

  public var spec: SettingSpec {
    switch template {
    case .popoverExpanded: SettingSpec(type: .bool, defaultValue: .bool(false), rule: .none, tab: .general)
    case .alertsSnoozedUntil: SettingSpec(type: .double, defaultValue: .double(0), rule: .doubleMin(0), tab: .alerts)
    }
  }

  public static var allCases: [TemplatedSettingsKey] {
    Template.allCases.flatMap { template in ProviderID.allCases.map { TemplatedSettingsKey(template: template, provider: $0) } }
  }
}

extension SettingsKey {
  /// `tb.popover.expanded.<provider>` (09 § General).
  public static func expanded(_ provider: ProviderID) -> TemplatedSettingsKey {
    TemplatedSettingsKey(template: .popoverExpanded, provider: provider)
  }

  /// `tb.alerts.snoozedUntil.<provider>` (09 § Alerts).
  public static func snoozedUntil(_ provider: ProviderID) -> TemplatedSettingsKey {
    TemplatedSettingsKey(template: .alertsSnoozedUntil, provider: provider)
  }
}
