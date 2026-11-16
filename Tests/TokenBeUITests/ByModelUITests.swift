import SQLite3
import XCTest

// ui-covers: Sources/TokenBeApp/Dashboard/ByModelTable.swift Sources/TokenBeApp/Dashboard/AccountDetailView.swift
// ui-covers: Sources/TokenBeCore/Ledger/Drift.swift Sources/TokenBeCore/Pricing/PriceBook.swift
// ui-covers: Sources/TokenBeCore/Pricing/CostEstimator.swift
/// 14 § Stage 8.1 Tests, E2E-8 (01 A6), in fixture mode under a throwaway `TOKENBE_TEST_ROOT` (Q-014). The first
/// launch onboards an OpenAI key with the `unpriced` usage fixture, whose `made-up-model-1` is in no price book: the
/// poll stores it with `est_cost_cents NULL` and logs `price.unpriced` once for the day. The test then moves those
/// rows to today and adds yesterday's `gpt-4o-mini` usage (≈ $2.00) beside a $1.00 line item, so the 7 d range shows
/// both on any date. The account page's By-model table flags `made-up-model-1` as `unpriced` (no drift), the
/// numbers strip shows `Unpriced in range` (never added to spend or runway), and `gpt-4o-mini`'s Drift reads about
/// +100 %, flagged above 09's 10 % threshold. Settings are not changed; the range is passed as `7d` for this run only.
final class ByModelUITests: XCTestCase {
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
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Bm8", count: 14)
  private var databasePath: String { root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite").path }

  @MainActor
  func testUnpricedModelIsFlaggedAndDriftIsFlagged() throws {
    let first = makeApp(root: root, onboardingDone: false, fixtures: true,
                        fixtureCases: "openai/usage_completions=unpriced")
    first.launch()
    try onboard(first)
    XCTAssertTrue(waitFor { self.unpricedWarnings() >= 1 }, "the usage poll priced the fixture")
    XCTAssertTrue(quitThroughPopover(first), "the app quits")
    XCTAssertEqual(unpricedWarnings(), 1, "price.unpriced once per model per UTC day (05, A6)")
    XCTAssertEqual(try query("""
      SELECT count(*) FROM usage_bucket WHERE model = 'made-up-model-1' AND est_cost_cents IS NULL AND unpriced = 1
      """), "1", "the unpriced bucket is stored with est_cost_cents NULL, never 0")
    try seed()

    let app = makeApp(root: root, fixtures: true)
    app.launchArguments += ["-tb.ui.dashboardRange", "7d"]
    app.launch()
    let card = control(app, "popover.card.openai")
    XCTAssertTrue(openPopover(app, until: card), "the popover shows the card")
    card.click()
    let table = control(app, "dashboard.account.byModel")
    XCTAssertTrue(table.waitForExistence(timeout: 15), "the account page shows the By-model table")

    let unpriced = control(app, "dashboard.account.byModel.est.made-up-model-1")
    XCTAssertTrue(unpriced.waitForExistence(timeout: 10), "the unpriced model has a row")
    XCTAssertEqual(text(unpriced), "unpriced", "flagged in Est. cost, never $0")
    XCTAssertEqual(text(control(app, "dashboard.account.byModel.drift.made-up-model-1")), "\u{2014}",
                   "an unpriced model has no drift")
    XCTAssertTrue(control(app, "dashboard.account.numbers.unpriced").exists,
                  "Unpriced in range shows; the tokens are not in spend or runway")

    let drift = control(app, "dashboard.account.byModel.drift.gpt-4o-mini")
    XCTAssertTrue(drift.waitForExistence(timeout: 10), "gpt-4o-mini has a drift cell")
    // About +100 %: the fixture's own Nov 10 line item (1 ¢) can fall in the range too, so only the sign is fixed.
    XCTAssertTrue(drift.label.hasPrefix("Drift +"), "est ≈ $2.00 against $1.00: `\(drift.label)`")
    XCTAssertTrue(drift.label.hasSuffix("above the 10 % threshold"), "the flag is in words: `\(drift.label)`")
    let provider = text(control(app, "dashboard.account.byModel.provider.gpt-4o-mini"))
    XCTAssertTrue(provider.hasPrefix("$"), "the provider cost shows without ≈: `\(provider)`")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

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

  /// The unpriced rows move to today, 01:00 UTC; yesterday gets `gpt-4o-mini` usage of 200 ¢ and a 100 ¢ line item.
  private func seed() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let midnight = calendar.startOfDay(for: Date())
    let today = formatter.string(from: midnight.addingTimeInterval(3_600))
    let yesterday = formatter.string(from: midnight.addingTimeInterval(-14 * 3_600))
    let yesterdayDay = String(yesterday.prefix(10))
    try execute("""
      UPDATE usage_bucket SET bucket_start = '\(today)' WHERE model = 'made-up-model-1';
      INSERT INTO usage_bucket (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source,
        input_uncached, output, requests, est_cost_cents, unpriced, provisional, fetched_at)
      SELECT id, '\(yesterday)', '1h', 'gpt-4o-mini', 'key_fixture_c3d4', 'default', 'provider', 2000, 200, 5, 200, 0,
        0, '\(today)' FROM account;
      INSERT INTO cost_bucket (account_id, day, group_kind, group_key, amount_cents, currency, provisional, fetched_at)
      SELECT id, '\(yesterdayDay)', 'line_item', 'gpt-4o-mini, input', 100, 'USD', 0, '\(today)' FROM account;
      """)
  }

  // MARK: - Helpers

  private func unpricedWarnings() -> Int {
    logLinesOrNone().filter { $0.contains("\"evt\":\"price.unpriced\"") && $0.contains("made-up-model-1") }.count
  }

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
