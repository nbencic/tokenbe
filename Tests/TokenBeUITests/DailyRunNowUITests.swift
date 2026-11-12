import XCTest

/// 14 § Stage 4.3 Tests, `DailyRunNowUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014):
/// Settings → Sources → `Run daily tasks now` runs the daily activity out of band (04). The log shows
/// `sched.daily_start … poll.ok cost … db.backup … db.vacuum … sched.daily_end` in that order (14 Verify), with no
/// weekly `integrity_check` on run 1; Advanced shows `Last daily run`; the account page's cost source reads
/// `Cost · ok · HH:mm` (PM-4.2-2). Settings are not reset (PM-4.2-5); the test leaves General selected.
final class DailyRunNowUITests: XCTestCase {
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
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Dy4", count: 14)

  @MainActor
  func testRunDailyTasksNow() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true)
    app.launch()
    try onboard(app)
    XCTAssertTrue(waitFor { self.events().contains("poll.ok usage") }, "the coordinator polls the new account")

    // Settings → Sources → Run daily tasks now.
    let settings = control(app, "popover.footer.settings")
    XCTAssertTrue(openPopover(app, until: settings), "the popover opens")
    settings.click()
    try selectTab(app, "Sources")
    let button = control(app, "settings.sources.runDaily")
    XCTAssertTrue(button.waitForExistence(timeout: 5), "Run daily tasks now exists")
    XCTAssertEqual(button.label, "Run daily tasks now")
    button.click()
    XCTAssertTrue(waitFor(timeout: 30) { self.events().contains("sched.daily_end") }, "the run finishes")
    let daily = events().drop { $0 != "sched.daily_start" }
    let order = daily.filter {
      ["sched.daily_start", "poll.ok cost", "db.backup", "db.vacuum", "sched.daily_end"].contains($0)
    }
    XCTAssertEqual(order, ["sched.daily_start", "poll.ok cost", "db.backup", "db.vacuum", "sched.daily_end"])
    XCTAssertFalse(daily.contains("db.integrity_check"), "the weekly check waits for the 7th run")
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite.bak").path), "backup written")

    // Advanced → Last daily run.
    try selectTab(app, "Advanced")
    let lastRun = control(app, "settings.advanced.lastDailyRun")
    XCTAssertTrue(lastRun.waitForExistence(timeout: 5), "Last daily run exists")
    let shown = "\(lastRun.label) \(lastRun.value as? String ?? "")"
    XCTAssertFalse(shown.contains("never"), shown)
    XCTAssertNotNil(shown.range(of: #"\d"#, options: .regularExpression), "a date and time: \(shown)")
    try selectTab(app, "General")
    app.typeKey("w", modifierFlags: .command)

    // The account page: cost polled by the daily activity (PM-4.2-2).
    let card = control(app, "popover.card.openai")
    XCTAssertTrue(openPopover(app, until: card), "the popover opens")
    card.click()
    let cost = control(app, "dashboard.account.source.cost")
    XCTAssertTrue(cost.waitForExistence(timeout: 10), "the account page opens")
    XCTAssertNotNil(cost.label.range(of: #"^Cost · ok · \d\d:\d\d$"#, options: .regularExpression), cost.label)
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

  /// The log's events in order, `poll.*` with their job (`poll.ok cost`).
  private func events() -> [String] {
    let lines: [String]
    do {
      lines = try logLines()
    } catch {
      XCTFail("log unreadable: \(error)")
      return []
    }
    return lines.compactMap { line -> String? in
      let object: Any
      do {
        object = try JSONSerialization.jsonObject(with: Data(line.utf8))
      } catch {
        XCTFail("unparseable log line: \(error)")
        return nil
      }
      guard let record = object as? [String: Any], let evt = record["evt"] as? String else { return nil }
      if evt.hasPrefix("poll."), let job = record["job"] as? String { return "\(evt) \(job)" }
      return evt
    }
  }

  private func logLines() throws -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }
}
