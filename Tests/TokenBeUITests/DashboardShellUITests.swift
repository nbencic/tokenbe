import XCTest

/// 11 `DashboardShellUITests` (Stage 1.2): ⌘D from the popover opens the Dashboard with its empty Overview;
/// the range picker's choice and the window frame persist across a relaunch; ⌥-click on the glyph opens it.
final class DashboardShellUITests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = makeTestRoot()
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
  }

  /// By scene id: the window's title follows the sidebar selection (`Overview`), not the scene name.
  private func dashboard(_ app: XCUIApplication) -> XCUIElement { app.windows["dashboard"] }

  private func segment(_ app: XCUIApplication, _ label: String) -> XCUIElement {
    dashboard(app).radioButtons[label]
  }

  private func isSelected(_ element: XCUIElement) -> Bool {
    element.isSelected || (element.value as? NSNumber)?.boolValue == true
  }

  @MainActor
  func testCommandDOpensDashboardAndRangePersists() throws {
    // Launch 1 from 09's defaults: open with ⌘D, check the empty Overview, pick 30 d, close, quit.
    let app = makeApp(root: root, resetSettings: true)
    app.launch()
    XCTAssertTrue(openPopover(app, until: app.buttons["popover.footer.openDashboard"]), "popover open")
    XCTAssertEqual(app.buttons["popover.footer.openDashboard"].label, "Open dashboard")
    app.typeKey("d", modifierFlags: .command)
    XCTAssertTrue(dashboard(app).waitForExistence(timeout: 10), "⌘D opens the Dashboard")
    XCTAssertEqual(text(dashboard(app).staticTexts["dashboard.overview.empty.headline"]), "No accounts yet")
    XCTAssertEqual(text(dashboard(app).staticTexts["dashboard.spendByDay.title"]), "Spend by day")
    XCTAssertEqual(text(dashboard(app).staticTexts["dashboard.spendByDay.empty"]), "No spend in this range")
    XCTAssertEqual(text(dashboard(app).staticTexts["dashboard.sidebar.overview"]), "Overview", "sidebar shows Overview")
    let frame = dashboard(app).frame
    XCTAssertGreaterThanOrEqual(frame.width, 920)
    XCTAssertGreaterThanOrEqual(frame.height, 600)
    XCTAssertTrue(isSelected(segment(app, "7 d")), "default range is 7 d")
    segment(app, "30 d").click()
    XCTAssertTrue(isSelected(segment(app, "30 d")))
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(dashboard(app).waitForNonExistence(timeout: 5), "⌘W closes the Dashboard")
    XCTAssertTrue(quitThroughPopover(app), "Quit terminates the app")

    // Launch 2, same settings: the footer button opens the Dashboard where it was, still on 30 d.
    let again = makeApp(root: root)
    again.launch()
    XCTAssertTrue(openPopover(again, until: again.buttons["popover.footer.openDashboard"]))
    again.buttons["popover.footer.openDashboard"].click()
    XCTAssertTrue(dashboard(again).waitForExistence(timeout: 10), "Open dashboard opens it")
    XCTAssertTrue(isSelected(segment(again, "30 d")), "range persists across relaunch")
    XCTAssertEqual(dashboard(again).frame, frame, "frame restored from tb.ui.dashboardFrame")
    XCTAssertTrue(quitThroughPopover(again))
  }

  @MainActor
  func testOptionClickOpensDashboard() throws {
    // No settings reset: the range the other test picked stays for 14's Verify (`1.2.sh`).
    let app = makeApp(root: root)
    app.launch()
    // Reveal the item first (overflow, Q-019), then close the popover and ⌥-click the item itself.
    let quit = app.buttons["popover.footer.quit"]
    XCTAssertTrue(openPopover(app, until: quit))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quit.waitForNonExistence(timeout: 5))
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }
    XCTAssertTrue(dashboard(app).waitForExistence(timeout: 10), "⌥-click opens the Dashboard")
    XCTAssertTrue(quitThroughPopover(app))
  }
}
