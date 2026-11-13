import SQLite3
import XCTest

/// 14 § Stage 5.1 Tests, `PriceBookUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014), so no
/// request reaches the feed. First launch installs the bundled snapshot (`price.feed_ok source=bundled`, one
/// `price_snapshot` row: 14 Verify). Settings → Sources → Price book: `+` adds an override (one `price_override` row,
/// shown in the table), an incomplete one is refused, `Reset to feed` removes it. Settings are not reset
/// (PM-4.2-5); the test leaves General selected and changes no shared setting.
final class PriceBookUITests: XCTestCase {
  private var root: URL!
  private var databasePath: String { root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite").path }
  private let model = "tokenbe-ui-model"

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
  func testBundledSnapshotOverrideAndReset() throws {
    let app = makeApp(root: root, fixtures: true)
    app.launch()

    // Startup step 4 (14 Verify): the bundled snapshot, logged and stored once.
    XCTAssertTrue(waitFor { self.bundledFeedOK() }, "first launch logs price.feed_ok source=bundled")
    XCTAssertEqual(try count("SELECT count(*) FROM price_snapshot"), 1)
    XCTAssertEqual(try count("SELECT count(*) FROM price_snapshot WHERE is_current = 1 AND version LIKE 'bundled-%'"), 1)

    let settings = control(app, "popover.footer.settings")
    XCTAssertTrue(openPopover(app, until: settings), "the popover opens")
    settings.click()
    try selectTab(app, "Sources")
    let caption = control(app, "settings.sources.priceSnapshot")
    XCTAssertTrue(caption.waitForExistence(timeout: 5), "the snapshot line exists")
    let line = text(caption)
    XCTAssertTrue(line.hasPrefix("Snapshot bundled-"), line)
    XCTAssertTrue(line.contains(" models · 0 overrides · refreshed "), line)
    XCTAssertTrue(control(app, "settings.sources.priceFeed").exists, "the feed toggle exists")
    XCTAssertTrue(control(app, "settings.sources.priceRefresh").exists, "Refresh now exists")
    XCTAssertFalse(control(app, "settings.sources.priceReset").isEnabled, "Reset to feed waits for an override")

    // An override without an output rate is refused, and nothing is stored.
    control(app, "settings.sources.priceAdd").click()
    try type(app, "settings.price.model", model)
    try type(app, "settings.price.input", "2")
    control(app, "settings.price.save").click()
    XCTAssertTrue(control(app, "settings.price.invalid").waitForExistence(timeout: 5), "an incomplete override is refused")
    XCTAssertEqual(try count("SELECT count(*) FROM price_override"), 0)
    try type(app, "settings.price.output", "8")
    control(app, "settings.price.save").click()
    XCTAssertTrue(control(app, "settings.price.save").waitForNonExistence(timeout: 5), "Save closes the sheet")

    // `+` → one `price_override` row with feed keys, in the table.
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM price_override WHERE model = '\(self.model)' AND json LIKE '%\"input_cost_per_token\":2000000e-12%'") == 1 },
                  "the override is stored with feed keys")
    XCTAssertTrue(control(app, "settings.sources.priceRow.\(model)").waitForExistence(timeout: 5), "the table shows it")
    XCTAssertTrue(waitFor { self.text(caption).contains(" 1 override ") }, text(caption))

    // `Reset to feed` (confirmed) removes every override.
    control(app, "settings.sources.priceReset").click()
    let confirm = confirmButton(app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Reset to feed asks first")
    confirm.click()
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM price_override") == 0 }, "Reset to feed removes it")
    XCTAssertTrue(control(app, "settings.sources.priceRow.\(model)").waitForNonExistence(timeout: 5))

    try selectTab(app, "General")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    let actions = try logRecords().filter { $0["evt"] as? String == "price.override_set" }
      .compactMap { ($0["ctx"] as? [String: Any])?["action"] as? String }
    XCTAssertEqual(actions, ["set", "reset"])
    let failures = try logLines().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
  }

  // MARK: - Helpers

  private func bundledFeedOK() -> Bool {
    do {
      return try logRecords().contains {
        $0["evt"] as? String == "price.feed_ok" && ($0["ctx"] as? [String: Any])?["source"] as? String == "bundled"
      }
    } catch {
      return false
    }
  }

  /// The confirmation's destructive button: by identifier, else by its title inside the dialog.
  @MainActor
  private func confirmButton(_ app: XCUIApplication) -> XCUIElement {
    let byID = control(app, "settings.sources.priceResetConfirm")
    if byID.waitForExistence(timeout: 2) { return byID }
    let inSheet = app.sheets.buttons["Reset to feed"]
    if inSheet.waitForExistence(timeout: 2) { return inSheet }
    return app.dialogs.buttons["Reset to feed"]
  }

  @MainActor
  private func type(_ app: XCUIApplication, _ identifier: String, _ value: String) throws {
    let field = control(app, identifier)
    XCTAssertTrue(field.waitForExistence(timeout: 5), "\(identifier) exists")
    field.click()
    field.typeText(value)
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

  private func logRecords() throws -> [[String: Any]] {
    try logLines().compactMap { line in
      try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
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
