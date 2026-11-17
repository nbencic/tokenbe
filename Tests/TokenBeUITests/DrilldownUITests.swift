import SQLite3
import XCTest

// ui-covers: Sources/TokenBeApp/Dashboard/AppsThisPeriod.swift Sources/TokenBeApp/Dashboard/OverviewView.swift
// ui-covers: Sources/TokenBeApp/Dashboard/DashboardView.swift Sources/TokenBeApp/Dashboard/AccountDetailView.swift
// ui-covers: Sources/TokenBeApp/Dashboard/ByAppTable.swift Sources/TokenBeApp/Dashboard/DriftChip.swift
// ui-covers: Sources/TokenBeCore/Ledger/Attribution.swift Sources/TokenBeCore/Ledger/Attribution+Harness.swift
// ui-covers: Sources/TokenBeApp/Dashboard/SpendByDayChart.swift Sources/TokenBeApp/Dashboard/CacheTile.swift
// ui-covers: Sources/TokenBeCore/Ledger/SpendChart.swift Sources/TokenBeCore/Ledger/CacheSavings.swift
// ui-covers: Sources/TokenBeApp/Dashboard/ViewExport.swift Sources/TokenBeCore/Export/ViewCSVExporter.swift
/// 14 § Stage 7.3 Tests, `DrilldownUITests`, in fixture mode under a throwaway `TOKENBE_TEST_ROOT`, with a DeepSeek
/// account: harness lines for two apps (yesterday and today, UTC) are dropped into `ingest/`, and yesterday's balance
/// fell by $5, far more than the lines' ≈ $1. The Overview's `Apps this period` row `news-digest` opens the DeepSeek
/// page filtered by the app (chip `App: news-digest`, only its row, `App total` equal to the Overview's amount); the
/// header shows the drift chip; ✕ clears the filter; leaving the account clears it too. The Overview also shows the
/// `Spend by day` chart, whose hover tooltip lists today's account and total, and the cache savings tile with
/// DeepSeek's harness-computed figure (14 § Stage 8.2). On the filtered page, `Export…` suggests the filtered table's
/// file and is cancelled (8.3). Settings are not changed.
final class DrilldownUITests: XCTestCase {
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
  private let fakeKey = "sk-" + String(repeating: "Dr7", count: 11)
  private var support: URL { root.appendingPathComponent("Application Support/TokenBe", isDirectory: true) }
  private var ingest: URL { support.appendingPathComponent("ingest", isDirectory: true) }

