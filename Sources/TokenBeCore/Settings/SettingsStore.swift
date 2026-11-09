/// A stored setting value. `strings` is the `[String]` type of 09.
public enum SettingValue: Sendable, Equatable {
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case strings([String])

  /// The value as a flat log value for `app.settings_changed` (07).
  var logValue: LogValue {
    switch self {
    case .bool(let flag): .bool(flag)
    case .int(let number): .int(number)
    case .double(let number): .double(number)
    case .string(let text): .string(text)
    case .strings(let list): .string(list.joined(separator: ","))
    }
  }
}

public enum SettingType: Sendable, Equatable {
  case bool, int, double, string, strings
}

/// Settings storage seam (14 § 0.3). Production: the suite-backed store in `Settings/` (suite `dev.bathyon.tokenbe`).
/// Tests and previews: `InMemorySettingsStore`. Only `Settings` talks to a store.
public protocol SettingsStore: AnyObject {
  /// The stored value, else the registered default, else nil. `type` disambiguates numeric storage.
  func value(forKey key: String, as type: SettingType) -> SettingValue?
  func set(_ value: SettingValue, forKey key: String)
  func remove(forKey key: String)
  func registerDefaults(_ defaults: [String: SettingValue])
  /// Keys with an explicitly stored value (registered defaults excluded).
  func storedKeys() -> [String]
}

/// Dictionary-backed store for tests and previews.
public final class InMemorySettingsStore: SettingsStore {
  private var stored: [String: SettingValue]
  private var defaults: [String: SettingValue] = [:]

  public init(stored: [String: SettingValue] = [:]) {
    self.stored = stored
  }

  public func value(forKey key: String, as type: SettingType) -> SettingValue? {
    stored[key] ?? defaults[key]
  }

  public func set(_ value: SettingValue, forKey key: String) { stored[key] = value }
  public func remove(forKey key: String) { stored[key] = nil }
  public func registerDefaults(_ defaults: [String: SettingValue]) { self.defaults.merge(defaults) { _, new in new } }
  public func storedKeys() -> [String] { Array(stored.keys) }

  /// Test hook: the raw stored value, ignoring defaults.
  public func storedValue(forKey key: String) -> SettingValue? { stored[key] }
  /// Test hook: the registered default.
  public func registeredDefault(forKey key: String) -> SettingValue? { defaults[key] }
}
