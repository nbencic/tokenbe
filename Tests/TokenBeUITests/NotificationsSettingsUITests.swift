import XCTest

// ui-covers: Sources/TokenBeApp/SettingsUI/AlertsTab.swift Sources/TokenBeApp/Notifications/
// ui-covers: Sources/TokenBeCore/Notifications/ Sources/TokenBeCore/Ledger/AlertPolicy.swift
/// 14 § Stage 5.4 Tests, `NotificationsSettingsUITests`: Settings → Alerts has the notification toggles per band,
/// quiet hours with its times, and `Send test notification`. Under a `TOKENBE_TEST_ROOT` the app's notifier writes
/// `<root>/notifications.ndjson` instead of asking macOS (Q-043), so the test notification is read back from there.
/// Every toggle is flipped and flipped back, so the shared UI-test settings suite ends as it began (PM-4.2-5).
final class NotificationsSettingsUITests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = makeTestRoot()
  }

  override func tearDownWithError() throws {
    if let root, FileManager.default.fileExists(atPath: root.path) {
      try FileManager.default.removeItem(at: root)
    }
  }

  @MainActor
  func testAlertsTabNotificationControls() throws {
    let app = makeApp(root: root)
    app.launch()
    let settingsRoot = control(app, "settings.root")
    let button = app.buttons["popover.footer.settings"]
    XCTAssertTrue(openPopover(app, until: button), "the popover shows Settings…")
    button.click()
    XCTAssertTrue(settingsRoot.waitForExistence(timeout: 10), "Settings… opens the Settings window")
    let tab = app.toolbars.buttons["Alerts"].exists ? app.toolbars.buttons["Alerts"] : app.buttons["Alerts"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "the Alerts tab exists (08 order: after Sources)")
    tab.click()

    for id in ["notifyLow", "notifyCritical", "notifyUnknown", "notifyStale", "quietHours"] {
      let toggle = control(app, "settings.alerts.\(id)")
      XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(id) exists")
      let before = isOn(toggle)
      toggle.click()
      XCTAssertTrue(waitFor { self.isOn(toggle) != before }, "\(id) flips")
      toggle.click()
      XCTAssertTrue(waitFor { self.isOn(toggle) == before }, "\(id) flips back")
    }
    XCTAssertTrue(control(app, "settings.alerts.quietStart").exists, "quiet hours start")
    XCTAssertTrue(control(app, "settings.alerts.quietEnd").exists, "quiet hours end")
    XCTAssertTrue(control(app, "settings.alerts.watchDays").exists, "5.3's thresholds are on the same tab")

    control(app, "settings.alerts.sendTest").click()
    XCTAssertTrue(control(app, "settings.alerts.testResult").waitForExistence(timeout: 5), "the result shows")
    XCTAssertEqual(text(control(app, "settings.alerts.testResult")), "Sent")
    let sent = try String(contentsOf: root.appendingPathComponent("notifications.ndjson"), encoding: .utf8)
    XCTAssertTrue(sent.contains("\"kind\":\"test\""), "the test notification reached the notifier: \(sent)")
    XCTAssertFalse(control(app, "settings.alerts.denied").exists, "no denied banner when notifications are allowed")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func isOn(_ toggle: XCUIElement) -> Bool? {
    switch toggle.value {
    case let number as NSNumber: number.boolValue
    case let text as String: text == "1"
    default: nil
    }
  }

  private func waitFor(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }
}
