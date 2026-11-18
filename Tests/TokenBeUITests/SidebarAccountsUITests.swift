import SQLite3
import XCTest

// ui-covers: Sources/TokenBeApp/Dashboard/SidebarView.swift Sources/TokenBeApp/Dashboard/DashboardView.swift
// ui-covers: Sources/TokenBeApp/SettingsUI/AccountsTab.swift Sources/TokenBeApp/Onboarding/
/// 14 § Stage 10.0.1 Tests, `SidebarAccountsUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014):
/// - onboard OpenAI;
/// - the sidebar's `+` opens Add account with OpenAI shown `Added`;
/// - add xAI (fixture), and its row appears;
/// - `−` is disabled on Overview;
/// - select xAI, `−` → confirm, the row is gone and Overview is selected (Q-060).
/// Keys live in the app's test key file inside the root, never in a keychain (PM-3.2-1, Q-030).
final class SidebarAccountsUITests: XCTestCase {
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
  private let openAIKey = "sk-" + "admin-" + String(repeating: "Sb7", count: 14)
  private let xaiKey = "xai-" + String(repeating: "Sb7", count: 16)
  private var databasePath: String { root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite").path }

  @MainActor
  func testAddAndRemoveFromSidebar() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true)
    app.launch()
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    onboard(app, provider: "openai", key: openAIKey)
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM account") == 1 }, "the OpenAI account exists")

    // The Dashboard, on Overview: `−` has no account to remove.
    XCTAssertTrue(openPopover(app, until: app.buttons["popover.footer.openDashboard"]), "popover open")
    app.buttons["popover.footer.openDashboard"].click()
    XCTAssertTrue(dashboard(app).waitForExistence(timeout: 10), "Open dashboard opens it")
    app.activate()
    let add = control(app, "dashboard.sidebar.add")
    let remove = control(app, "dashboard.sidebar.remove")
    XCTAssertTrue(add.waitForExistence(timeout: 5), "the sidebar's foot has +")
    XCTAssertTrue(control(app, "dashboard.sidebar.account.openai").waitForExistence(timeout: 10))
    control(app, "dashboard.sidebar.overview").click()
    XCTAssertTrue(add.isEnabled, "+ is on while a provider has no account")
    XCTAssertFalse(remove.isEnabled, "− is off on Overview")
    control(app, "dashboard.sidebar.apps").click()
    XCTAssertFalse(remove.isEnabled, "− is off on Apps")

    // `+` opens Add account; OpenAI reads `Added` and cannot be picked again.
    add.click()
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 10), "+ opens Add account")
    let openAITile = control(app, "onboarding.provider.openai")
    XCTAssertTrue(openAITile.waitForExistence(timeout: 5))
    XCTAssertTrue(openAITile.label.contains("Added"), "OpenAI is shown Added: \(openAITile.label)")
    XCTAssertFalse(openAITile.isEnabled, "an added provider cannot be picked")
    onboard(app, provider: "xai", key: xaiKey)
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM account WHERE provider = 'xai'") == 1 },
                  "the xAI account exists")

    // xAI's row appears; selecting it turns `−` on; the shared confirm removes it and Overview is selected.
    app.activate()
    let xaiRow = control(app, "dashboard.sidebar.account.xai")
    XCTAssertTrue(xaiRow.waitForExistence(timeout: 10), "the xAI row appears in the sidebar")
    xaiRow.click()
    XCTAssertTrue(waitFor(timeout: 5) { remove.isEnabled }, "− is on for a selected account")
    remove.click()
    let confirm = app.buttons["Remove"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Remove account…'s destructive confirm appears")
    confirm.click()
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM account WHERE provider = 'xai'") == 0 },
                  "the xAI account is gone")
    XCTAssertEqual(try count("SELECT count(*) FROM account"), 1, "OpenAI stays")
    XCTAssertEqual(try count("SELECT count(*) FROM poll_state WHERE account_id NOT IN (SELECT id FROM account)"), 0,
                   "poll_state cascades")
    XCTAssertTrue(xaiRow.waitForNonExistence(timeout: 10), "the xAI row is gone")
    XCTAssertTrue(control(app, "dashboard.spendByDay.title").waitForExistence(timeout: 5), "the detail is Overview")
    XCTAssertTrue(isSelected(app, "dashboard.sidebar.overview"), "Overview is selected")
    XCTAssertFalse(remove.isEnabled, "− is off again on Overview")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
    try assertLog()
  }

  /// Steps 1–3 for `provider` with the fixture key, then `Done` (no anchor).
  @MainActor
  private func onboard(_ app: XCUIApplication, provider: String, key: String) {
    let tile = control(app, "onboarding.provider.\(provider)")
    XCTAssertTrue(tile.waitForExistence(timeout: 5), "Debug builds offer \(provider)")
    control(app, "onboarding.provider.\(provider)").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "step 2 shows the key field")
    field.click()
    field.typeText(key)
    control(app, "onboarding.test").click()
    XCTAssertTrue(control(app, "onboarding.done").waitForExistence(timeout: 15), "the probe passes in fixture mode")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 10), "Done closes onboarding")
  }

  /// No key reaches the log, and the run logs no error or fault (D10).
  private func assertLog() throws {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    let log = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
    XCTAssertFalse(log.joined().contains(openAIKey), "the OpenAI key never reaches the log")
    XCTAssertFalse(log.joined().contains(xaiKey), "the xAI key never reaches the log")
    let failures = log.filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
  }

  // MARK: - Helpers

  @MainActor
  private func dashboard(_ app: XCUIApplication) -> XCUIElement { app.windows["dashboard"] }

  @MainActor
  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// A sidebar row is selected when its outline row is; the label itself carries no selection on macOS.
  @MainActor
  private func isSelected(_ app: XCUIApplication, _ identifier: String) -> Bool {
    if control(app, identifier).isSelected { return true }
    let row = dashboard(app).outlineRows.containing(.any, identifier: identifier).firstMatch
    return row.exists && row.isSelected
  }

  @MainActor
  private func waitFor(timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }

  /// One integer from the test root's database, opened read-only.
  private func count(_ sql: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(databasePath)"])
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: sql])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  /// `count`, or -1 while the database is busy or not there yet (polled by `waitFor`).
  private func countOrNone(_ sql: String) -> Int {
    do {
      return try count(sql)
    } catch {
      return -1
    }
  }
}
