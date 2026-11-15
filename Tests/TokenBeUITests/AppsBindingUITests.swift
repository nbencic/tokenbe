import SQLite3
import XCTest

// ui-covers: Sources/TokenBeApp/Dashboard/ByAppTable.swift Sources/TokenBeApp/Dashboard/AppsThisPeriod.swift
// ui-covers: Sources/TokenBeApp/Dashboard/AppsPage.swift Sources/TokenBeApp/Dashboard/SidebarView.swift
// ui-covers: Sources/TokenBeApp/Dashboard/AccountDetailView.swift Sources/TokenBeApp/SettingsUI/AccountsTab.swift
// ui-covers: Sources/TokenBeApp/SettingsUI/BoundAppPicker.swift Sources/TokenBeApp/Popover/AccountCardView.swift
// ui-covers: Sources/TokenBeCore/Ledger/Attribution.swift Sources/TokenBeCore/Store/Repository+Apps.swift
/// 14 § Stage 7.1 Tests, `AppsBindingUITests` (01 A2), in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014):
/// after onboarding an OpenAI key, today's usage of the two fixture keys is written into the test root's database.
/// The account page's By-app table then lists both keys by their provider names, and its `Total` equals the numbers
/// strip's `Spend in range`. `Name…` on one key and Keys & apps `New app…` on the other create apps (O-16 names) and
/// rename the rows; the popover's row 4 and the Apps page show them. Settings are not reset; the only shared key it
/// writes, `tb.popover.expanded.openai`, it sets back to false (PM-4.2-5).
final class AppsBindingUITests: XCTestCase {
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
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Ap7", count: 14)
  private var databasePath: String { root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite").path }

  @MainActor
  func testBindKeysRenamesRowsAndTotalEqualsProviderTotal() throws {
    let first = makeApp(root: root, onboardingDone: false, fixtures: true)
    first.launch()
    try onboard(first)
    XCTAssertTrue(waitFor { self.logLinesOrNone().contains { $0.contains("\"evt\":\"poll.ok\"") } }, "the account polls")
    XCTAssertTrue(quitThroughPopover(first), "the app quits")
    try seedToday()

    let app = makeApp(root: root, fixtures: true)
    app.launch()
    let card = control(app, "popover.card.openai")
    XCTAssertTrue(openPopover(app, until: card), "the popover shows the card")
    card.click()
    let production = control(app, "dashboard.account.byApp.name.key_fixture_a1b2")
    XCTAssertTrue(production.waitForExistence(timeout: 15), "the By-app table lists the first key")
    XCTAssertEqual(text(production), "Production", "an unbound key shows the provider's key name (01 A2)")
    XCTAssertEqual(text(control(app, "dashboard.account.byApp.name.key_fixture_c3d4")), "Staging")
    let total = text(control(app, "dashboard.account.byApp.total"))
    let inRange = combined(control(app, "dashboard.account.numbers.rangeSpend"))
    XCTAssertFalse(total.isEmpty)
    XCTAssertTrue(inRange.trimmingCharacters(in: .whitespaces).hasSuffix(total), "Total `\(total)` equals the provider total for the range (`\(inRange)`)")

    // `Name…` on the second key: a new app, bound to it.
    control(app, "dashboard.account.byApp.name.key_fixture_c3d4.button").click()
    try createApp(app, named: "Batch jobs")
    XCTAssertTrue(waitFor { self.text(control(app, "dashboard.account.byApp.name.key_fixture_c3d4")) == "Batch jobs" },
                  "the row takes the app's name")
    XCTAssertTrue(control(app, "dashboard.account.byApp.name.key_fixture_c3d4.button").waitForNonExistence(timeout: 5),
                  "a bound key offers no `Name…`")

    try bindInKeysAndApps(app)
    XCTAssertTrue(waitFor { self.text(production) == "Weather collector" }, "the By-app row is renamed")
    XCTAssertTrue(inRange == combined(control(app, "dashboard.account.numbers.rangeSpend"))
                  && total == text(control(app, "dashboard.account.byApp.total")), "binding moves no money")

    // The Apps page lists both apps with their O-16 names.
    // Closing Settings can leave another app's window in front of the Dashboard.
    app.activate()
    control(app, "dashboard.sidebar.apps").click()
    XCTAssertTrue(control(app, "dashboard.apps.weather-collector.displayName").waitForExistence(timeout: 5),
                  "the Apps page lists weather-collector")
    XCTAssertTrue(control(app, "dashboard.apps.batch-jobs.displayName").exists, "and batch-jobs")
    XCTAssertEqual(try query("SELECT group_concat(name, ',') FROM (SELECT name FROM app ORDER BY name)"),
                   "batch-jobs,unassigned,weather-collector")
    XCTAssertEqual(try query("SELECT count(*) FROM app_binding WHERE kind = 'provider_key'"), "2")

    try assertPopoverRow4(app)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    let failures = logLinesOrNone().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
    XCTAssertFalse(logLinesOrNone().joined().contains(fakeKey), "the key never reaches the log")
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

  /// Popover row 4: collapsed, then the top apps by today's spend, then collapsed again.
  @MainActor
  private func assertPopoverRow4(_ app: XCUIApplication) throws {
    let toggle = control(app, "popover.card.openai.appsToggle")
    XCTAssertTrue(openPopover(app, until: toggle), "row 4 shows: the account spent today")
    // 09's default is collapsed; a run that stopped half-way may have left it expanded in the shared suite.
    if toggle.label != "Show apps" { toggle.click() }
    XCTAssertTrue(waitFor { toggle.label == "Show apps" }, "collapsed: `\(toggle.label)`")
    toggle.click()
    XCTAssertTrue(waitFor { toggle.label.hasPrefix("Weather collector ") && toggle.label.contains(" \u{00B7} Batch jobs ") },
                  "row 4 lists the apps by today's spend: `\(toggle.label)`")
    toggle.click()
    XCTAssertTrue(waitFor { toggle.label == "Show apps" }, "and collapses again (tb.popover.expanded.openai = false)")
  }

  /// Settings → Accounts → Keys & apps: `New app…` on the first key; then back to General, and the window closes.
  @MainActor
  private func bindInKeysAndApps(_ app: XCUIApplication) throws {
    app.typeKey(",", modifierFlags: .command)
    try selectTab(app, "Accounts")
    let picker = control(app, "settings.accounts.key.key_fixture_a1b2.app")
    XCTAssertTrue(picker.waitForExistence(timeout: 10), "Keys & apps has a Bound app picker")
    picker.click()
    app.menuItems["New app\u{2026}"].click()
    try createApp(app, named: "Weather collector")
    XCTAssertTrue(waitFor { self.text(control(app, "settings.accounts.key.key_fixture_a1b2.app")) == "Weather collector" },
                  "the picker shows the new app")
    try selectTab(app, "General")
    app.typeKey("w", modifierFlags: .command)
  }

  /// The `App name` prompt: replaces the suggested name and presses `Create`.
  @MainActor
  private func createApp(_ app: XCUIApplication, named name: String) throws {
    let create = app.buttons["Create"]
    XCTAssertTrue(create.waitForExistence(timeout: 5), "the App name prompt opens")
    let field = app.sheets.textFields.firstMatch.exists ? app.sheets.textFields.firstMatch
      : app.dialogs.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5), "the prompt has a name field")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(name)
    create.click()
    XCTAssertTrue(create.waitForNonExistence(timeout: 5), "Create closes the prompt")
  }

