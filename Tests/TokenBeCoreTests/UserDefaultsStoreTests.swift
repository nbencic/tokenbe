import Foundation
import Testing
@testable import TokenBeCore

/// The production settings store, on a throwaway suite (never the app's `dev.bathyon.tokenbe` domain).
@MainActor @Suite struct UserDefaultsStoreTests {
  static func makeStore() -> UserDefaultsStore {
    UserDefaultsStore(suiteName: "dev.bathyon.tokenbe.tests.\(UUID().uuidString)")
  }

  @Test("round-trips every value type, falls back to registered defaults, and lists stored keys")
  func roundTrip() {
    let store = Self.makeStore()
    defer { store.removeAll() }
    store.registerDefaults(["tb.a": .bool(true), "tb.n": .int(5)])
    #expect(store.value(forKey: "tb.a", as: .bool) == .bool(true))
    #expect(store.value(forKey: "tb.n", as: .int) == .int(5))
    #expect(store.value(forKey: "tb.missing", as: .string) == nil)
    struct Case {
      let key: String
      let value: SettingValue
      let type: SettingType
    }
    let values: [Case] = [
      Case(key: "tb.bool", value: .bool(false), type: .bool), Case(key: "tb.int", value: .int(42), type: .int),
      Case(key: "tb.double", value: .double(1.25), type: .double), Case(key: "tb.string", value: .string("dark"), type: .string),
      Case(key: "tb.strings", value: .strings(["xai", "openai"]), type: .strings)
    ]
    for item in values {
      store.set(item.value, forKey: item.key)
      #expect(store.value(forKey: item.key, as: item.type) == item.value, "\(item.key)")
    }
    #expect(Set(store.storedKeys()) == Set(values.map(\.key)))
    store.remove(forKey: "tb.int")
    #expect(store.value(forKey: "tb.int", as: .int) == nil)
    #expect(store.value(forKey: "tb.double", as: .string) == .double(1.25), "numbers read for a string type stay numbers")
  }

  @Test("Settings over the real store: defaults, clamping and reset")
  func settingsOverRealStore() {
    let store = Self.makeStore()
    defer { store.removeAll() }
    let pipeline = LogPipeline(sinks: [], version: "test")
    let settings = Settings(store: store, logPipeline: pipeline)
    #expect(settings.pollUsageIntervalOpenAIS == 300)
    settings.pollUsageIntervalOpenAIS = 10
    #expect(Settings(store: store, logPipeline: pipeline).pollUsageIntervalOpenAIS == 60)
    settings.uiOnboardingDone = true
    settings.resetAll()
    #expect(store.storedKeys() == ["tb.ui.onboardingDone"])
    #expect(UserDefaultsStore().suiteName == UserDefaultsStore.defaultSuiteName)
  }
}
