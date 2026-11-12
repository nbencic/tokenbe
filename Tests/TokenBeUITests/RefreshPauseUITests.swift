import XCTest

/// 14 § Stage 4.1 Tests, `RefreshPauseUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014):
/// - a new account is polled at once by the coordinator, and the header reads `Refreshed …`;
/// - the refresh button runs the jobs again;
/// - `Pause polling for 1 h` shows `Paused · resumes HH:mm` and `Resume`; `Resume` restores the header;
/// - Settings → Sources changes `tb.poll.usageIntervalOpenAIS`; the Accounts `Paused` toggle makes the scheduler skip.
/// Every value it changes it changes back (`pausedUntil` 0, the interval 300 s, the account unpaused, General
/// selected), so later suites and stage checks see 09's defaults (PM-1.3-2, PM-2.2-1, PM-2.2-2).
final class RefreshPauseUITests: XCTestCase {
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

  /// Built at run time so no key-shaped literal is committed (Q-028).
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Rp4", count: 14)

  @MainActor
  func testRefreshPauseResumeSourcesAndPausedAccount() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true)
    app.launch()
    try onboard(app)
    XCTAssertTrue(waitFor { self.count("\"evt\":\"poll.ok\"", job: "usage") == 1 },
                  "the coordinator polls the new account at once (PM-3.6-3)")

    // Header: freshness and refresh.
    let freshness = control(app, "popover.header.freshness")
    XCTAssertTrue(openPopover(app, until: freshness), "the header shows the freshness")
    XCTAssertEqual(text(freshness), "Refreshed just now")
    control(app, "popover.header.refresh").click()
    XCTAssertTrue(waitFor { self.count("\"evt\":\"poll.ok\"", job: "usage") == 2 }, "refresh runs usage again")

    // Pause for 1 h, then Resume from the header.
    control(app, "popover.footer.pause").click()
    let paused = control(app, "popover.header.paused")
    XCTAssertTrue(paused.waitForExistence(timeout: 5), "the header shows the pause")
    XCTAssertTrue(text(paused).hasPrefix("Paused \u{00B7} resumes "), text(paused))
    XCTAssertNotNil(text(paused).range(of: #"resumes \d\d:\d\d$"#, options: .regularExpression), text(paused))
    XCTAssertTrue(control(app, "popover.footer.resume").exists, "the footer offers Resume")
    XCTAssertFalse(control(app, "popover.header.refresh").exists, "no refresh button while paused")
    control(app, "popover.header.resume").click()
    XCTAssertTrue(control(app, "popover.header.freshness").waitForExistence(timeout: 5), "Resume restores the header")
    XCTAssertTrue(control(app, "popover.footer.pause").exists, "the footer offers the pause again")
    XCTAssertTrue(settingChanged("tb.poll.pausedUntil", to: "0"), "Resume writes tb.poll.pausedUntil = 0")

    // Settings → Sources: one step up, then back.
    control(app, "popover.footer.settings").click()
    try selectTab(app, "Sources")
    let usage = app.steppers["settings.sources.usageOpenAI"].firstMatch
    XCTAssertTrue(usage.waitForExistence(timeout: 5), "the OpenAI usage interval stepper exists")
    usage.incrementArrows.firstMatch.click()
    XCTAssertTrue(waitFor { self.settingChanged("tb.poll.usageIntervalOpenAIS", to: "360") }, "+1 min")
    usage.decrementArrows.firstMatch.click()
    XCTAssertTrue(waitFor { self.settingChanged("tb.poll.usageIntervalOpenAIS", to: "300") }, "back to 5 min")

    // Settings → Accounts → Paused: a refresh is skipped with reason paused; unpause again.
    try selectTab(app, "Accounts")
    let toggle = control(app, "settings.accounts.paused")
    XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the Paused toggle exists")
    toggle.click()
    XCTAssertTrue(openPopover(app, until: control(app, "popover.header.refresh")), "the popover opens")
    control(app, "popover.header.refresh").click()
    XCTAssertTrue(waitFor { self.count("\"reason\":\"paused\"", job: "usage") >= 1 },
                  "the scheduler skips the paused account (sched.skip reason=paused)")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(openSettingsAgain(app), "Settings comes back to the front")
    try selectTab(app, "Accounts")
    control(app, "settings.accounts.paused").click()
    try selectTab(app, "General")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    let failures = try logLines().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
    XCTAssertFalse(try logLines().joined().contains(fakeKey), "the key never reaches the log")
  }

  // MARK: - Steps

  @MainActor
  private func onboard(_ app: XCUIApplication) throws {
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    control(app, "onboarding.provider.openai").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "step 2 shows the key field")
    field.click()
    field.typeText(fakeKey)
    control(app, "onboarding.test").click()
    XCTAssertTrue(control(app, "onboarding.done").waitForExistence(timeout: 15), "the probe passes in fixture mode")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 5), "Done closes onboarding")
  }

  @MainActor
  private func openSettingsAgain(_ app: XCUIApplication) -> Bool {
    let settings = control(app, "popover.footer.settings")
    guard openPopover(app, until: settings) else { return false }
    settings.click()
    return control(app, "settings.root").waitForExistence(timeout: 5)
  }

  @MainActor
  private func selectTab(_ app: XCUIApplication, _ name: String) throws {
    let tab = app.toolbars.buttons[name].exists ? app.toolbars.buttons[name] : app.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name) exists")
    tab.click()
  }

  // MARK: - Helpers

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func waitFor(timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }

  /// Log records containing `fragment` for `job`, from the app's log in the test root (PM-2.2-2).
  private func count(_ fragment: String, job: String) -> Int {
    let lines: [String]
    do {
      lines = try logLines()
    } catch {
      XCTFail("log unreadable: \(error)")
      return 0
    }
    return lines.filter { $0.contains(fragment) && $0.contains("\"job\":\"\(job)\"") }.count
  }

  /// The last `app.settings_changed` for `key` has `new` = `value`.
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
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }
}
