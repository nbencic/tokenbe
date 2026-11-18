import XCTest

// ui-covers: Sources/TokenBeApp/Update/ Sources/TokenBeApp/Components/UpdateBadge.swift
// ui-covers: Sources/TokenBeApp/SettingsUI/PrivacyTab.swift Sources/TokenBeCore/Update/
/// 14 § Stage 9.4 (02 § Update check; 08 § Settings Privacy; 09 `tb.update.*`), under a throwaway `TOKENBE_TEST_ROOT`
/// with no network: a `tb.update.latestSeen` newer than the bundle, seeded by launch argument, shows `Update
/// available` above the popover footer, at the top of the Overview and in Privacy; `Check for updates daily` (with
/// 08's caption) hides it while off; `Skip this version` writes `tb.update.ignoredVersion` and hides it everywhere.
/// The version is new on every run, so a skip left in the shared settings domain never hides it (PM-1.2-2). The
/// test never presses `Open release page`, which would open the owner's browser.
final class UpdateCheckUITests: XCTestCase {
  private var root: URL!
  private let version = "99.\(Int(Date().timeIntervalSince1970)).0"

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
  func testBadgeToggleAndSkip() throws {
    let app = makeApp(root: root)
    app.launchArguments += ["-tb.update.latestSeen", version]
    app.launch()

    // Settings → Privacy: the row and its caption; the toggle starts on (normalized: the shared domain may hold off).
    let settings = app.buttons["popover.footer.settings"]
    XCTAssertTrue(openPopover(app, until: settings), "the popover opens")
    settings.click()
    XCTAssertTrue(control(app, "settings.root").waitForExistence(timeout: 10), "Settings opens")
    try selectTab(app, "Privacy")
    let toggle = control(app, "settings.privacy.checkForUpdates")
    XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Check for updates daily exists")
    if (toggle.value as? Int ?? 1) == 0 { toggle.click() }
    XCTAssertTrue(app.staticTexts["Check for updates daily"].exists, "08's label")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'One GET a day to the GitHub releases API.'"))
      .count + app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'One GET a day to the GitHub releases API.'"))
      .count > 0, "08's caption")
    let privacyBadge = control(app, "settings.privacy.update.badge")
    XCTAssertTrue(privacyBadge.waitForExistence(timeout: 5), "Privacy shows Update available")
    XCTAssertTrue(text(privacyBadge).contains("Update available") && text(privacyBadge).contains(version),
                  "the badge names the version: `\(text(privacyBadge))`")
    XCTAssertTrue(control(app, "settings.privacy.update.open").exists, "Open release page exists (never pressed)")

    // Off hides the badge; on brings it back.
    toggle.click()
    XCTAssertTrue(privacyBadge.waitForNonExistence(timeout: 5), "no badge while the daily check is off")
    XCTAssertTrue(waitFor { self.settingChanged("tb.update.checkEnabled", to: "false") }, "the toggle writes its key")
    toggle.click()
    XCTAssertTrue(privacyBadge.waitForExistence(timeout: 5), "the badge returns with the check on")
    try selectTab(app, "General")
    app.typeKey("w", modifierFlags: .command)

    // The popover, above its footer, and the Overview.
    app.activate()
    let popoverBadge = control(app, "popover.update.badge")
    XCTAssertTrue(openPopover(app, until: popoverBadge), "the popover shows Update available")
    control(app, "popover.footer.openDashboard").click()
    XCTAssertTrue(control(app, "dashboard.overview.update.badge").waitForExistence(timeout: 10),
                  "the Overview shows Update available")

    // Skip this version, from the Overview: gone everywhere, and the key holds the version.
    control(app, "dashboard.overview.update.skip").click()
    XCTAssertTrue(control(app, "dashboard.overview.update.badge").waitForNonExistence(timeout: 5), "skipped")
    XCTAssertTrue(waitFor { self.settingChanged("tb.update.ignoredVersion", to: self.version) },
                  "Skip writes tb.update.ignoredVersion")
    XCTAssertTrue(openPopover(app, until: app.buttons["popover.footer.quit"]), "the popover opens")
    XCTAssertFalse(popoverBadge.exists, "no badge in the popover after Skip")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    let failures = try logLines().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
    XCTAssertFalse(try logLines().contains { $0.contains("\"evt\":\"update.check_") },
                   "no check runs at launch: the GET belongs to the daily activity")
  }

  // MARK: - Helpers

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  private func selectTab(_ app: XCUIApplication, _ name: String) throws {
    let tab = app.toolbars.buttons[name].exists ? app.toolbars.buttons[name] : app.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name) exists")
    tab.click()
  }

  /// The newest `app.settings_changed` record for `key` has `new` = `value` (a string or a bare JSON value).
  private func settingChanged(_ key: String, to value: String) -> Bool {
    let lines: [String]
    do {
      lines = try logLines()
    } catch {
      XCTFail("log unreadable: \(error)")
      return false
    }
    let last = lines.last { $0.contains("\"evt\":\"app.settings_changed\"") && $0.contains("\"key\":\"\(key)\"") }
    return last?.contains("\"new\":\(value)") == true || last?.contains("\"new\":\"\(value)\"") == true
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
