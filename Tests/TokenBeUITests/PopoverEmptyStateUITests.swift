import XCTest

/// 11 `PopoverEmptyStateUITests` (Stage 1.1): open the popover, assert identifiers and 08 copy, Quit terminates cleanly.
final class PopoverEmptyStateUITests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = makeTestRoot()
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

  @MainActor
  func testEmptyStateAndQuit() throws {
    let app = makeApp(root: root)
    app.launch()

    let headline = app.staticTexts["popover.empty.headline"]
    XCTAssertTrue(openPopover(app, until: headline), "Empty state shown")
    XCTAssertEqual(text(headline), "No accounts yet")
    XCTAssertEqual(text(app.staticTexts["popover.empty.body"]), "Add a provider key to start tracking.")
    XCTAssertEqual(text(app.staticTexts["popover.header.title"]), "TokenBe")
    XCTAssertTrue(app.buttons["popover.footer.quit"].exists)
    XCTAssertEqual(app.buttons["popover.footer.quit"].label, "Quit")
    XCTAssertEqual(app.buttons["popover.empty.addAccount"].label, "Add account\u{2026}",
                   "Add account… opens onboarding (3.5; covered by OnboardingUITests)")

    // Close and reopen: each opening is a popover session.
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(headline.waitForNonExistence(timeout: 5), "popover closed")
    XCTAssertTrue(openPopover(app, until: headline), "popover reopened")

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
