import XCTest

/// 14 § Stage 1.3 Tests: every General control writes its 09 key; the appearance flips; the global shortcut toggles
/// the Dashboard (Q-023: `MenuBarExtra` cannot be opened from code); Advanced writes the log level. The test does not reset settings, because the Dashboard test's `30d`
/// must survive for 1.2's check (PM-1.2-2). Instead, each control is first set to one value and then to its
/// target, so every run really writes. `scripts/stages/1.3.sh` reads the final values from the UI-test suite.
final class SettingsGeneralUITests: XCTestCase {
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
  func testGeneralControlsWriteSettingsAndShortcutTogglesDashboard() throws {
    let app = makeApp(root: root)
    app.launch()
    try openSettings(app)
    // The Settings window reopens on the tab last used in this suite, e.g. Advanced after 2.2's test (Q-025).
    try selectTab(app, "General")

    checkLaunchAtLogin(app)
    checkGeneralControls(app)
    try checkShortcut(app)
    try checkLogLevel(app)

    // Relaunch: the values come back from the settings suite.
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
    let retention = try retentionChangesAfterWarning()
    XCTAssertEqual(retention.count, 1, "only the change made at Info is logged: \(retention)")
    app.launch()
    try openSettings(app)
    try selectTab(app, "General")
    let settingsRoot = control(app, "settings.root")
    XCTAssertEqual(isOn(control(app, "settings.general.launchAtLogin")), true, "launch at login persisted")
    XCTAssertEqual(control(app, "settings.general.menubarMetric").value as? String, "Today\u{2019}s spend")
    XCTAssertEqual(control(app, "settings.general.sort").value as? String, "Name")
    XCTAssertEqual(isOn(control(app, "settings.general.hideCents")), false, "hide cents persisted")
    XCTAssertTrue(waitFor { settingsRoot.value as? String == "dark" }, "Dark persisted")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  // MARK: - Steps

  @MainActor
  private func checkLaunchAtLogin(_ app: XCUIApplication) {
    // Launch at login: a fresh test root has no (fake) login item, so the toggle mirrors "off" (09).
    let launchAtLogin = control(app, "settings.general.launchAtLogin")
    XCTAssertEqual(isOn(launchAtLogin), false, "launch at login mirrors the system's status at launch")
    launchAtLogin.click()
    XCTAssertTrue(waitFor { self.isOn(launchAtLogin) == true }, "launch at login turns on")
    XCTAssertTrue(waitFor { FileManager.default.fileExists(atPath: self.loginMarker.path) },
                  "turning it on registers the (test) login item")
  }

  @MainActor
  private func checkGeneralControls(_ app: XCUIApplication) {
    // Pickers: a known value first, then the target.
    choose(app, "settings.general.menubarMetric", "None", then: "Today\u{2019}s spend")
    choose(app, "settings.general.pinnedMetric", "Runway", then: "Remaining")
    choose(app, "settings.general.sort", "Runway", then: "Name")
    XCTAssertFalse(control(app, "settings.general.currencyDisplay").isEnabled, "currency display is disabled in v1")
    XCTAssertTrue(app.staticTexts["Conversion is not in v1"].exists)

    // Toggles: on first, then off.
    setToggle(app, "settings.general.hideCents", on: true)
    setToggle(app, "settings.general.hideCents", on: false)
    setToggle(app, "settings.general.useSystemAccent", on: true)
    setToggle(app, "settings.general.useSystemAccent", on: false)

    // Appearance flips every scene: the Settings root reports its effective colour scheme.
    let settingsRoot = control(app, "settings.root")
    choose(app, "settings.general.appearance", "System", then: "Light")
    XCTAssertTrue(waitFor { settingsRoot.value as? String == "light" }, "Light makes the window light")
    choose(app, "settings.general.appearance", "Light", then: "Dark")
    XCTAssertTrue(waitFor { settingsRoot.value as? String == "dark" }, "Dark makes the window dark")
  }

  @MainActor
  private func checkShortcut(_ app: XCUIApplication) throws {
    // Global shortcut: record ⌃⌥K, which then toggles the Dashboard; clear it; record the default ⌃⌥T again.
    let recorder = control(app, "settings.general.shortcut")
    let dashboard = app.windows["dashboard"]
    record(app, recorder, key: "k", expect: "\u{2303}\u{2325}K")
    app.typeKey("k", modifierFlags: [.control, .option])
    XCTAssertTrue(dashboard.waitForExistence(timeout: 5), "the recorded shortcut opens the Dashboard")
    app.typeKey("k", modifierFlags: [.control, .option])
    XCTAssertTrue(waitFor { !dashboard.exists }, "pressed again, it closes the Dashboard")
    recorder.click()
    XCTAssertTrue(waitFor { self.label(recorder) == "Type shortcut\u{2026}" }, "the recorder listens")
    app.typeKey(.delete, modifierFlags: [])
    XCTAssertTrue(waitFor { self.label(recorder) == "None" }, "\u{232B} clears the shortcut")
    record(app, recorder, key: "t", expect: "\u{2303}\u{2325}T")
    app.typeKey("t", modifierFlags: [.control, .option])
    XCTAssertTrue(dashboard.waitForExistence(timeout: 5), "the default shortcut opens the Dashboard")
    app.typeKey("t", modifierFlags: [.control, .option])
    XCTAssertTrue(waitFor { !dashboard.exists }, "and closes it")
  }

  @MainActor
  private func checkLogLevel(_ app: XCUIApplication) throws {
    // Advanced: the log level applies live (07). At Warning, a retention change (an info event) is not written;
    // back at Info, the next one is. The level ends at the default, so later launches log as usual.
    try openSettings(app)
    try selectTab(app, "Advanced")
    XCTAssertTrue(control(app, "settings.advanced.openLogFolder").exists)
    let stepper = app.steppers.firstMatch
    XCTAssertTrue(stepper.waitForExistence(timeout: 5), "log retention stepper exists")
    choose(app, "settings.advanced.logLevel", "Debug", then: "Warning")
    stepper.incrementArrows.firstMatch.click()
    choose(app, "settings.advanced.logLevel", "Warning", then: "Info")
    stepper.decrementArrows.firstMatch.click()
  }

  // MARK: - Helpers

  /// `app.settings_changed` records for `tb.log.retentionDays` written after the level was set to `warn`.
  private func retentionChangesAfterWarning() throws -> [[String: Any]] {
    let logs = root.appendingPathComponent("Logs/TokenBe")
    let files = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }.sorted { $0.path < $1.path }
    var records: [[String: Any]] = []
    for file in files {
      for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
        if let record = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
          records.append(record)
        }
      }
    }
    let changes = records.filter { $0["evt"] as? String == "app.settings_changed" }
    let key = { (record: [String: Any]) in (record["ctx"] as? [String: Any])?["key"] as? String }
    let new = { (record: [String: Any]) in (record["ctx"] as? [String: Any])?["new"] as? String }
    guard let warning = changes.lastIndex(where: { key($0) == "tb.log.level" && new($0) == "warn" }) else {
      XCTFail("the change to warn is logged (it is written at the old level, info)")
      return []
    }
    return changes[(warning + 1)...].filter { key($0) == "tb.log.retentionDays" }
  }

  private var loginMarker: URL { root.appendingPathComponent("login-item-enabled") }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  private func openSettings(_ app: XCUIApplication) throws {
    let settingsRoot = control(app, "settings.root")
    if settingsRoot.exists { return }
    let button = app.buttons["popover.footer.settings"]
    XCTAssertTrue(openPopover(app, until: button), "the popover shows Settings…")
    button.click()
    XCTAssertTrue(settingsRoot.waitForExistence(timeout: 10), "Settings… opens the Settings window")
  }

  @MainActor
  private func selectTab(_ app: XCUIApplication, _ name: String) throws {
    let tab = app.toolbars.buttons[name].exists ? app.toolbars.buttons[name] : app.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name) exists")
    tab.click()
  }

  @MainActor
  private func choose(_ app: XCUIApplication, _ identifier: String, _ first: String, then target: String) {
    for title in [first, target] {
      let picker = control(app, identifier)
      XCTAssertTrue(picker.waitForExistence(timeout: 5), "\(identifier) exists")
      picker.click()
      let item = app.menuItems[title]
      XCTAssertTrue(item.waitForExistence(timeout: 5), "\(identifier) offers \(title)")
      item.click()
      XCTAssertTrue(waitFor { picker.value as? String == title }, "\(identifier) shows \(title)")
    }
  }

  @MainActor
  private func setToggle(_ app: XCUIApplication, _ identifier: String, on wanted: Bool) {
    let toggle = control(app, identifier)
    XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(identifier) exists")
    if isOn(toggle) != wanted { toggle.click() }
    XCTAssertTrue(waitFor { self.isOn(toggle) == wanted }, "\(identifier) is \(wanted ? "on" : "off")")
  }

  @MainActor
  private func record(_ app: XCUIApplication, _ recorder: XCUIElement, key: String, expect: String) {
    recorder.click()
    XCTAssertTrue(waitFor { self.label(recorder) == "Type shortcut\u{2026}" }, "the recorder listens")
    app.typeKey(key, modifierFlags: [.control, .option])
    XCTAssertTrue(waitFor { self.label(recorder) == expect }, "the recorder shows \(expect)")
  }

  private func isOn(_ toggle: XCUIElement) -> Bool? {
    switch toggle.value {
    case let number as NSNumber: number.boolValue
    case let text as String: text == "1"
    default: nil
    }
  }

  private func label(_ element: XCUIElement) -> String {
    element.label.isEmpty ? text(element) : element.label
  }

  private func waitFor(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
  }
}
