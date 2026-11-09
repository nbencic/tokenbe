import AppKit
import TokenBeCore

/// Runs the startup sequence (04) and the clean-terminate path (07 § Crash handling); owns the `AppModel`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  private let startup = Startup()

  func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
      await startup.run()
      model.environment = startup.environment
    }
  }

  /// Terminate later, so the log is flushed and the sentinel removed before the process exits.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await startup.terminate(reason: "quit")
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
