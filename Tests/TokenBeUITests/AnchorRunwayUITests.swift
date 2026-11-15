import SQLite3
import XCTest

// ui-covers: Sources/TokenBeApp/Onboarding/ Sources/TokenBeApp/Popover/AccountCardView.swift
// ui-covers: Sources/TokenBeApp/Popover/AlertBanner.swift Sources/TokenBeApp/Dashboard/AccountDetailView.swift
// ui-covers: Sources/TokenBeApp/Dashboard/LedgerList.swift Sources/TokenBeApp/Dashboard/NumbersStrip.swift
// ui-covers: Sources/TokenBeApp/Dashboard/SetAnchorSheet.swift Sources/TokenBeCore/Ledger/
// ui-covers: Sources/TokenBeCore/Presentation/AccountPresentation.swift
/// 14 § Stage 5.3 Tests, `AnchorRunwayUITests` (E2E-2), in fixture mode under a throwaway `TOKENBE_TEST_ROOT`:
/// - onboarding with a $100 anchor and empty usage fixtures → the card reads `≈ $100 ± 0` with Day-1's
///   `Collecting… runway after 2 days of data`, and the banner offers nothing;
/// - two closed UTC days of heavy usage, written into the test root's database between launches, drive the account
///   `critical`: the card's band dot says so and the alert banner reads `OpenAI: … left`; its tap opens the account
///   page with the numbers strip and the ledger.
final class AnchorRunwayUITests: XCTestCase {
  private var root: URL!
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Rw4", count: 14)
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
  func testAnchorDayOneAndCriticalBanner() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true, fixtureCases: emptyUsage)
    app.launch()
    try onboard(app, anchor: "100")
    let pinned = control(app, "popover.card.openai.pinned")
    XCTAssertTrue(openPopover(app, until: pinned), "the popover shows the card")
    // `≈ $100 ± 0` or `≈ $100,00 ± 0,00`: the locale and the shared suite's `tb.ui.hideCents` decide the cents.
    XCTAssertTrue(waitFor { self.text(pinned).hasPrefix("\u{2248} $100") && self.text(pinned).contains(" \u{00B1} ") },
                  "set anchor → `≈ $100 ± …`, got `\(text(pinned))` / `\(text(control(app, "popover.card.openai.row3")))`")
    XCTAssertTrue(text(control(app, "popover.card.openai.row3")).hasSuffix("Collecting\u{2026} runway after 2 days of data"),
                  "Day-1: row 3 ends with 08's collecting text")
    XCTAssertFalse(control(app, "popover.banner.alert").exists, "no banner while the band is unknown with an anchor")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    try seedHeavyDays()
    let again = makeApp(root: root, fixtures: true, fixtureCases: emptyUsage)
    again.launch()
    let banner = control(again, "popover.banner.alert")
    XCTAssertTrue(openPopover(again, until: banner), "the fixture drives the account critical: the banner shows")
    let line = banner.label
    XCTAssertTrue(line.hasPrefix("OpenAI: ") && line.hasSuffix(" left"), "banner: \(line)")
    XCTAssertTrue(control(again, "popover.card.openai.band").label.contains("critical"), "the band dot says critical")
    banner.click()
    XCTAssertTrue(control(again, "dashboard.account.numbers.remaining").waitForExistence(timeout: 10),
                  "the banner opens the account page")
    XCTAssertTrue(control(again, "dashboard.ledger.row.anchor").exists, "the ledger lists the anchor")
    // PM-4.2-1: the header's band pill names the band (08 § Accessibility: colour is never the only carrier).
    let pill = control(again, "dashboard.account.band")
    XCTAssertTrue(waitFor { self.text(pill) == "Band: critical" }, "the pill says critical: `\(text(pill))`")
    again.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(waitFor { self.logLinesOrNone().contains { $0.contains("\"evt\":\"ui.band_change\"") } },
                  "the change to critical is logged")
    XCTAssertEqual(try untracedBandChanges(), [], "E2E-9: every data-triggered band change follows a poll or ledger record")
  }

  /// E2E-9, the same join as `scripts/check-traceability.sh` (Q-042): a `ui.band_change` with trigger `data` needs a
  /// `poll.ok` or `ledger.*` record for its `acct` within the 2 s before it, or a `poll.ok` within the 2 s after.
  private struct Record {
    var evt: String
    var acct: String
    var trigger: String
    var time: Date
  }

  private func untracedBandChanges() throws -> [String] {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let records: [Record] = try logLines().compactMap { line in
      guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let evt = object["evt"] as? String, let stamp = object["ts"] as? String,
            let time = parser.date(from: stamp) else { return nil }
      let trigger = (object["ctx"] as? [String: Any])?["trigger"] as? String ?? "data"
      return Record(evt: evt, acct: object["acct"] as? String ?? "", trigger: trigger, time: time)
    }
    return records.filter { $0.evt == "ui.band_change" && $0.trigger == "data" }.compactMap { change in
      let traced = records.contains { other in
        guard other.acct == change.acct else { return false }
        let delta = change.time.timeIntervalSince(other.time)
        let before = (other.evt == "poll.ok" || other.evt.hasPrefix("ledger.")) && delta >= 0 && delta <= 2
        let after = other.evt == "poll.ok" && delta < 0 && delta >= -2
        return before || after
      }
      return traced ? nil : "\(change.acct) at \(change.time)"
    }
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
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 5), "Done closes onboarding")
  }

  /// $300 estimated on each of the two UTC days before today: `burn_7d` = $85.71/day, so the $100 anchor (set today)
  /// lasts about 28 h, below 09's 2-day critical threshold.
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

  private func logLines() throws -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }

  /// The log lines, or none while the folder is being written.
  private func logLinesOrNone() -> [String] {
    do {
      return try logLines()
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
