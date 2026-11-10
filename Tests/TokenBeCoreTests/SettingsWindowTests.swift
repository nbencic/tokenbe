import Foundation
import Testing
@testable import TokenBeCore

/// 09 `tb.ui.shortcut`: stored text ↔ key code, Carbon modifiers and display.
@Suite struct ShortcutTests {
  @Test("the default ctrl+alt+t parses to kVK_ANSI_T with ⌃⌥ and shows ⌃⌥T")
  func defaultShortcut() throws {
    let shortcut = try #require(Shortcut(setting: "ctrl+alt+t"))
    #expect(shortcut.keyCode == 0x11)
    #expect(shortcut.carbonModifiers == (1 << 12) | (1 << 11))
    #expect(shortcut.display == "\u{2303}\u{2325}T")
    #expect(shortcut.setting == "ctrl+alt+t")
  }

  @Test("modifiers are stored and shown in macOS order whatever order they were typed in")
  func modifierOrder() throws {
    let shortcut = try #require(Shortcut(setting: "cmd+shift+alt+ctrl+f5"))
    #expect(shortcut.setting == "ctrl+alt+shift+cmd+f5")
    #expect(shortcut.display == "\u{2303}\u{2325}\u{21E7}\u{2318}F5")
    #expect(shortcut.carbonModifiers == (1 << 12) | (1 << 11) | (1 << 9) | (1 << 8))
    #expect(shortcut.keyCode == 0x60)
    #expect(Shortcut(setting: "ctrl+space")?.display == "\u{2303}Space")
  }

  @Test("empty means none; anything 09's pattern rejects is not a shortcut", arguments: [
    "", "t", "ctrl+", "ctrl+ctrl+t", "hyper+t", "ctrl+f13", "ctrl+T", "ctrl+alt+tab"
  ])
  func rejected(_ setting: String) {
    #expect(Shortcut(setting: setting) == nil)
  }

  @Test("every key 09 allows has a key code, and recording that key code gives the same key back")
  func roundTrip() throws {
    let keys = (Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)) + (1...12).map { "f\($0)" } + ["space"]
    #expect(Set(keys) == Set(Shortcut.keyCodes.keys))
    #expect(Set(Shortcut.keyCodes.values).count == keys.count, "key codes are distinct")
    for key in keys {
      let stored = try #require(Shortcut(setting: "cmd+\(key)"))
      let recorded = try #require(Shortcut(keyCode: UInt16(stored.keyCode), modifiers: [.cmd]))
      #expect(recorded == stored, "\(key)")
      #expect(SettingSpec.matches(recorded.setting, .shortcut), "\(key)")
    }
  }

  @Test("the recorder refuses a bare key and keys 09 has no name for")
  func recorderRefusals() {
    #expect(Shortcut(keyCode: 0x11, modifiers: []) == nil)
    #expect(Shortcut(keyCode: Shortcut.escapeKeyCode, modifiers: [.ctrl]) == nil)
    #expect(Shortcut(keyCode: 0x30, modifiers: [.ctrl]) == nil, "Tab")
    #expect(Shortcut(keyCode: 0x28, modifiers: [.ctrl, .alt])?.setting == "ctrl+alt+k")
  }
}

/// Fake login item: records calls and can fail.
@MainActor
final class FakeLoginItem: LoginItemService {
  struct Failure: Error {}

  var isEnabled: Bool
  var fails = false
  private(set) var calls: [String] = []

  init(enabled: Bool) {
    isEnabled = enabled
  }

  func register() throws {
    calls.append("register")
    if fails { throw Failure() }
    isEnabled = true
  }

  func unregister() throws {
    calls.append("unregister")
    if fails { throw Failure() }
    isEnabled = false
  }
}

/// 09 `tb.general.launchAtLogin`: mirrors the system at launch (`source=system`), drives it on change, and a
/// failure logs `app.login_item_failed` and shows the actual status.
@MainActor @Suite struct LoginItemControllerTests {
  @Test("at launch the setting follows the system and the mismatch is logged with source=system")
  func mirrorsAtLaunch() async {
    let harness = SettingsTests.Harness()
    #expect(harness.settings.generalLaunchAtLogin == true, "09 default")
    let service = FakeLoginItem(enabled: false)
    let controller = LoginItemController(settings: harness.settings, service: service, logPipeline: harness.pipeline)
    controller.mirrorSystemStatus()
    #expect(harness.settings.generalLaunchAtLogin == false)
    #expect(service.calls.isEmpty, "mirroring never registers")
    let changes = await harness.records(.appSettingsChanged)
    #expect(changes.count == 1)
    #expect(changes.first?.ctx["key"] == .string("tb.general.launchAtLogin"))
    #expect(changes.first?.ctx["source"] == .string("system"))
  }

