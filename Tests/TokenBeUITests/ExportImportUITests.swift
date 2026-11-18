import SQLite3
import XCTest

// ui-covers: Sources/TokenBeApp/SettingsUI/DataTransferRows.swift Sources/TokenBeCore/Export/
// ui-covers: Sources/TokenBeCore/Store/Repository+Export.swift
/// E2E-7 (11; 14 § Stage 9.2), in fixture mode under a throwaway `TOKENBE_TEST_ROOT`: onboard OpenAI with a $100
/// anchor, `Export data (JSON)…`, quit, delete the database, relaunch, `Import…` → every exported table has the
/// file's row count and the card reads the same Remaining; the file holds no key; a second import is refused with
/// O-17's sheet. `TOKENBE_TEST_EXPORT_DIR` stands in for the panels, so nothing is written outside the test root
/// (Q-056). The suite keeps its helpers to itself: `UITestSupport` is shared (Q-047).
final class ExportImportUITests: XCTestCase {
  private var root: URL!
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Ex7", count: 14)
  private var exportDirectory: URL { root.appendingPathComponent("exports", isDirectory: true) }
  private var supportFolder: URL { root.appendingPathComponent("Application Support/TokenBe", isDirectory: true) }

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = makeTestRoot()
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let root, FileManager.default.fileExists(atPath: root.path) {
      try FileManager.default.removeItem(at: root)
    }
  }

  @MainActor
  func testExportWipeImport() throws {
    let app = launch(onboardingDone: false)
    try onboard(app, anchor: "100")
    let remaining = try settledRemaining(app)
    app.typeKey(.escape, modifierFlags: [])

    try openAdvanced(app)
    control(app, "settings.advanced.exportJSON").click()
    XCTAssertEqual(reportTitle(app), "Export saved")
    dismissReport(app)
    let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)
      .first { $0.pathExtension == "json" }, "the export is in the test folder")
    let exported = try String(contentsOf: file, encoding: .utf8)
    XCTAssertFalse(exported.contains("sk-"), "E2E-7: the export contains no `sk-`")
    XCTAssertFalse(exported.contains(String(fakeKey.suffix(12))), "nor any part of the key beyond its hint")
    leaveOnGeneral(app)
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    // Wipe: the database and its WAL go together; the test key file stays, as the Keychain would.
    for suffix in ["", "-wal", "-shm"] {
      let url = supportFolder.appendingPathComponent("tokenbe.sqlite" + suffix)
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    let again = launch(onboardingDone: true)
    XCTAssertTrue(openPopover(again, until: again.staticTexts["popover.empty.headline"]), "the wiped database is empty")
    again.typeKey(.escape, modifierFlags: [])
    try openAdvanced(again)
    control(again, "settings.advanced.import").click()
    XCTAssertEqual(reportTitle(again), "Import complete")
    dismissReport(again)
    let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
    for (key, table) in [("accounts", "account"), ("provider_keys", "provider_key"), ("apps", "app"),
                         ("app_bindings", "app_binding"), ("usage_buckets", "usage_bucket"),
                         ("cost_buckets", "cost_bucket"), ("balance_snapshots", "balance_snapshot"),
                         ("ledger_events", "ledger_event"), ("price_overrides", "price_override")] {
      XCTAssertEqual(try rowCount(table), (document[key] as? [Any])?.count, "\(table): the file's row count")
    }

    control(again, "settings.advanced.import").click()
    XCTAssertEqual(reportTitle(again), "Import needs an empty database", "O-17: a second import is refused")
    dismissReport(again)
    leaveOnGeneral(again)
    let pinned = control(again, "popover.card.openai.pinned")
    XCTAssertTrue(openPopover(again, until: pinned), "the imported account has its card")
    XCTAssertTrue(waitFor { self.text(pinned) == remaining }, "E2E-7: the same Remaining, `\(text(pinned))` vs `\(remaining)`")
    again.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(again), "the app quits")

    let log = try logLines()
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"db.export\"") && $0.contains("\"kind\":\"json\"") })
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"db.import\"") }, "db.import is logged")
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"db.import_failed\"") && $0.contains("not_empty") })
    let failures = log.filter { ($0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\""))
      && !$0.contains("\"evt\":\"db.import_failed\"") }
    XCTAssertEqual(failures, [], "no error or fault besides the refused import")
    XCTAssertFalse(log.joined().contains(fakeKey), "the key never reaches the log")
  }

  // MARK: - Helpers

  @MainActor
  private func launch(onboardingDone: Bool) -> XCUIApplication {
    let app = makeApp(root: root, onboardingDone: onboardingDone, fixtures: true)
    app.launchEnvironment["TOKENBE_TEST_EXPORT_DIR"] = exportDirectory.path
    app.launch()
    return app
  }

  /// The card's Remaining once the first usage poll has landed (read as VoiceOver hears it, 8.4).
  @MainActor
  private func settledRemaining(_ app: XCUIApplication) throws -> String {
    XCTAssertTrue(waitFor(timeout: 30) { self.logContains("\"evt\":\"poll.ok\"", "\"job\":\"usage\"") },
                  "the first usage poll lands")
    let pinned = control(app, "popover.card.openai.pinned")
    XCTAssertTrue(openPopover(app, until: pinned), "the popover shows the card")
    XCTAssertTrue(waitFor { self.text(pinned).hasPrefix("Remaining, approximately ") }, "the card has a Remaining")
    return text(pinned)
  }

  /// Steps 1–3 with the fixture key and the anchor, then `Done`.
  @MainActor
  private func onboard(_ app: XCUIApplication, anchor: String) throws {
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    control(app, "onboarding.provider.openai").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeText(fakeKey)
    control(app, "onboarding.test").click()
    XCTAssertTrue(control(app, "onboarding.done").waitForExistence(timeout: 15), "the probe passes in fixture mode")
    let amount = control(app, "onboarding.anchorAmount")
    amount.click()
    amount.typeText(anchor)
    control(app, "onboarding.setAnchor").click()
    XCTAssertTrue(control(app, "onboarding.anchorSaved").waitForExistence(timeout: 5), "the anchor is saved")
    control(app, "onboarding.done").click()
  }

  @MainActor
  private func openAdvanced(_ app: XCUIApplication) throws {
    let button = app.buttons["popover.footer.settings"]
    XCTAssertTrue(openPopover(app, until: button), "the popover shows Settings…")
    button.click()
    XCTAssertTrue(control(app, "settings.root").waitForExistence(timeout: 10), "Settings… opens the Settings window")
    let tab = app.toolbars.buttons["Advanced"].exists ? app.toolbars.buttons["Advanced"] : app.buttons["Advanced"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "the Advanced tab exists")
    tab.click()
    XCTAssertTrue(control(app, "settings.advanced.exportJSON").waitForExistence(timeout: 5), "the data rows exist")
  }

  /// The Settings window remembers its tab; other suites expect General (PM-1.3-2).
  @MainActor
  private func leaveOnGeneral(_ app: XCUIApplication) {
    let general = app.toolbars.buttons["General"].exists ? app.toolbars.buttons["General"] : app.buttons["General"]
    general.click()
    app.activate()
  }

  @MainActor
  private func reportTitle(_ app: XCUIApplication) -> String? {
    let title = control(app, "settings.advanced.report.title")
    guard title.waitForExistence(timeout: 15) else { return nil }
    return text(title)
  }

  @MainActor
  private func dismissReport(_ app: XCUIApplication) {
    let done = control(app, "settings.advanced.report.ok")
    XCTAssertTrue(done.waitForExistence(timeout: 5), "the sheet has OK")
    done.click()
    XCTAssertTrue(control(app, "settings.advanced.report.title").waitForNonExistence(timeout: 5), "OK closes the sheet")
  }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Rows of `table` in the test root's database, read-only.
  private func rowCount(_ table: String) throws -> Int {
    var db: OpaquePointer?
    let path = supportFolder.appendingPathComponent("tokenbe.sqlite").path
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(path)"])
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK else {
      throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot count \(table)"])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "sqlite", code: 3, userInfo: [NSLocalizedDescriptionKey: "no count for \(table)"])
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func logContains(_ parts: String...) -> Bool {
    let lines: [String]
    do {
      lines = try logLines()
    } catch {
      XCTFail("log unreadable: \(error)")
      return false
    }
    return lines.contains { line in parts.allSatisfy { line.contains($0) } }
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
