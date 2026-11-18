import XCTest

// ui-covers: Sources/TokenBeApp/SettingsUI/ResetSettingsButton.swift Sources/TokenBeCore/Settings/
/// E2E-6 (11; 14 § Stage 9.5; Q-059), under a throwaway `TOKENBE_TEST_ROOT`: one control in each Settings tab is
/// changed through the UI and its 09 key is written (`app.settings_changed`); a relaunch shows the new values; `Reset
/// all settings…` (destructive confirm) logs `app.settings_reset` and every control shows its 09 default again, live.
/// The keys `makeApp` pins by launch argument (log level, onboarding, fixture mode) are left alone: the argument domain
/// would hide a reset. The test runs in a settings suite of its own, so its Reset leaves the shared one alone. Each tab's other controls have their own suites (General, Sources, Alerts, Privacy, Advanced).
final class SettingsRoundTripUITests: XCTestCase {
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

  /// A settings suite of its own (`TOKENBE_TEST_SETTINGS_SUITE`), cleared at the first launch: Reset must not wipe
  /// the shared UI-test suite, whose values later checks read (PM-1.2-2, Q-059).
  @MainActor
  private func launch(resetFirst: Bool) -> XCUIApplication {
    let app = makeApp(root: root, resetSettings: resetFirst)
    app.launchEnvironment["TOKENBE_TEST_SETTINGS_SUITE"] = "roundtrip"
    app.launch()
    return app
  }

  @MainActor
  func testEveryTabRoundTripsAndResets() throws {
    let app = launch(resetFirst: true)
    try openSettings(app)

    // One control per tab, each written to its 09 key.
    try selectTab(app, "General")
    let hideCents = control(app, "settings.general.hideCents")
    XCTAssertTrue(hideCents.waitForExistence(timeout: 5))
    hideCents.click()
    XCTAssertTrue(waitFor { self.newValue("tb.ui.hideCents") != nil }, "Hide cents writes tb.ui.hideCents")
    try selectTab(app, "Sources")
    try step(app, "settings.sources.usageOpenAI", key: "tb.poll.usageIntervalOpenAIS")
    try selectTab(app, "Alerts")
    try step(app, "settings.alerts.watchDays", key: "tb.alerts.watchDays")
    try selectTab(app, "Privacy")
    let updates = control(app, "settings.privacy.checkForUpdates")
    XCTAssertTrue(updates.waitForExistence(timeout: 5))
    updates.click()
    XCTAssertTrue(waitFor { self.newValue("tb.update.checkEnabled") != nil }, "the toggle writes its key")
    try selectTab(app, "Advanced")
    try step(app, "settings.advanced.hourlyRetention", key: "tb.retention.hourlyDays")
    let hours = try XCTUnwrap(newValue("tb.retention.hourlyDays"))
    let checks = try XCTUnwrap(newValue("tb.update.checkEnabled"))
    try selectTab(app, "General")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    // A relaunch shows what was written.
    let again = launch(resetFirst: false)
    try openSettings(again)
    try selectTab(again, "Privacy")
    XCTAssertEqual(toggleValue(control(again, "settings.privacy.checkForUpdates")), checks == "true",
                   "Privacy shows the stored value after a relaunch")
    try selectTab(again, "Advanced")
    XCTAssertTrue(waitFor { self.texts(again, "\(hours) days") >= 1 }, "Advanced shows \(hours) days")

    // Reset all settings… → confirm: the defaults are back, live, in every tab touched.
    let reset = control(again, "settings.advanced.resetAll")
    XCTAssertTrue(reset.waitForExistence(timeout: 5), "Reset all settings… exists")
    XCTAssertEqual(reset.title.isEmpty ? reset.label : reset.title, "Reset all settings\u{2026}")
    reset.click()
    // A macOS confirmation dialog may not carry the button's identifier; its title is 09's `Reset`.
    let byID = control(again, "settings.advanced.resetAll.confirm")
    let confirm = byID.waitForExistence(timeout: 3) ? byID : again.sheets.buttons["Reset"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the destructive confirm appears")
    confirm.click()
    XCTAssertTrue(waitFor { self.logContains("\"evt\":\"app.settings_reset\"") }, "app.settings_reset is logged")
    XCTAssertTrue(waitFor { self.texts(again, "90 days") >= 2 }, "hourly and raw-harness retention show 09's 90 days")
    try selectTab(again, "Privacy")
    XCTAssertTrue(toggleValue(control(again, "settings.privacy.checkForUpdates")), "Check for updates daily is on")
    try selectTab(again, "General")
    XCTAssertTrue(toggleValue(control(again, "settings.general.hideCents")), "Hide cents is on (09's default)")
    XCTAssertTrue(quitThroughPopover(again), "the app quits")

    let reset0 = try XCTUnwrap(try logLines().first { $0.contains("\"evt\":\"app.settings_reset\"") })
    XCTAssertFalse(reset0.contains("\"keys_removed\":0"), "the reset removed the stored keys: \(reset0)")
    let failures = try logLines().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
  }

  // MARK: - Helpers

  /// One step up a stepper, asserted from the key's `app.settings_changed`.
  @MainActor
  private func step(_ app: XCUIApplication, _ identifier: String, key: String) throws {
    let stepper = app.steppers[identifier].firstMatch
    XCTAssertTrue(stepper.waitForExistence(timeout: 5), "\(identifier) exists")
    let before = changes(key)
    stepper.incrementArrows.firstMatch.click()
    XCTAssertTrue(waitFor { self.changes(key) > before }, "\(identifier) writes \(key)")
  }

  /// Static texts whose label or value is `text`.
  private func texts(_ app: XCUIApplication, _ text: String) -> Int {
    app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).count
  }

  private func toggleValue(_ element: XCUIElement) -> Bool {
    XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) exists")
    return (element.value as? Int ?? (element.value as? NSNumber)?.intValue ?? 0) == 1
  }

  @MainActor
  private func openSettings(_ app: XCUIApplication) throws {
    let button = app.buttons["popover.footer.settings"]
    XCTAssertTrue(openPopover(app, until: button), "the popover shows Settings…")
    button.click()
    XCTAssertTrue(control(app, "settings.root").waitForExistence(timeout: 10), "Settings… opens the Settings window")
  }

  @MainActor
  private func selectTab(_ app: XCUIApplication, _ name: String) throws {
    let tab = app.toolbars.buttons[name].exists ? app.toolbars.buttons[name] : app.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name) exists")
    tab.click()
  }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The `new` of the latest `app.settings_changed` for `key`, as JSON text (`true`, `360`, `"x"`).
  private func newValue(_ key: String) -> String? {
    guard let line = lines().last(where: { $0.contains("\"evt\":\"app.settings_changed\"") && $0.contains("\"key\":\"\(key)\"") }),
          let range = line.range(of: "\"new\":") else { return nil }
    let rest = line[range.upperBound...]
    return String(rest.prefix { $0 != "," && $0 != "}" }).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
  }

  private func changes(_ key: String) -> Int {
    lines().filter { $0.contains("\"evt\":\"app.settings_changed\"") && $0.contains("\"key\":\"\(key)\"") }.count
  }

  private func logContains(_ text: String) -> Bool { lines().contains { $0.contains(text) } }

  private func lines() -> [String] {
    do {
      return try logLines()
    } catch {
      XCTFail("log unreadable: \(error)")
      return []
    }
  }

  private func logLines() throws -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }

  private func waitFor(timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }
}
