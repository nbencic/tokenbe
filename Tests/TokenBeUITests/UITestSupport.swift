import XCTest

/// Shared UI-test helpers (Q-019, Q-020).
extension XCTestCase {
  /// A fresh `TOKENBE_TEST_ROOT` inside the runner's temporary folder (Q-014).
  func makeTestRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("tokenbe-uitests-\(UUID().uuidString)")
  }

  /// The app under `root`, at debug log level. Settings reach the app as launch arguments: the runner is
  /// sandboxed, so its own `UserDefaults` writes never reach the app's suite (Q-019).
  func makeApp(root: URL, resetSettings: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TOKENBE_TEST_ROOT"] = root.path
    if resetSettings { app.launchEnvironment["TOKENBE_TEST_RESET_SETTINGS"] = "1" }
    app.launchArguments += ["-tb.log.level", "debug"]
    return app
  }

  /// Clicks the status item until `element` appears. On a crowded menu bar macOS keeps the item behind its
  /// overflow chevron, and the first click only reveals it (Q-019).
  @MainActor
  func openPopover(_ app: XCUIApplication, until element: XCUIElement) -> Bool {
    let item = app.statusItems.firstMatch
    guard item.waitForExistence(timeout: 10) else { return false }
    for _ in 0..<2 {
      item.click()
      if element.waitForExistence(timeout: 5) { return true }
    }
    return false
  }

  /// A static text's string: macOS exposes it as the accessibility value; the label is usually empty.
  func text(_ element: XCUIElement) -> String {
    (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
  }

  /// Quits through the popover's footer (the clean terminate path) and waits for the app to exit.
  @MainActor
  func quitThroughPopover(_ app: XCUIApplication) -> Bool {
    let quit = app.buttons["popover.footer.quit"]
    guard openPopover(app, until: quit) else { return false }
    quit.click()
    return app.wait(for: .notRunning, timeout: 15)
  }
}
