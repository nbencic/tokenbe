import Foundation
import Testing
@testable import TokenBeCore

/// 09 § Definition of done: every key has a registered default; below/above range (or invalid) clamps and logs;
/// `critical < low < watch` repair; reset keeps `tb.ui.onboardingDone`; templated keys round-trip.
@MainActor @Suite struct SettingsTests {
  /// Settings over an in-memory store with a private log pipeline, so assertions never touch global state.
  @MainActor struct Harness {
    let store: InMemorySettingsStore
    let sink: CapturingLogSink
    let pipeline: LogPipeline
    let settings: Settings

    init(stored: [String: SettingValue] = [:]) {
      store = InMemorySettingsStore(stored: stored)
      sink = CapturingLogSink()
      pipeline = LogPipeline(sinks: [sink], version: "test")
      pipeline.startConsumer()
      settings = Settings(store: store, logPipeline: pipeline)
    }

    func records(_ evt: Evt) async -> [LogRecord] {
      await pipeline.drain()
      return await sink.records.filter { $0.evt == evt }
    }
  }

  /// A value outside each rule, low and high where a range exists.
  static func invalidValues(for spec: SettingSpec) -> [SettingValue] {
    switch spec.rule {
    case .none: return spec.type == .bool ? [.string("not a bool")] : []
    case .intRange(let range), .threshold(let range):
      var values: [SettingValue] = [.string("wrong type")]
      if range.lowerBound > Int.min { values.append(.int(range.lowerBound - 1)) }
      if range.upperBound < Int.max { values.append(.int(range.upperBound + 1)) }
      return values
    case .doubleMin(let minimum): return [.double(minimum - 1), .double(.nan), .bool(true)]
    case .oneOf: return [.string("definitely-not-allowed"), .int(1)]
    case .pattern: return [.string("not a valid value ##"), .bool(false)]
    case .providerIDs: return [.strings(["openai", "gemini", "openai"]), .string("openai")]
    case .fixed: return [.string("/somewhere/else")]
    }
  }

  @Test("09 lists exactly the keys of SettingsKey, and every key has a registered default")
  func everyKeyHasDefault() {
    let harness = Harness()
    for key in SettingsKey.allCases {
      #expect(harness.store.registeredDefault(forKey: key.rawValue) == key.spec.defaultValue, "\(key.rawValue)")
      #expect(harness.settings.value(key) == key.spec.defaultValue, "\(key.rawValue)")
      #expect(key.spec.validate(key.spec.defaultValue).clamped == false, "default of \(key.rawValue) is valid")
    }
    for key in TemplatedSettingsKey.allCases {
      #expect(harness.store.registeredDefault(forKey: key.name) == key.spec.defaultValue)
    }
    #expect(SettingsKey.allCases.count == 53)
    #expect(SettingsKey.allCases.allSatisfy { $0.rawValue.hasPrefix("tb.") })
  }

  @Test("writing a below-range, above-range or invalid value clamps and logs clamped=true", arguments: SettingsKey.allCases)
  func clampsAndLogs(key: SettingsKey) async throws {
    for invalid in Self.invalidValues(for: key.spec) {
      let harness = Harness()
      harness.settings.set(key, invalid)
      let stored = harness.settings.value(key)
      #expect(key.spec.validate(stored).clamped == false, "\(key.rawValue) stored a valid value")
      let logged = try #require(await harness.records(.appSettingsChanged).last, "\(key.rawValue) logged")
      #expect(logged.ctx["key"] == .string(key.rawValue))
      #expect(logged.ctx["clamped"] == .bool(true), "\(key.rawValue) ← \(invalid)")
      #expect(logged.ctx["source"] == .string("user"))
    }
  }

  @Test("range clamping goes to the nearest bound; valid writes log old/new without clamping")
  func clampingDetails() async throws {
    let harness = Harness()
    let settings = harness.settings
    settings.pollBalanceIntervalS = 5
    #expect(settings.pollBalanceIntervalS == 30)
    settings.pollBalanceIntervalS = 999_999
    #expect(settings.pollBalanceIntervalS == 3600)
    settings.pollBalanceIntervalS = 120
    let last = try #require(await harness.records(.appSettingsChanged).last)
    #expect(last.ctx == ["key": "tb.poll.balanceIntervalS", "old": 3600, "new": 120, "clamped": false, "source": "user"])
    settings.pollBalanceIntervalS = 120
    #expect(await harness.records(.appSettingsChanged).count == 3, "an unchanged write logs nothing")
    settings.pollPausedUntil = -5
    #expect(settings.pollPausedUntil == 0)
    settings.set(.pollPausedUntil, .int(1_800_000_000))
    #expect(settings.pollPausedUntil == 1_800_000_000, "an int is accepted for a Double setting")
    settings.popoverManualOrder = ["xai", "openai", "xai", "gemini"]
    #expect(settings.popoverManualOrder == ["xai", "openai"])
    settings.ingestFolderPath = "/tmp/elsewhere"
    #expect(settings.ingestFolderPath == SettingSpec.ingestFolderPath)
    #expect(SettingSpec.ingestFolderPath.hasSuffix("Library/Application Support/TokenBe/ingest"))
  }

