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

/// The store's remaining paths (PM-0.5-2), each on a throwaway suite.
@MainActor @Suite struct UserDefaultsStoreEdgeTests {
  @Test("a value of a type 09 does not use reads back as text, so Settings can replace it")
  func foreignType() throws {
    let name = "dev.bathyon.tokenbe.tests.\(UUID().uuidString)"
    let raw = try #require(UserDefaults(suiteName: name))
    defer { raw.removePersistentDomain(forName: name) }
    raw.set(Data([1, 2]), forKey: "tb.data")
    let store = SettingsSuite.store(named: name)
    guard case .string(let text) = store.value(forKey: "tb.data", as: .string) else {
      Issue.record("a foreign value must read back as text")
      return
    }
    #expect(text.contains("0102"))
  }

  @Test("resetUITests refuses every suite but the UI-test one")
  func resetRefuses() {
    #expect(SettingsSuite.resetUITests(named: SettingsSuite.name) == false)
    #expect(SettingsSuite.resetUITests(named: "dev.bathyon.tokenbe.tests.other") == false)
  }
}
