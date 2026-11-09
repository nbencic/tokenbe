import XCTest

/// 11 `PopoverEmptyStateUITests` (Stage 1.1): open the popover, assert identifiers and 08 copy, Quit terminates cleanly.
final class PopoverEmptyStateUITests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = FileManager.default.temporaryDirectory.appendingPathComponent("tokenbe-uitests-\(UUID().uuidString)")
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
  }

  private func logText() throws -> String {
    let logs = root.appendingPathComponent("Logs/TokenBe")
    return try FileManager.default.contentsOfDirectory(atPath: logs.path)
      .map { try String(contentsOf: logs.appendingPathComponent($0), encoding: .utf8) }
      .joined()
  }

  private func count(_ evt: String, in text: String) -> Int {
    text.components(separatedBy: "\"evt\":\"\(evt)\"").count - 1
  }

  /// A static text's string: macOS exposes it as the accessibility value; the label is usually empty.
  private func text(_ element: XCUIElement) -> String {
    (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
  }

  /// Clicks the status item until the popover shows. On a crowded menu bar macOS keeps the item behind its
  /// overflow chevron, and the first click only reveals it; the second click then reaches the item (Q-019).
  @MainActor
  private func openPopover(_ item: XCUIElement, until element: XCUIElement) -> Bool {
    for _ in 0..<2 {
      item.click()
      if element.waitForExistence(timeout: 5) { return true }
    }
    return false
  }

  @MainActor
  func testEmptyStateAndQuit() throws {
    let app = XCUIApplication()
    app.launchEnvironment["TOKENBE_TEST_ROOT"] = root.path
    // Debug logging, so the popover's debug-level events reach the log file. The runner is sandboxed: its own
    // UserDefaults writes land in its container, so settings reach the app through the arguments domain (Q-019).
    app.launchArguments += ["-tb.log.level", "debug"]
    app.launch()
    let item = app.statusItems.firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 10))

    let headline = app.staticTexts["popover.empty.headline"]
    XCTAssertTrue(openPopover(item, until: headline), "Empty state shown")
    XCTAssertEqual(text(headline), "No accounts yet")
    XCTAssertEqual(text(app.staticTexts["popover.empty.body"]), "Add a provider key to start tracking.")
    XCTAssertEqual(text(app.staticTexts["popover.header.title"]), "TokenBe")
    XCTAssertTrue(app.buttons["popover.footer.quit"].exists)
    XCTAssertEqual(app.buttons["popover.footer.quit"].label, "Quit")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Add account…")).firstMatch.exists,
                   "Add account… arrives with onboarding in 3.5")

    // Close and reopen: each opening is a popover session.
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(headline.waitForNonExistence(timeout: 5), "popover closed")
    XCTAssertTrue(openPopover(item, until: headline), "popover reopened")

    app.buttons["popover.footer.quit"].click()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Quit terminates the app")

    let log = try logText()
    XCTAssertEqual(count("app.terminate", in: log), 1, "clean terminate path ran")
    XCTAssertGreaterThanOrEqual(count("ui.popover_open", in: log), 2)
    XCTAssertGreaterThanOrEqual(count("ui.popover_close", in: log), 1)
    XCTAssertTrue(log.contains("\"dur_ms\":"), "popover close carries dur_ms")
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: root.appendingPathComponent("Application Support/TokenBe/.running").path), "sentinel removed")
  }
}