  @Test("pattern rules accept 09's formats and reject others")
  func patterns() {
    let valid: [(SettingSpec.Pattern, String)] = [
      (.shortcut, "ctrl+alt+t"), (.shortcut, ""), (.shortcut, "cmd+shift+f12"), (.shortcut, "ctrl+space"),
      (.rect, ""), (.rect, "{{100, 200}, {920, 600}}"), (.rect, "{{-12.5, 0}, {1024.5, 768}}"),
      (.clockTime, "23:00"), (.clockTime, "07:00"), (.clockTime, "00:59"),
      (.httpsURL, "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"),
      (.semver, ""), (.semver, "1.0.0"), (.semver, "1.2.3-beta.1+42")
    ]
    let invalid: [(SettingSpec.Pattern, String)] = [
      (.shortcut, "t"), (.shortcut, "ctrl+ctrl+t"), (.shortcut, "hyper+t"), (.shortcut, "ctrl+"), (.shortcut, "ctrl+f13"),
      (.rect, "{{1, 2}, {3}}"), (.rect, "garbage"),
      (.clockTime, "24:00"), (.clockTime, "7:00"), (.clockTime, "12:60"),
      (.httpsURL, "http://example.com/x"), (.httpsURL, "https://"), (.httpsURL, "not a url"),
      (.semver, "1.0"), (.semver, "v1.0.0")
    ]
    for (pattern, text) in valid { #expect(SettingSpec.matches(text, pattern), "\(pattern) should accept \(text)") }
    for (pattern, text) in invalid { #expect(!SettingSpec.matches(text, pattern), "\(pattern) should reject \(text)") }
  }

  @Test("threshold writes keep critical < low < watch")
  func thresholdOrderOnWrite() async throws {
    let harness = Harness()
    let settings = harness.settings
    settings.alertsCriticalDays = 10
    #expect(settings.alertsCriticalDays == 6, "critical < low (7)")
    settings.alertsLowDays = 3
    #expect(settings.alertsLowDays == 7, "low > critical (6)")
    settings.alertsLowDays = 20
    #expect(settings.alertsLowDays == 13, "low < watch (14)")
    settings.alertsWatchDays = 5
    #expect(settings.alertsWatchDays == 14, "watch > low (13)")
    settings.alertsWatchDays = 400
    #expect(settings.alertsWatchDays == 365)
    #expect(settings.alertsCriticalDays < settings.alertsLowDays && settings.alertsLowDays < settings.alertsWatchDays)
    let clamped = await harness.records(.appSettingsChanged).filter { $0.ctx["clamped"] == .bool(true) }
    #expect(clamped.count == 5)
  }

  @Test("stored values that break the threshold order are repaired at launch, source=system")
  func thresholdRepairAtLaunch() async throws {
    let harness = Harness(stored: [
      "tb.alerts.criticalDays": .int(9), "tb.alerts.lowDays": .int(8), "tb.alerts.watchDays": .int(30)
    ])
    #expect(harness.settings.alertsCriticalDays == 2)
    #expect(harness.settings.alertsLowDays == 7)
    #expect(harness.settings.alertsWatchDays == 14)
    let logged = await harness.records(.appSettingsChanged)
    #expect(logged.count == 3)
    #expect(logged.allSatisfy { $0.ctx["source"] == .string("system") && $0.ctx["clamped"] == .bool(true) })
    #expect(harness.store.storedValue(forKey: "tb.alerts.criticalDays") == .int(2))
  }

  @Test("invalid stored values are replaced at launch and logged with source=system")
  func invalidStoredValues() async throws {
    let harness = Harness(stored: [
      "tb.menubar.metric": .string("bogus"), "tb.poll.keysIntervalS": .int(1), "tb.ui.hideCents": .string("yes")
    ])
    #expect(harness.settings.menubarMetric == "minRunway")
    #expect(harness.settings.pollKeysIntervalS == 600)
    #expect(harness.settings.uiHideCents == true)
    let logged = await harness.records(.appSettingsChanged)
    #expect(Set(logged.compactMap { record -> String? in
      if case .string(let key) = record.ctx["key"] { return key }
      return nil
    }) == ["tb.menubar.metric", "tb.poll.keysIntervalS", "tb.ui.hideCents"])
    #expect(harness.store.storedValue(forKey: "tb.menubar.metric") == .string("minRunway"))
  }

  @Test("resetAll removes every tb.* key except tb.ui.onboardingDone and logs app.settings_reset")
  func resetKeepsOnboarding() async throws {
    let harness = Harness()
    let settings = harness.settings
    settings.uiOnboardingDone = true
    settings.pollBalanceIntervalS = 90
    settings.uiAppearance = "dark"
    settings.setSnoozedUntil(.xai, 1_900_000_000)
    harness.store.set(.string("kept"), forKey: "other.app.key")
    settings.resetAll()
    #expect(settings.uiOnboardingDone == true)
    #expect(settings.pollBalanceIntervalS == 60)
    #expect(settings.uiAppearance == "system")
    #expect(settings.snoozedUntil(.xai) == 0)
    #expect(harness.store.storedValue(forKey: "tb.ui.onboardingDone") == .bool(true))
    #expect(harness.store.storedValue(forKey: "other.app.key") == .string("kept"))
    #expect(harness.store.storedKeys().filter { $0.hasPrefix("tb.") } == ["tb.ui.onboardingDone"])
    let reset = try #require(await harness.records(.appSettingsReset).first)
    #expect(reset.ctx["keys_removed"] == .int(3))
  }

  @Test("templated per-provider keys round-trip and are removed with the account", arguments: ProviderID.allCases)
  func templatedKeys(provider: ProviderID) async {
    let harness = Harness()
    let settings = harness.settings
    #expect(SettingsKey.expanded(provider).name == "tb.popover.expanded.\(provider.rawValue)")
    #expect(SettingsKey.snoozedUntil(provider).name == "tb.alerts.snoozedUntil.\(provider.rawValue)")
    #expect(!settings.isPopoverExpanded(provider))
    settings.setPopoverExpanded(provider, true)
    settings.setSnoozedUntil(provider, 1_900_000_000)
    #expect(settings.isPopoverExpanded(provider))
    #expect(settings.snoozedUntil(provider) == 1_900_000_000)
    let reopened = Settings(store: harness.store, logPipeline: harness.pipeline)
    #expect(reopened.isPopoverExpanded(provider))
    #expect(reopened.snoozedUntil(provider) == 1_900_000_000)
    settings.setSnoozedUntil(provider, -1)
    #expect(settings.snoozedUntil(provider) == 0)
    settings.removeProviderKeys(provider)
    #expect(!settings.isPopoverExpanded(provider))
    #expect(harness.store.storedValue(forKey: SettingsKey.expanded(provider).name) == nil)
    #expect(await harness.records(.appSettingsChanged).count == 4)
    settings.removeProviderKeys(provider)
    #expect(await harness.records(.appSettingsChanged).count == 4, "nothing left to remove")
  }

  @Test("changes stream and Settings.didChange announce each changed key")
  func changeNotifications() async throws {
    let harness = Harness()
    let settings = harness.settings
    let stream = settings.changes
    let center = NotificationCenter.default
    let received = LockedNames()
    let token = center.addObserver(forName: Settings.didChange, object: settings, queue: nil) { note in
      if let name = note.userInfo?[Settings.changedKeyName] as? String { received.append(name) }
    }
    defer { center.removeObserver(token) }
    settings.uiHideCents = false
    settings.uiHideCents = false
    settings.setPopoverExpanded(.openai, true)
    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == .uiHideCents)
    #expect(received.names == ["tb.ui.hideCents", "tb.popover.expanded.openai"])
  }

  @Test("tb.log.level drives the pipeline's minimum level")
  func logLevelBinding() {
    let harness = Harness(stored: ["tb.log.level": .string("warn")])
    #expect(harness.pipeline.minimumLevel == .warn)
    harness.settings.logLevel = "debug"
    #expect(harness.pipeline.minimumLevel == .debug)
    harness.settings.logLevel = "fault"
    #expect(harness.settings.logLevel == "info", "fault is not a 09 value")
    #expect(harness.pipeline.minimumLevel == .info)
  }

  @Test("typed accessors read and write every type")
  func typedAccessors() {
    let settings = Harness().settings
    settings.generalLaunchAtLogin = false
    settings.dailyRunCount = 7
    settings.dbLastBackupAt = 1_700_000_000.5
    settings.alertsQuietStart = "22:30"
    settings.popoverManualOrder = ["deepseek"]
    #expect(settings.bool(.generalLaunchAtLogin) == false)
    #expect(settings.int(.dailyRunCount) == 7)
    #expect(settings.double(.dbLastBackupAt) == 1_700_000_000.5)
    #expect(settings.string(.alertsQuietStart) == "22:30")
    #expect(settings.strings(.popoverManualOrder) == ["deepseek"])
    #expect(settings.int(.uiHideCents) == 0, "wrong-type read falls back")
    #expect(settings.bool(.dailyRunCount) == false)
    #expect(settings.double(.uiShortcut) == 0)
    #expect(settings.string(.dailyRunCount).isEmpty)
    #expect(settings.strings(.dailyRunCount).isEmpty)
  }

  @Test("ProviderID matches the 03 CHECK constraint")
  func providerIDs() {
    #expect(ProviderID.allCases.map(\.rawValue) == ["openai", "anthropic", "openrouter", "deepseek", "xai"])
  }
}

/// Collects notification key names from the posting thread.
final class LockedNames: @unchecked Sendable {
  // Invariant: `names` is only touched under `lock` (test helper).
  private let lock = NSLock()
  private var storage: [String] = []
  var names: [String] { lock.withLock { storage } }
  func append(_ name: String) { lock.withLock { storage.append(name) } }
}
