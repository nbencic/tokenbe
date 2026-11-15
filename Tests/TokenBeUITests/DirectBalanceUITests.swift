import XCTest

// ui-covers: Sources/TokenBeApp/Onboarding/ Sources/TokenBeApp/Popover/AccountCardView.swift
// ui-covers: Sources/TokenBeApp/Popover/AlertBanner.swift Sources/TokenBeCore/Providers/
// ui-covers: Sources/TokenBeCore/Model/Formatters.swift Sources/TokenBeCore/Ledger/Remaining.swift
// ui-covers: Sources/TokenBeCore/Ledger/BandEvaluator.swift
/// 14 § Stage 6.1/6.2 (PM-6.1-2): a direct-balance account end to end, in fixture mode under a throwaway
/// `TOKENBE_TEST_ROOT` (Q-014). Onboarding a DeepSeek key shows `direct`, the first entry's currency and no anchor
/// field. After the first balance poll, the card shows the balance in `CN¥` without `≈` or `±`. An account the provider
/// reports unavailable gets 08's banner `DeepSeek: account unavailable` (D-deepseek-unavailable, Q-045).
/// Settings are not reset and no key is written to the shared suite beyond what onboarding writes (PM-4.2-5).
final class DirectBalanceUITests: XCTestCase {
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

  /// DeepSeek's standard keys have no prefix in 02, so any text passes step 2's check; built at run time (Q-028).
  private let fakeKey = "sk-" + String(repeating: "Dz4", count: 11)

  @MainActor
  func testDeepSeekCNYIsDirect() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true, fixtureCases: "deepseek/balance=cny")
    app.launch()
    try onboardDeepSeek(app, currency: "CNY")

    // The coordinator polls the new account at once; until then row 2 reads `No data yet`.
    XCTAssertTrue(openPopover(app, until: control(app, "popover.card.deepseek.label")), "the popover shows the card")
    var pinned = ""
    XCTAssertTrue(waitFor {
      pinned = text(control(app, "popover.card.deepseek.pinned"))
      return pinned.hasPrefix("CN\u{00A5}")
    }, "row 2 shows the CN¥ balance: \(pinned)")
    // Whole units or cents, either separator (the shared suite's hideCents and the owner's locale), never `≈`.
    XCTAssertTrue(["CN\u{00A5}57", "CN\u{00A5}56.79", "CN\u{00A5}56,79"].contains(pinned), "the CNY entry: \(pinned)")
    XCTAssertFalse(pinned.contains("\u{2248}") || pinned.contains("\u{00B1}"), "a direct balance is not an estimate")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  @MainActor
  func testUnavailableAccountBanner() throws {
    let app = makeApp(root: root, onboardingDone: false, fixtures: true,
                      fixtureCases: "deepseek/balance=unavailable")
    app.launch()
    try onboardDeepSeek(app, currency: "USD")
    XCTAssertTrue(openPopover(app, until: control(app, "popover.card.deepseek.label")), "the popover shows the card")
    var banner = ""
    XCTAssertTrue(waitFor {
      let element = control(app, "popover.banner.alert")
      banner = element.exists ? element.label : ""
      return banner == "DeepSeek: account unavailable"
    }, "08's banner for a forced critical: \(banner)")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  // MARK: - Helpers

  /// Steps 1–3 for DeepSeek: 08's caption, the fixture key, `direct` with the fixture's currency, no anchor field.
  @MainActor
  private func onboardDeepSeek(_ app: XCUIApplication, currency: String) throws {
    XCTAssertTrue(control(app, "onboarding.root").waitForExistence(timeout: 15), "onboarding opens at launch")
    let tile = control(app, "onboarding.provider.deepseek")
    XCTAssertTrue(tile.waitForExistence(timeout: 5), "Debug builds offer DeepSeek")
    XCTAssertTrue(tile.label.contains("Balance only"), "08's caption: \(tile.label)")
    control(app, "onboarding.provider.deepseek").click()
    control(app, "onboarding.continue").click()
    let field = control(app, "onboarding.key")
    XCTAssertTrue(field.waitForExistence(timeout: 5), "step 2 shows the key field")
    field.click()
    field.typeText(fakeKey)
    control(app, "onboarding.test").click()
    XCTAssertTrue(control(app, "onboarding.done").waitForExistence(timeout: 15), "the probe passes in fixture mode")
    XCTAssertEqual(text(control(app, "onboarding.result.mode")), "direct")
    XCTAssertEqual(text(control(app, "onboarding.result.keyCount")), "0")
    XCTAssertEqual(text(control(app, "onboarding.result.currency")), currency)
    XCTAssertFalse(control(app, "onboarding.anchorAmount").exists, "a direct account is never asked for an anchor")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 10), "Done closes onboarding")
  }

  private func control(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func waitFor(timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return condition()
  }
}
