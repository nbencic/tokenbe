import SQLite3
import XCTest

/// 14 § Stage 5.5 Tests, `GlyphMetricUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT`: an anchored
/// account driven `critical` (two heavy closed days written into the test root's database) notches the menu-bar
/// glyph (`glyph.notched`), and 09 `tb.menubar.metric` shows the text beside it: `minRunway` as `Nh`, `todaySpend` as
/// `$N`. The metric is passed as a launch argument, so the shared UI-test settings suite is not changed (PM-4.2-5).
final class GlyphMetricUITests: XCTestCase {
  private var root: URL!
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Gm6", count: 14)
  private let emptyUsage = "openai/usage_completions=empty"
  private var databasePath: String { root.appendingPathComponent("Application Support/TokenBe/tokenbe.sqlite").path }

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
  func testNotchAndMetric() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true, fixtureCases: emptyUsage)
    app.launch()
    try onboard(app)
    XCTAssertTrue(app.statusItems["glyph.solid"].waitForExistence(timeout: 15), "unknown band: the ring is solid")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    try seedHeavyDays()
    let critical = makeApp(root: root, fixtures: true, fixtureCases: emptyUsage)
    critical.launchArguments += ["-tb.menubar.metric", "minRunway"]
    critical.launch()
    XCTAssertTrue(critical.statusItems["glyph.notched"].waitForExistence(timeout: 20), "critical: the ring is notched")
    let runway = metricText(critical)
    XCTAssertNotNil(runway.range(of: #"^\d+h$"#, options: .regularExpression), "minRunway reads `Nh`: `\(runway)`")
    XCTAssertTrue(quitThroughPopover(critical), "the app quits")

    let spend = makeApp(root: root, fixtures: true, fixtureCases: emptyUsage)
    spend.launchArguments += ["-tb.menubar.metric", "todaySpend"]
    spend.launch()
    XCTAssertTrue(spend.statusItems["glyph.notched"].waitForExistence(timeout: 20), "step 8: notched from launch")
    XCTAssertTrue(metricText(spend).hasPrefix("$"), "todaySpend reads `$N`: \(metricText(spend))")
    XCTAssertTrue(quitThroughPopover(spend), "the app quits")
  }

  /// The metric beside the glyph, as the status item reads it out (`TokenBe, 30h`; Q-044): the item's title carries
  /// the glyph's accessibility label. Waits for the first evaluation to put it there.
  @MainActor
  private func metricText(_ app: XCUIApplication) -> String {
    let item = app.statusItems.firstMatch
    func spoken() -> String { item.title.isEmpty ? item.label : item.title }
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline, !spoken().contains(", ") {
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return spoken().components(separatedBy: ", ").dropFirst().joined(separator: ", ")
  }

  @MainActor
  private func onboard(_ app: XCUIApplication) throws {
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
    amount.typeText("100")
    control(app, "onboarding.setAnchor").click()
    XCTAssertTrue(control(app, "onboarding.anchorSaved").waitForExistence(timeout: 5), "the anchor is saved")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 5), "Done closes onboarding")
  }

  /// $300 on each of the two UTC days before today: about 28 h of runway for the $100 anchor (critical).
  private func seedHeavyDays() throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(databasePath)"])
    }
    defer { sqlite3_close(db) }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let midnight = calendar.startOfDay(for: Date())
    for back in 1...2 {
      let start = formatter.string(from: midnight.addingTimeInterval(TimeInterval(-86_400 * back + 3_600)))
      let sql = """
        INSERT INTO usage_bucket (account_id, bucket_start, bucket_width, model, provider_key_id, service_tier, source,
          input_uncached, output, requests, est_cost_cents, unpriced, provisional, fetched_at)
        SELECT id, '\(start)', '1h', 'gpt-4o', '', '', 'provider', 1000, 100, 1, 30000, 0, 0, '\(start)' FROM account
        """
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
      }
    }
  }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }
}
