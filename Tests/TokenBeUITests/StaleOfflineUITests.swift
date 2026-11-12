import XCTest

/// 14 § Stage 4.2 Tests, `StaleOfflineUITests` (E2E-5 of 11), in fixture mode under a throwaway `TOKENBE_TEST_ROOT`
/// (Q-014). Settings that shorten the wait go in as launch arguments (the argument domain, never stored), and no test
/// resets the UI-test suite, so later checks still see what earlier suites left (PM-3.4-8).
/// - Offline (`TOKENBE_TEST_OFFLINE=1`, Q-036), after one online poll: the banner, every card under the stale
///   overlay (`stale · …`), the glyph `glyph.dashed`; in light and dark appearance (08 § Definition of done).
/// - Stale: usage answers 500 after one success; past 2 × 60 s the card dims and reads `stale · …`, the glyph is
///   dashed; the card opens the account page (header, badges with help, sources strip with the human message).
///   Recovery: with `ok` fixtures the first poll clears it.
final class StaleOfflineUITests: XCTestCase {
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
  private let fakeKey = "sk-" + "admin-" + String(repeating: "St4", count: 14)

  /// 60 s usage interval, stale past 2 × 60 s (09's minimums).
  private let fastStale = ["-tb.poll.usageIntervalOpenAIS", "<integer>60</integer>",
                           "-tb.alerts.staleMultiplier", "<integer>2</integer>"]

  @MainActor
  func testOfflineBannerDimmedCardsAndDashedGlyph() throws {
    // Online first: onboard, one usage poll, so the cards have last known values.
    let online = makeApp(root: root, onboardingDone: false, fixtures: true)
    online.launch()
    try onboard(online)
    XCTAssertTrue(waitFor { self.count("\"evt\":\"poll.ok\"", job: "usage") == 1 }, "first usage poll")
    XCTAssertTrue(quitThroughPopover(online), "the app quits")

    let app = makeApp(root: root, fixtures: true)
    app.launchEnvironment["TOKENBE_TEST_OFFLINE"] = "1"
    app.launch()
    XCTAssertTrue(waitFor { self.count("\"reason\":\"offline\"", job: "usage") >= 1 },
                  "the scheduler skips while offline (sched.skip reason=offline)")
    try assertOffline(app)
    XCTAssertTrue(quitThroughPopover(app), "the app quits")

    let dark = makeApp(root: root, fixtures: true)
    dark.launchEnvironment["TOKENBE_TEST_OFFLINE"] = "1"
    dark.launchArguments += ["-tb.ui.appearance", "dark"]
    dark.launch()
    try assertOffline(dark)
    XCTAssertTrue(quitThroughPopover(dark), "the app quits")

    let failures = try logLines().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertEqual(failures, [], "offline is not an error")
  }

  @MainActor
  func testStaleOverlayAccountPageAndRecovery() throws {
    // Launch 1: onboard; the coordinator's first usage poll succeeds.
    let first = makeApp(root: root, onboardingDone: false, fixtures: true)
    first.launch()
    try onboard(first)
    XCTAssertTrue(waitFor { self.count("\"evt\":\"poll.ok\"", job: "usage") == 1 }, "first usage poll")
    XCTAssertTrue(quitThroughPopover(first), "the app quits")

    // Launch 2: usage now answers 500; past 2 × 60 s after that success the account is stale.
    let failing = makeApp(root: root, fixtures: true, fixtureCases: "openai/usage_completions=500")
    failing.launchArguments += fastStale
    failing.launch()
    XCTAssertTrue(failing.statusItems["glyph.dashed"].waitForExistence(timeout: 180), "the glyph turns dashed")
    let card = control(failing, "popover.card.openai")
    XCTAssertTrue(openPopover(failing, until: card), "the popover opens")
    let freshness = text(control(failing, "popover.card.openai.freshness"))
    XCTAssertTrue(freshness.hasPrefix("stale \u{00B7} "), freshness)
    XCTAssertFalse(control(failing, "popover.banner.offline").exists, "online: no Offline banner")

    // The card opens the account page.
    card.click()
    try assertAccountPage(failing)
    failing.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(failing), "the app quits")
    let errors = try logLines().filter { $0.contains("\"lvl\":\"error\"") || $0.contains("\"lvl\":\"fault\"") }
    XCTAssertFalse(errors.isEmpty, "the 500s are logged")
    XCTAssertEqual(errors.filter { !($0.contains("\"evt\":\"poll.failed\"") && $0.contains("\"job\":\"usage\"")) }, [],
                   "every error record is one failed usage poll (A4)")

