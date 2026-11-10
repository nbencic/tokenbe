import SQLite3
import XCTest

/// 14 § Stage 3.5 Tests, `OnboardingUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014):
/// - the happy path creates 1 account, its 4 `poll_state` rows and the discovered `provider_key` rows (14 Verify:
///   `select count(*) from poll_state` == 4, in the test root's database, never the owner's; Q-025);
/// - a missing key shows `Key missing · Fix…`, which opens Settings → Accounts;
/// - `Remove account…` deletes the key and the rows;
/// - a wrong prefix shows 08's message; a 401 shows 02's message and writes nothing.
/// Keys live in the app's test key file inside the root, never in a keychain (PM-3.2-1, Q-030). Settings are not
/// reset, so 1.2's range check survives (PM-3.4-8).
final class OnboardingUITests: XCTestCase {
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
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Ux5", count: 14)
  private var databasePath: String { root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite").path }
  private var keyFile: URL { root.appendingPathComponent("test-keychain.json") }

  @MainActor
  func testHappyPathMissingKeyAndRemove() throws {
    // Launch 1: no account and onboarding not done → onboarding opens by itself (09 `tb.ui.onboardingDone`).
    let app = makeApp(root: root, onboardingDone: false, fixtures: true)
    app.launch()
    try onboard(app)
    try assertDatabaseAfterOnboarding()

    // The card in its pre-data state. SwiftUI folds the card container into the popover group; its rows carry
    // the identifiers.
    XCTAssertTrue(openPopover(app, until: control(app, "popover.card.openai.label")), "the popover shows the card")
    XCTAssertEqual(text(control(app, "popover.card.openai.label")), "OpenAI")
    XCTAssertEqual(text(control(app, "popover.card.openai.pinned")), "No data yet")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    // Launch 2 without the key: startup step 3 marks the account; Fix… opens Accounts; Remove account… cleans up.
    try FileManager.default.removeItem(at: keyFile)
    let again = makeApp(root: root, fixtures: true)
    again.launch()
    try fixAndRemove(again)
    selectGeneral(again)
    XCTAssertTrue(quitThroughPopover(again), "the app quits")
    try assertLog()
  }

  /// Steps 1–3 with the fixture key, the anchor, and `Done`.
  @MainActor
  private func onboard(_ app: XCUIApplication) throws {
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    // Fresh queries for each use: the tiles redraw once the account list arrives at launch.
    let caption = control(app, "onboarding.provider.openai").label
    XCTAssertTrue(caption.contains("Admin key required"), "08's caption: \(caption)")
    control(app, "onboarding.provider.openai").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "step 2 shows the key field")
    field.click()
    field.typeText(fakeKey)
    control(app, "onboarding.test").click()
    // Step 3: what the probe found (fixtures: OpenAI is anchored, 2 keys, USD).
    XCTAssertTrue(control(app, "onboarding.done").waitForExistence(timeout: 15), "the probe passes in fixture mode")
    XCTAssertEqual(text(control(app, "onboarding.result.mode")), "anchored")
    XCTAssertEqual(text(control(app, "onboarding.result.keyCount")), "2")
    XCTAssertEqual(text(control(app, "onboarding.result.currency")), "USD")
    let amount = control(app, "onboarding.anchorAmount")
    amount.click()
    amount.typeText("200")
    control(app, "onboarding.setAnchor").click()
    XCTAssertTrue(control(app, "onboarding.anchorSaved").waitForExistence(timeout: 5), "the anchor is saved")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 5), "Done closes onboarding")
  }

  /// 1 account, 4 poll_state rows (14 Verify), 2 provider keys, 1 anchor; Done's first polls succeed.
  private func assertDatabaseAfterOnboarding() throws {
    XCTAssertEqual(try count("SELECT count(*) FROM account"), 1)
    XCTAssertEqual(try count("SELECT count(*) FROM poll_state"), 4, "14 Verify: 4 poll_state rows")
    XCTAssertEqual(try count("SELECT count(*) FROM provider_key"), 2)
    XCTAssertEqual(try count("SELECT count(*) FROM ledger_event WHERE kind = 'anchor' AND amount_cents = 20000"), 1)
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM poll_state WHERE last_success_at IS NOT NULL") == 2 },
                  "Done runs the keys and usage polls")
    XCTAssertTrue(try keyFileRefs().contains("openai"), "the key is stored under the provider's ref")
  }

  @MainActor
  private func fixAndRemove(_ app: XCUIApplication) throws {
    let fix = control(app, "popover.card.openai.fixKey")
    XCTAssertTrue(openPopover(app, until: fix), "Key missing · Fix… replaces the pinned metric")
    XCTAssertEqual(fix.title.isEmpty ? fix.label : fix.title, "Key missing \u{00B7} Fix\u{2026}")
    fix.click()
    XCTAssertTrue(control(app, "settings.accounts.keyStatus").waitForExistence(timeout: 10),
                  "Fix… opens Settings → Accounts")
    XCTAssertEqual(text(control(app, "settings.accounts.keyStatus")), "Key missing")
    XCTAssertTrue(control(app, "settings.accounts.key.key_fixture_a1b2").exists, "Keys & apps lists the keys")
    control(app, "settings.accounts.remove").click()
    let confirm = app.buttons["Remove"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the destructive confirmation appears")
    confirm.click()
    XCTAssertTrue(waitFor { self.countOrNone("SELECT count(*) FROM account") == 0 }, "the account is gone")
    XCTAssertEqual(try count("SELECT count(*) FROM poll_state"), 0, "poll_state cascades")
    XCTAssertEqual(try count("SELECT count(*) FROM provider_key"), 0, "provider_key cascades")
    XCTAssertFalse(try keyFileRefs().contains("openai"), "no key left for the provider")
  }

  private func assertLog() throws {
    let log = try logLines()
    for evt in ["keychain.missing", "ledger.anchor_set"] {
      XCTAssertTrue(log.contains { $0.contains("\"evt\":\"\(evt)\"") }, "\(evt) is logged")
    }
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"poll.ok\"") && $0.contains("\"job\":\"usage\"") })
    XCTAssertTrue(log.contains { $0.contains("\"evt\":\"app.settings_changed\"") &&
                    $0.contains("\"key\":\"tb.ui.onboardingDone\"") }, "onboarding is marked done")
    XCTAssertFalse(log.joined().contains(fakeKey), "the key never reaches the log")
    let failures = log.filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
      .filter { !$0.contains("\"evt\":\"keychain.missing\"") }
    XCTAssertEqual(failures, [], "no error or fault records besides the deliberate keychain.missing")
  }

  @MainActor
  func testWrongPrefixAndAdminKeyMessage() throws {
    // A project key: 08's inline message, and the probe cannot start.
    let app = makeApp(root: root, onboardingDone: false, fixtures: true, fixtureCases: "openai/projects=401")
    app.launch()
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    control(app, "onboarding.provider.openai").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeText("sk-" + "proj-" + String(repeating: "Ux5", count: 14))
    XCTAssertEqual(text(control(app, "onboarding.prefixMessage")),
                   "This looks like a project key. TokenBe needs an Admin key (sk-admin-\u{2026}).")
    XCTAssertFalse(control(app, "onboarding.test").isEnabled, "a wrong prefix cannot be tested")

    // An admin-shaped key that the provider refuses (fixture 401): 02's message, nothing stored.
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(fakeKey)
    XCTAssertFalse(control(app, "onboarding.prefixMessage").exists)
    control(app, "onboarding.test").click()
    let message = control(app, "onboarding.probeMessage")
    XCTAssertTrue(message.waitForExistence(timeout: 15), "the probe's message appears")
    XCTAssertEqual(text(message), "This is not an Admin key. Create one at platform.openai.com \u{2192} Settings "
                   + "\u{2192} Organization \u{2192} Admin keys (Organization Owner only).")
    XCTAssertEqual(try count("SELECT count(*) FROM account"), 0, "no account after a failed probe")
    XCTAssertFalse(FileManager.default.fileExists(atPath: keyFile.path), "no key stored after a failed probe")
    control(app, "onboarding.cancel").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 5), "Cancel closes onboarding")

    // The Empty state's Add account… opens onboarding again.
    let add = control(app, "popover.empty.addAccount")
    XCTAssertTrue(openPopover(app, until: add), "the Empty state offers Add account…")
    add.click()
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 10), "Add account… opens onboarding")
    control(app, "onboarding.cancel").click()
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  // MARK: - Helpers

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  private func selectGeneral(_ app: XCUIApplication) {
    let general = app.toolbars.buttons["General"].exists ? app.toolbars.buttons["General"] : app.buttons["General"]
    if general.exists { general.click() }
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

  private func keyFileRefs() throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: keyFile.path) else { return [] }
    let items = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: keyFile))
    return Set(items.keys)
  }

  private func logLines() throws -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }
}
