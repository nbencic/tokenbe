import Foundation

/// The production `SettingsStore` (09): `UserDefaults(suiteName: "dev.bathyon.tokenbe")`.
/// This is the ONLY file allowed to use `UserDefaults` (09, lint rule `tokenbe_no_userdefaults`).
public final class UserDefaultsStore: SettingsStore {
  public static let defaultSuiteName = "dev.bathyon.tokenbe"

  public let suiteName: String
  private let defaults: UserDefaults

  /// When the suite equals the running app's bundle id, the app's own domain is used: Foundation refuses
  /// the bundle id as a suite name, and both resolve to the same `defaults` domain (`dev.bathyon.tokenbe`).
  public init(suiteName: String = UserDefaultsStore.defaultSuiteName) {
    self.suiteName = suiteName
    if suiteName == Bundle.main.bundleIdentifier {
      defaults = .standard
    } else {
      // Only `NSGlobalDomain` makes this initializer return nil, and it is never passed here.
      defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }
  }

  public func value(forKey key: String, as type: SettingType) -> SettingValue? {
    guard let object = defaults.object(forKey: key) else { return nil }
    switch object {
    case let text as String: return .string(text)
    case let list as [String]: return .strings(list)
    case let number as NSNumber:
      switch type {
      case .bool: return .bool(number.boolValue)
      case .int: return .int(number.intValue)
      case .double, .string, .strings: return .double(number.doubleValue)
      }
    default:
      // Any other plist type is foreign to 09; `Settings` replaces it with the default and logs.
      return .string(String(describing: object))
    }
  }

  public func set(_ value: SettingValue, forKey key: String) {
    defaults.set(Self.plist(value), forKey: key)
  }

  public func remove(forKey key: String) {
    defaults.removeObject(forKey: key)
  }

  public func registerDefaults(_ values: [String: SettingValue]) {
    defaults.register(defaults: values.mapValues(Self.plist))
  }

  public func storedKeys() -> [String] {
    Array(defaults.persistentDomain(forName: suiteName)?.keys ?? [String: Any]().keys)
  }

  /// Test hook: deletes the whole suite.
  public func removeAll() {
    defaults.removePersistentDomain(forName: suiteName)
  }

  private static func plist(_ value: SettingValue) -> Any {
    switch value {
    case .bool(let flag): flag
    case .int(let number): number
    case .double(let number): number
    case .string(let text): text
    case .strings(let list): list
    }
  }
}