  @Test("when they already agree nothing is written or logged")
  func agreeing() async {
    let harness = SettingsTests.Harness()
    let service = FakeLoginItem(enabled: true)
    LoginItemController(settings: harness.settings, service: service, logPipeline: harness.pipeline).mirrorSystemStatus()
    #expect(harness.settings.generalLaunchAtLogin == true)
    #expect(await harness.records(.appSettingsChanged).isEmpty)
  }

  @Test("changing the setting registers and unregisters the login item")
  func followsSetting() async {
    let harness = SettingsTests.Harness()
    let service = FakeLoginItem(enabled: false)
    let controller = LoginItemController(settings: harness.settings, service: service, logPipeline: harness.pipeline)
    controller.start()
    harness.settings.generalLaunchAtLogin = true
    await eventually("registered") { await MainActor.run { service.isEnabled } }
    harness.settings.generalLaunchAtLogin = false
    await eventually("unregistered") { await MainActor.run { !service.isEnabled } }
    #expect(service.calls == ["register", "unregister"])
    controller.stop()
  }

  @Test("apply does nothing when the system already matches")
  func applyNoop() {
    let harness = SettingsTests.Harness()
    let service = FakeLoginItem(enabled: true)
    LoginItemController(settings: harness.settings, service: service, logPipeline: harness.pipeline).apply()
    #expect(service.calls.isEmpty)
  }

  @Test("a failure logs app.login_item_failed at error and the toggle shows the actual status")
  func failure() async {
    let harness = SettingsTests.Harness()
    harness.settings.generalLaunchAtLogin = false
    let service = FakeLoginItem(enabled: false)
    service.fails = true
    let controller = LoginItemController(settings: harness.settings, service: service, logPipeline: harness.pipeline)
    harness.settings.generalLaunchAtLogin = true
    controller.apply()
    #expect(service.calls == ["register"])
    #expect(harness.settings.generalLaunchAtLogin == false, "back to what the system has")
    let failures = await harness.records(.appLoginItemFailed)
    #expect(failures.count == 1)
    #expect(failures.first?.lvl == .error)
    #expect(failures.first?.err != nil)
    #expect(failures.first?.ctx["wanted"] == .bool(true))
    let mirrored = await harness.records(.appSettingsChanged).last
    #expect(mirrored?.ctx["source"] == .string("system"))
  }
}

/// 09 `tb.popover.sort` and `tb.popover.manualOrder`.
@Suite struct AccountOrderTests {
  static func account(_ provider: ProviderID, _ label: String, runway: TimeInterval? = nil,
                      remaining: Int64? = nil) -> AccountSummary {
    AccountSummary(id: provider.rawValue, provider: provider, label: label, mode: .direct,
                   remainingCents: remaining, runwayMin: runway)
  }

  let accounts = [
    account(.openai, "OpenAI", runway: 9 * 86_400, remaining: 5_000),
    account(.deepseek, "DeepSeek", runway: nil, remaining: 100),
    account(.xai, "xAI", runway: 2 * 86_400, remaining: nil),
    account(.anthropic, "anthropic", runway: 2 * 86_400, remaining: 5_000)
  ]

  private func order(_ sort: AccountOrder.Sort, manual: [String] = []) -> [ProviderID] {
    AccountOrder.sorted(accounts, by: sort, manualOrder: manual).map(\.provider)
  }

  @Test("runway: shortest first, ties by name, unknown last")
  func byRunway() {
    #expect(order(.runway) == [.anthropic, .xai, .openai, .deepseek])
  }

  @Test("remaining: lowest first, ties by name, unknown last")
  func byRemaining() {
    #expect(order(.remaining) == [.deepseek, .anthropic, .openai, .xai])
  }

  @Test("name: case-insensitive")
  func byName() {
    #expect(order(.name) == [.anthropic, .deepseek, .openai, .xai])
  }

  @Test("manual: the stored order, then missing providers in name order; unknown ids are ignored")
  func manual() {
    #expect(order(.manual, manual: ["xai", "gemini", "openai"]) == [.xai, .openai, .anthropic, .deepseek])
    #expect(order(.manual) == order(.name))
  }

  @Test("equal labels fall back to provider id, so the order is stable")
  func stableTies() {
    let twins = [Self.account(.xai, "Same"), Self.account(.anthropic, "Same")]
    #expect(AccountOrder.sorted(twins, by: .name, manualOrder: []).map(\.provider) == [.anthropic, .xai])
  }
}

/// Steppers take their bounds from 09.
@Suite struct SettingSpecBoundsTests {
  @Test("int settings expose their range; others have none")
  func bounds() {
    #expect(SettingsKey.logRetentionDays.spec.intBounds == 1...90)
    #expect(SettingsKey.alertsWatchDays.spec.intBounds != nil)
    #expect(SettingsKey.logLevel.spec.intBounds == nil)
  }
}