  @MainActor
  private func selectTab(_ app: XCUIApplication, _ name: String) throws {
    let tab = app.toolbars.buttons[name].exists ? app.toolbars.buttons[name] : app.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name) exists")
    tab.click()
  }

  /// Today's usage of both fixture keys, an hour after UTC midnight: $1.20 on the first, $0.30 on the second.
  private func seedToday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let start = formatter.string(from: calendar.startOfDay(for: Date()).addingTimeInterval(3_600))
    for (key, cents) in [("key_fixture_a1b2", 120), ("key_fixture_c3d4", 30)] {
      try execute("""
        INSERT INTO usage_bucket (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source,
          input_uncached, output, requests, est_cost_cents, unpriced, provisional, fetched_at)
        SELECT id, '\(start)', '1h', 'gpt-4o-mini', '\(key)', 'default', 'provider', 1000, 100, 3, \(cents), 0, 1,
          '\(start)' FROM account
        """)
    }
  }

  // MARK: - Helpers

  private func open() throws -> OpaquePointer? {
    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(databasePath)"])
    }
    return db
  }

  private func execute(_ sql: String) throws {
    let db = try open()
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
  }

  /// The first column of the first row, as text.
  private func query(_ sql: String) throws -> String? {
    let db = try open()
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NSError(domain: "sqlite", code: 3, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: value)
  }

  private func logLinesOrNone() -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    do {
      return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "ndjson" }
        .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
    } catch {
      return []
    }
  }

  /// A combined element's label and value (the numbers strip's cells).
  private func combined(_ element: XCUIElement) -> String {
    "\(element.label) \(element.value as? String ?? "")"
  }

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
}
