import AppKit
import TokenBeCore

/// Runs the startup sequence (04) and the clean-terminate path (07 § Crash handling); owns the `AppModel` and the
/// global shortcut.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  private(set) lazy var hotKeys = HotKeyCenter { [weak self] in self?.toggleDashboard() }
  private let startup = Startup()
  private var shortcutWatcher: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
      guard await startup.run() else { return }
      model.environment = startup.environment
      if let settings = startup.environment?.settings {
        model.bind(settings)
        watchShortcut(settings)
      }
      model.missingKeys = startup.missingKeys
      if let repository = startup.environment?.repository {
        model.observe(repository)
      }
      if let settings = startup.environment?.settings, !settings.uiOnboardingDone, startup.accountCount == 0 {
        model.showOnboarding()
      }
    }
  }

  /// Terminate later, so the log is flushed and the sentinel removed before the process exits.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    shortcutWatcher?.cancel()
    hotKeys.unregister()
    Task {
      await startup.terminate(reason: startup.terminationReason)
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  /// 09 `tb.ui.shortcut`: registered now and again on every change.
  private func watchShortcut(_ settings: TokenBeCore.Settings) {
    hotKeys.register(settings.uiShortcut)
    let changes = settings.changes
    shortcutWatcher = Task { [weak self] in
      for await key in changes where key == .uiShortcut {
        self?.hotKeys.register(settings.uiShortcut)
      }
    }
  }

  /// The global shortcut (09 `tb.ui.shortcut`) toggles the Dashboard: it opens and brings it forward, or closes it
  /// when it is already the front window. `MenuBarExtra` cannot be opened from code on macOS 26+, so the shortcut
  /// cannot toggle the popover as first specified (Q-023).
  func toggleDashboard() {
    if let window = NSApp.keyWindow, window.identifier?.rawValue.hasPrefix(DashboardView.windowID) == true,
       NSApp.isActive {
      window.performClose(nil)
      return
    }
    NSApp.activate()
    model.openDashboard?()
  }
}