    // Launch 3: usage answers again; the first poll clears the overlay.
    let recovered = makeApp(root: root, fixtures: true)
    recovered.launchArguments += fastStale
    recovered.launch()
    XCTAssertTrue(recovered.statusItems["glyph.solid"].waitForExistence(timeout: 60), "the glyph is solid again")
    let again = control(recovered, "popover.card.openai")
    XCTAssertTrue(openPopover(recovered, until: again), "the popover opens")
    let cleared = text(control(recovered, "popover.card.openai.freshness"))
    XCTAssertFalse(cleared.hasPrefix("stale"), "no stale overlay: \(cleared)")
    XCTAssertTrue(quitThroughPopover(recovered), "the app quits")
    XCTAssertFalse(try logLines().joined().contains(fakeKey), "the key never reaches the log")
  }

  // MARK: - Steps

  /// The account page of a stale OpenAI account whose usage answers 500: header, sources strip, badges and help.
  @MainActor
  private func assertAccountPage(_ failing: XCUIApplication) throws {
    let label = control(failing, "dashboard.account.label")
    XCTAssertTrue(label.waitForExistence(timeout: 10), "the card opens the account page")
    XCTAssertEqual(text(label), "OpenAI")
    XCTAssertTrue(text(control(failing, "dashboard.account.freshness")).hasPrefix("stale \u{00B7} "))
    XCTAssertEqual(text(control(failing, "dashboard.account.band")), "Band: unknown")
    XCTAssertTrue(control(failing, "dashboard.account.refresh").exists, "the header has Refresh")
    let usage = control(failing, "dashboard.account.source.usage").label
    XCTAssertTrue(usage.hasPrefix("Usage \u{00B7} failed \u{00B7} "), usage)
    XCTAssertTrue(usage.hasSuffix("OpenAI returned a server error (HTTP 500). Try again later."), usage)
    XCTAssertEqual(control(failing, "dashboard.account.source.balance").label, "Balance \u{00B7} n/a")
    let keys = control(failing, "dashboard.account.source.keys").label
    XCTAssertTrue(keys.hasPrefix("Keys \u{00B7} ok \u{00B7} "), keys)
    XCTAssertTrue(keys.contains(" \u{00B7} next "), keys)
    let badge = control(failing, "dashboard.account.badge.balance")
    XCTAssertEqual(badge.label, "Balance: anchored")
    for (id, expected) in [("usage", "Usage: per key"), ("cost", "Cost: provider"), ("lag", "Lag: 1 h")] {
      XCTAssertEqual(control(failing, "dashboard.account.badge.\(id)").label, expected)
    }
    badge.click()
    let help = control(failing, "dashboard.account.badge.balance.help")
    XCTAssertTrue(help.waitForExistence(timeout: 5), "the badge's help popover")
    XCTAssertEqual(text(help), "There is no balance endpoint, so remaining is your anchor plus top-ups minus spend since the anchor.")
  }

  @MainActor
  private func assertOffline(_ app: XCUIApplication) throws {
    XCTAssertTrue(app.statusItems["glyph.dashed"].waitForExistence(timeout: 15), "offline: the glyph is dashed")
    let banner = control(app, "popover.banner.offline")
    XCTAssertTrue(openPopover(app, until: banner), "the Offline banner")
    XCTAssertEqual(text(banner), "Offline \u{2014} showing last known values")
    let freshness = text(control(app, "popover.card.openai.freshness"))
    XCTAssertTrue(freshness.hasPrefix("stale \u{00B7} "), "offline puts every card under the stale overlay: \(freshness)")
    app.typeKey(.escape, modifierFlags: [])
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

  // MARK: - Helpers

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

  /// Log records containing `fragment` for `job` (PM-2.2-2).
  private func count(_ fragment: String, job: String) -> Int {
    let lines: [String]
    do {
      lines = try logLines()
    } catch {
      XCTFail("log unreadable: \(error)")
      return 0
    }
    return lines.filter { $0.contains(fragment) && $0.contains("\"job\":\"\(job)\"") }.count
  }

  private func logLines() throws -> [String] {
    let folder = root.appendingPathComponent("Logs/TokenBe", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "ndjson" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
  }
}
