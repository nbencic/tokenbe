import AppKit
import SwiftUI
import TokenBeCore

/// The Global shortcut control (08 § Settings · General, 09 `tb.ui.shortcut`). Shows the shortcut (`⌃⌥T`); a click
/// starts recording, and the next key press with a modifier becomes the shortcut. ⌫ clears it (none), Esc cancels.
/// Listens with a local monitor only: a global one needs Accessibility (09). The registered hotkey is removed while
/// recording, so pressing the current shortcut records it instead of toggling the popover.
struct HotKeyRecorder: View {
  @Binding var setting: String
  @Environment(\.hotKeyCenter) private var hotKeys
  @State private var monitor = KeyDownMonitor()

  var body: some View {
    Button(label) {
      if monitor.isActive {
        finish(nil)
      } else {
        start()
      }
    }
    .help(Strings.shortcutHelp)
    .accessibilityIdentifier("settings.general.shortcut")
    .onDisappear { if monitor.isActive { finish(nil) } }
  }

  private var label: String {
    if monitor.isActive { return Strings.shortcutRecording }
    return Shortcut(setting: setting)?.display ?? Strings.shortcutNone
  }

  private func start() {
    hotKeys?.unregister()
    monitor.start { event in handle(event) }
  }

  /// Consumes every key press while recording.
  private func handle(_ event: NSEvent) {
    if event.keyCode == Shortcut.escapeKeyCode {
      finish(nil)
    } else if Shortcut.deleteKeyCodes.contains(event.keyCode) {
      finish("")
    } else if let shortcut = Shortcut(keyCode: event.keyCode, modifiers: Self.modifiers(event.modifierFlags)) {
      finish(shortcut.setting)
    } else {
      NSSound.beep()
    }
  }

  /// Stores `newValue` (nil = keep the current shortcut) and registers the hotkey again.
  private func finish(_ newValue: String?) {
    monitor.stop()
    if let newValue { setting = newValue }
    hotKeys?.register(setting)
  }

  private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<Shortcut.Modifier> {
    var result = Set<Shortcut.Modifier>()
    if flags.contains(.control) { result.insert(.ctrl) }
    if flags.contains(.option) { result.insert(.alt) }
    if flags.contains(.shift) { result.insert(.shift) }
    if flags.contains(.command) { result.insert(.cmd) }
    return result
  }
}

/// Owns the local key-down monitor of one recorder.
@MainActor @Observable
final class KeyDownMonitor {
  @ObservationIgnored private var token: Any?
  private(set) var isActive = false

  func start(_ onKeyDown: @escaping @MainActor (NSEvent) -> Void) {
    stop()
    isActive = true
    token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      MainActor.assumeIsolated { onKeyDown(event) }
      return nil
    }
  }

  func stop() {
    if let token { NSEvent.removeMonitor(token) }
    token = nil
    isActive = false
  }
}
