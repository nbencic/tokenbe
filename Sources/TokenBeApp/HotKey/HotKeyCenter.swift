import Carbon.HIToolbox
import SwiftUI
import TokenBeCore

/// The global shortcut (09 `tb.ui.shortcut`, D-hotkey-carbon): Carbon `RegisterEventHotKey`, which needs no
/// Accessibility permission and consumes the key press. A global `NSEvent` monitor is not allowed (09).
/// One hotkey at a time; registration failure logs `ui.hotkey_failed {shortcut, osstatus}`.
@MainActor
final class HotKeyCenter {
  /// Four-char signature `TkBe`, identifying our hotkey in Carbon events.
  private static let signature: OSType = 0x546B_4265

  private let onPress: @MainActor () -> Void
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private(set) var current: Shortcut?

  init(onPress: @escaping @MainActor () -> Void) {
    self.onPress = onPress
  }

  /// Registers `setting` (empty = none), replacing the previous shortcut.
  func register(_ setting: String) {
    unregister()
    guard let shortcut = Shortcut(setting: setting) else { return }
    installHandlerIfNeeded()
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode, shortcut.carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
      GetApplicationEventTarget(), 0, &ref
    )
    guard status == noErr, let ref else {
      Log.warn(.uiHotkeyFailed, cat: .ui, msg: "global shortcut could not be registered", ctx: [
        "shortcut": .string(setting), "osstatus": .int(Int(status))
      ])
      return
    }
    hotKey = ref
    current = shortcut
  }

  /// Removes the hotkey, e.g. while the recorder listens, so pressing the old shortcut does not toggle the popover.
  func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    current = nil
  }

  fileprivate func pressed() {
    onPress()
  }

  private func installHandlerIfNeeded() {
    guard handler == nil else { return }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, context, &handler)
  }
}

/// Carbon calls this on the main thread for application-target events.
private func hotKeyCallback(_: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
  guard let event, let context else { return OSStatus(eventNotHandledErr) }
  var id = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &id
  )
  guard status == noErr else { return status }
  let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
  MainActor.assumeIsolated { center.pressed() }
  return noErr
}

extension EnvironmentValues {
  /// The app's global-shortcut registration, for the recorder in Settings.
  @Entry var hotKeyCenter: HotKeyCenter?
}