  @MainActor
  func testOverviewAppOpensFilteredAccountWithDriftChip() throws {
    let first = makeApp(root: root, onboardingDone: false, fixtures: true)
    first.launch()
    try onboardDeepSeek(first)
    XCTAssertTrue(waitFor { self.balances() > 0 }, "the fixture poll stored today's balance")
    XCTAssertTrue(waitFor { FileManager.default.fileExists(atPath: self.ingest.path) }, "startup step 5 made ingest/")
    XCTAssertTrue(quitThroughPopover(first), "the app quits")
    try seed()

    let app = makeApp(root: root, fixtures: true)
    // The chart's hover finds today's stack in a 7-day range (the range is otherwise whatever an earlier suite left).
    app.launchArguments += ["-tb.ui.dashboardRange", "7d"]
    app.launch()
    let open = app.buttons["popover.footer.openDashboard"]
    XCTAssertTrue(openPopover(app, until: open), "the popover opens")
    open.click()
    let row = control(app, "dashboard.overview.apps.row.news-digest.harness")
    XCTAssertTrue(row.waitForExistence(timeout: 20), "Apps this period lists news-digest")
    try checkChartAndCacheTile(app)
    let overviewLabel = row.label
    row.click()

    let chip = control(app, "dashboard.account.byApp.filter")
    XCTAssertTrue(chip.waitForExistence(timeout: 10), "the account page shows the filter chip")
    XCTAssertEqual(text(chip), "App: news-digest")
    XCTAssertTrue(control(app, "dashboard.account.byApp.name.news-digest").exists, "the app's row")
    XCTAssertFalse(control(app, "dashboard.account.byApp.name.weather-collector").exists, "no other app's row")
    let total = text(control(app, "dashboard.account.byApp.total"))
    XCTAssertTrue(overviewLabel.contains(total), "App total \(total) equals the Overview's amount (\(overviewLabel))")

    let drift = control(app, "dashboard.account.drift")
    XCTAssertTrue(drift.waitForExistence(timeout: 5), "the header shows the drift chip")
    XCTAssertTrue(text(drift).hasPrefix("Harness drift \u{00B7} "), "drift chip: \(text(drift))")
    XCTAssertTrue(text(drift).contains("\u{2212}"), "the lines report less than the balance fell: \(text(drift))")

    try checkExportPanel(app)
    control(app, "dashboard.account.byApp.filter.clear").click()
    XCTAssertTrue(chip.waitForNonExistence(timeout: 5), "✕ clears the filter")
    XCTAssertTrue(control(app, "dashboard.account.byApp.name.weather-collector").waitForExistence(timeout: 5),
                  "every app is back")

    control(app, "dashboard.sidebar.overview").click()
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.click()
    XCTAssertTrue(chip.waitForExistence(timeout: 10), "filtered again")
    control(app, "dashboard.sidebar.apps").click()
    control(app, "dashboard.sidebar.account.deepseek").click()
    XCTAssertTrue(control(app, "dashboard.account.byApp.name.weather-collector").waitForExistence(timeout: 10))
    XCTAssertFalse(chip.exists, "leaving the account cleared the filter")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  // MARK: - Steps

  /// 8.3: the toolbar's `Export…` opens a save panel suggesting the filtered By-app table's file. The panel is
  /// cancelled, never saved: a test must not write into the owner's folders.
  @MainActor
  private func checkExportPanel(_ app: XCUIApplication) throws {
    control(app, "dashboard.toolbar.export").click()
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Export… opens a save panel")
    let name = (sheet.textFields.firstMatch.value as? String) ?? ""
    // The panel hides the `.csv` extension in its name field.
    XCTAssertTrue(name.hasPrefix("TokenBe-DeepSeek-By-app-news-digest-7-d-"),
                  "the file is named after the page, the app filter and the range: \(name)")
    sheet.buttons["Cancel"].click()
    XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Cancel closes the panel without saving")
  }

  /// 8.2: the chart has bars (not `No spend in this range`) and a legend; hovering today's stack shows the tooltip
  /// with its `Total`; the cache tile's headline is 08's sentence (DeepSeek: computed from harness lines).
  @MainActor
  private func checkChartAndCacheTile(_ app: XCUIApplication) throws {
    let chart = control(app, "dashboard.spendByDay.chart")
    XCTAssertTrue(chart.waitForExistence(timeout: 10), "the Overview draws the Spend by day chart")
    XCTAssertFalse(control(app, "dashboard.spendByDay.empty").exists, "not the empty state")
    XCTAssertFalse(control(app, "dashboard.spendByDay.nonUSD").exists, "a USD account only")
    // Today is the last of 7 day bands (about 0.81–0.95 of the width); the y axis labels take the trailing edge.
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.6)).hover()
    // The tooltip's text is drawn, not exposed; its rule carries the same total (`Total, Nov 17, ≈ $0.64`).
    let rule = chart.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Total, '")).firstMatch
    XCTAssertTrue(rule.waitForExistence(timeout: 5), "hovering today's stack shows the tooltip")
    XCTAssertTrue(rule.label.contains("$"), "the tooltip's total: \(rule.label)")
    let headline = control(app, "dashboard.cacheSavings.headline")
    XCTAssertTrue(headline.waitForExistence(timeout: 5), "the Overview shows the cache savings tile")
    XCTAssertTrue(text(headline).hasPrefix("Saved $") && text(headline).hasSuffix(" via cache (net of writes)"),
                  "08's sentence: \(text(headline))")
    let deepseek = control(app, "dashboard.cacheSavings.value.deepseek")
    XCTAssertTrue(deepseek.exists && text(deepseek).contains("$"),
                  "DeepSeek's savings are computed from its harness lines: \(text(deepseek))")
  }

  /// Yesterday's and the day before's balance (UTC; $120.00 → $115.00, a $5 drop) and four harness lines: two apps,
  /// yesterday and today. The lines cost ≈ $1 a day at the fixture price book, so yesterday drifts by ≈ −$4.
  private func seed() throws {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let now = Date()
    func day(_ offset: Int) -> String {
      let date = now.addingTimeInterval(TimeInterval(-86_400 * offset))
      let parts = utc.dateComponents([.year, .month, .day], from: date)
      return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    let account = try XCTUnwrap(try query("SELECT id FROM account WHERE provider = 'deepseek'"))
    try execute("""
      INSERT INTO balance_snapshot (account_id, ts, currency, amount_cents) VALUES
        ('\(account)', '\(day(2))T12:00:00.000Z', 'USD', 12000),
        ('\(account)', '\(day(1))T12:00:00.000Z', 'USD', 11500);
      """)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let today = formatter.string(from: now.addingTimeInterval(-60))
    let lines = [("\(day(1))T10:00:00.000Z", "weather-collector", 1_000_000, 500_000),
                 ("\(day(1))T11:00:00.000Z", "news-digest", 400_000, 100_000),
                 (today, "weather-collector", 1_000_000, 500_000),
                 (today, "news-digest", 400_000, 100_000)]
    let text = lines.enumerated().map { index, line in
      #"{"v":1,"ts":"\#(line.0)","provider":"deepseek","app":"\#(line.1)","request_id":"drill-\#(index)","#
        + #""model":"deepseek-chat","usage":{"prompt_tokens":\#(line.2),"completion_tokens":\#(line.3),"#
        + #""prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":\#(line.2)},"status":"ok"}"#
    }.joined(separator: "\n") + "\n"
    try Data(text.utf8).write(to: ingest.appendingPathComponent("drill.jsonl"))
  }

  @MainActor
  private func onboardDeepSeek(_ app: XCUIApplication) throws {
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    control(app, "onboarding.provider.deepseek").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "step 2 shows the key field")
    field.click()
    field.typeText(fakeKey)
    control(app, "onboarding.test").click()
    XCTAssertTrue(control(app, "onboarding.done").waitForExistence(timeout: 15), "the probe passes in fixture mode")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 10), "Done closes onboarding")
  }

  // MARK: - Helpers

  private var databasePath: String { support.appendingPathComponent("tokenbe.sqlite").path }

  private func balances() -> Int {
    do {
      return Int(try query("SELECT count(*) FROM balance_snapshot") ?? "") ?? 0
    } catch {
      return 0
    }
  }

  /// The first column of the first row, as text; read-only.
  private func query(_ sql: String) throws -> String? {
    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(databasePath)"])
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: value)
  }

  private func execute(_ sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(databasePath)"])
    }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
  }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func waitFor(timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }
}
