import XCTest

/// 11 `PopoverEmptyStateUITests` (Stage 1.1): open the popover, assert identifiers and 08 copy, Quit terminates cleanly.
final class PopoverEmptyStateUITests: XCTestCase {
  /// The Debug-only settings suite used under `TOKENBE_TEST_ROOT` (Q-014).
  static let suite = "dev.bathyon.tokenbe.uitests"

  private var root: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = FileManager.default.temporaryDirectory.appendingPathComponent("tokenbe-uitests-\(UUID().uuidString)")
    // Start from a clean suite, with debug logging so the popover's debug events reach the log file.
    let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suite))
    defaults.removePersistentDomain(forName: Self.suite)
    defaults.set("debug", forKey: "tb.log.level")
  }

  override func tearDownWithError() throws {
    UserDefaults(suiteName: Self.suite)?.removePersistentDomain(forName: Self.suite)
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

  @MainActor
  func testEmptyStateAndQuit() throws {
    let app = XCUIApplication()
    app.launchEnvironment["TOKENBE_TEST_ROOT"] = root.path
    app.launch()
    let item = app.statusItems.firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 10))

    item.click()
    let headline = app.staticTexts["popover.empty.headline"]
    XCTAssertTrue(headline.waitForExistence(timeout: 10), "Empty state shown")
    XCTAssertEqual(headline.label, "No accounts yet")
    XCTAssertEqual(app.staticTexts["popover.empty.body"].label, "Add a provider key to start tracking.")
    XCTAssertEqual(app.staticTexts["popover.header.title"].label, "TokenBe")
    XCTAssertTrue(app.buttons["popover.footer.quit"].exists)
    XCTAssertEqual(app.buttons["popover.footer.quit"].label, "Quit")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Add account…")).firstMatch.exists,
                   "Add account… arrives with onboarding in 3.5")

    // Close and reopen: each opening is a popover session.
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(headline.waitForNonExistence(timeout: 5), "popover closed")
    item.click()
    XCTAssertTrue(headline.waitForExistence(timeout: 10), "popover reopened")

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
