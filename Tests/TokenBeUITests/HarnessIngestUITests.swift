import SQLite3
import XCTest

// ui-covers: Sources/TokenBeCore/Ingest/ Sources/TokenBeCore/Store/Repository+Ingest.swift
// ui-covers: Sources/TokenBeCore/Normalize/HarnessNormalizer.swift Sources/TokenBeCore/Ledger/Attribution+Harness.swift
// ui-covers: Sources/TokenBeApp/Dashboard/ByAppTable.swift Sources/TokenBeApp/Dashboard/SourcesStrip.swift
/// 11 E2E-3 (14 § Stage 7.2; 01 A3), in fixture mode under a throwaway `TOKENBE_TEST_ROOT`, with a DeepSeek account:
/// `valid_500.jsonl` (500 lines, 3 apps, 2 providers, 12 duplicate request ids; its `ts` moved to the last minutes so
/// the lines are today's) is appended to `ingest/harness.jsonl` in 5 bursts while the app runs. The first burst's rows
/// appear within 5 s (A3). After burst 3 the app is killed; relaunched, it reads on from its stored offset; after
/// burst 5 there are 488 `harness_event` rows. DeepSeek's By-app table lists the 3 apps with badge `harness`, and
/// `bad_json.jsonl` lands in `rejected/`. Move-when-done is off for the run (a launch argument, so the shared suite is
/// unchanged): a 2 s pause would otherwise move the file between bursts.
final class HarnessIngestUITests: XCTestCase {
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
  private let fakeKey = "sk-" + String(repeating: "Hi7", count: 11)
  private var support: URL { root.appendingPathComponent("Application Support/TokenBe", isDirectory: true) }
  private var ingest: URL { support.appendingPathComponent("ingest", isDirectory: true) }
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/harness")

  private func launch(onboarding: Bool = false) -> XCUIApplication {
    let app = makeApp(root: root, onboardingDone: !onboarding, fixtures: true)
    app.launchArguments += ["-tb.ingest.moveWhenDone", "<false/>"]
    app.launch()
    return app
  }

  @MainActor
  func testBurstsKillRelaunchAndByApp() throws {
    let bursts = try Self.bursts()
    let first = launch(onboarding: true)
    try onboardDeepSeek(first)
    XCTAssertTrue(waitFor { FileManager.default.fileExists(atPath: self.ingest.path) }, "startup step 5 made ingest/")

    let landed = Date()
    try append(bursts[0])
    XCTAssertTrue(waitFor(timeout: 5) { self.events() == Self.unique(bursts.prefix(1)) },
                  "A3: the first burst's rows within 5 s (\(events()) after \(Date().timeIntervalSince(landed)) s)")
    try append(bursts[1])
    try append(bursts[2])
    XCTAssertTrue(waitFor { self.events() == Self.unique(bursts.prefix(3)) }, "bursts 1–3 stored: \(events())")
    first.terminate()   // a hard kill, like `kill -9`: no clean terminate path runs

    let app = launch()
    try append(bursts[3])
    try append(bursts[4])
    XCTAssertTrue(waitFor { self.events() == 488 }, "all 500 lines, 12 duplicates: \(events()) rows")
    try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("bad_json.jsonl"),
                                     to: ingest.appendingPathComponent("bad_json.jsonl"))
    XCTAssertTrue(waitFor {
      FileManager.default.fileExists(atPath: self.ingest.appendingPathComponent("rejected/bad_json.jsonl").path)
    }, "bad_json.jsonl lands in rejected/")
    XCTAssertEqual(try query("SELECT count(*) FROM harness_event"), "488", "no line twice after the kill")

    let card = control(app, "popover.card.deepseek")
    XCTAssertTrue(openPopover(app, until: card), "the popover shows the DeepSeek card")
    card.click()
    for tag in ["weather-collector", "news-digest", "code-review"] {
      let row = control(app, "dashboard.account.byApp.name.\(tag)")
      XCTAssertTrue(row.waitForExistence(timeout: 15), "By app lists \(tag)")
      XCTAssertEqual(text(row), tag)
    }
    XCTAssertTrue(control(app, "dashboard.account.source.harness").label.hasPrefix("Harness · 1 file · "),
                  "the Sources strip's harness column: \(control(app, "dashboard.account.source.harness").label)")
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  // MARK: - Steps

  /// The fixture's 500 lines with `ts` moved to the last 500 s (now − 600 s + i), in 5 bursts of 100.
  static func bursts() throws -> [[String]] {
    let lines = try String(contentsOf: fixtures.appendingPathComponent("valid_500.jsonl"), encoding: .utf8)
      .split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, 500)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let start = Date().addingTimeInterval(-600)
    let moved = lines.enumerated().map { index, line in
      line.replacingOccurrences(of: #""ts":"[^"]*""#,
                                with: "\"ts\":\"\(formatter.string(from: start.addingTimeInterval(Double(index))))\"",
                                options: .regularExpression)
    }
    return stride(from: 0, to: 500, by: 100).map { Array(moved[$0..<($0 + 100)]) }
  }

  /// Distinct request ids among the bursts (a duplicate repeats an earlier line whole).
  static func unique(_ bursts: ArraySlice<[String]>) -> Int {
    Set(bursts.flatMap { $0 }.compactMap { line in
      line.range(of: #""request_id":"[^"]*""#, options: .regularExpression).map { String(line[$0]) }
    }).count
  }

  /// One burst appended in one write per line, as reporters do (06: append only).
  private func append(_ lines: [String]) throws {
    let url = ingest.appendingPathComponent("harness.jsonl")
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    for line in lines { try handle.write(contentsOf: Data((line + "\n").utf8)) }
    try handle.close()
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

  private func events() -> Int {
    do {
      return Int(try query("SELECT count(*) FROM harness_event") ?? "") ?? -1
    } catch {
      return -1
    }
  }

  /// The first column of the first row, as text; read-only.
  private func query(_ sql: String) throws -> String? {
    var db: OpaquePointer?
    let path = support.appendingPathComponent("tokenbe.sqlite").path
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot open \(path)"])
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
