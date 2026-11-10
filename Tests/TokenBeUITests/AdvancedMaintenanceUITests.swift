import XCTest

/// 14 § Stage 2.2 Tests: Settings → Advanced → `Run integrity check now` reports `ok`; `Back up now` writes
/// `tokenbe.sqlite.bak` and reports its size, time and path. Everything happens under a throwaway
/// `TOKENBE_TEST_ROOT` (Q-014, Q-025), never in the owner's support folder. Settings are not reset, so the values
/// earlier stages' checks read survive (PM-1.2-2); the `tb.db.*` writes are asserted from the app's log (Q-025).
final class AdvancedMaintenanceUITests: XCTestCase {
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

  private var supportFolder: URL { root.appendingPathComponent("Application Support/TokenBe", isDirectory: true) }
  private var backupFile: URL { supportFolder.appendingPathComponent("tokenbe.sqlite.bak") }

  @MainActor
  func testIntegrityCheckAndBackUp() throws {
    let app = makeApp(root: root)
    app.launch()
    try openAdvanced(app)

    let integrity = control(app, "settings.advanced.integrityCheck")
    XCTAssertTrue(integrity.waitForExistence(timeout: 5), "Run integrity check now exists")
    XCTAssertEqual(integrity.title.isEmpty ? integrity.label : integrity.title, "Run integrity check now")
    integrity.click()
    XCTAssertEqual(reportTitle(app), "Integrity check")
    XCTAssertEqual(text(control(app, "settings.advanced.report.line0")), "Result: ok")
    dismissReport(app)

    XCTAssertFalse(FileManager.default.fileExists(atPath: backupFile.path), "no backup before the click")
    let backUp = control(app, "settings.advanced.backUp")
    XCTAssertTrue(backUp.exists, "Back up now exists")
    backUp.click()
    XCTAssertEqual(reportTitle(app), "Backup saved")
    let detail = text(control(app, "settings.advanced.report.line0"))
    XCTAssertTrue(detail.contains(", "), "size and time: \(detail)")
    XCTAssertTrue(text(control(app, "settings.advanced.report.line1")).hasSuffix("TokenBe/tokenbe.sqlite.bak"),
                  "the sheet names the backup path")
    XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path), "Back up now writes tokenbe.sqlite.bak")
    let size = try backupFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    XCTAssertGreaterThan(size, 0, "the backup is not empty")
    dismissReport(app)

    // The Settings window remembers its tab; leave General selected, as other suites expect (PM-1.3-2).
    let general = app.toolbars.buttons["General"].exists ? app.toolbars.buttons["General"] : app.buttons["General"]
    general.click()
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
    let log = try logLines()
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"db.integrity_check\"") && $0.contains("\"result\":\"ok\"") },
                  "db.integrity_check ok is logged")
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"db.backup\"") }, "db.backup is logged")
    // 09 keys: the runner cannot read the app's settings suite (Q-019), and a later suite resets it (Q-020), so the
    // writes are asserted from the app's own `app.settings_changed` records (Q-025).
    for key in ["tb.db.lastIntegrityCheckAt", "tb.db.lastBackupAt"] {
      XCTAssertTrue(log.contains { $0.contains("\"evt\":\"app.settings_changed\"") && $0.contains("\"key\":\"\(key)\"") },
                    "\(key) is written")
    }
    let failures = log.filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "no error or fault records")
  }

  // MARK: - Helpers

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  private func openAdvanced(_ app: XCUIApplication) throws {
    let settingsRoot = control(app, "settings.root")
    let button = app.buttons["popover.footer.settings"]
    XCTAssertTrue(openPopover(app, until: button), "the popover shows Settings…")
    button.click()
    XCTAssertTrue(settingsRoot.waitForExistence(timeout: 10), "Settings… opens the Settings window")
    let tab = app.toolbars.buttons["Advanced"].exists ? app.toolbars.buttons["Advanced"] : app.buttons["Advanced"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "the Advanced tab exists")
    tab.click()
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
    let title = control(app, "settings.advanced.report.title")
    XCTAssertTrue(title.waitForNonExistence(timeout: 5), "OK closes the sheet")
  }

  private func logLines() throws -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }
}
