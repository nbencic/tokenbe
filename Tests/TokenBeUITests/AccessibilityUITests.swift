import XCTest

// ui-covers: Sources/TokenBeApp/Components/AccessibilityOverrides.swift Sources/TokenBeApp/Components/TableKeyboard.swift
// ui-covers: Sources/TokenBeApp/Components/BandDot.swift Sources/TokenBeCore/Model/SpokenFormatters.swift
// ui-covers: Sources/TokenBeApp/Popover/AccountCardView.swift Sources/TokenBeApp/Popover/PopoverView.swift
// ui-covers: Sources/TokenBeApp/Popover/AlertBanner.swift Sources/TokenBeApp/Dashboard/NumbersStrip.swift
// ui-covers: Sources/TokenBeApp/Dashboard/RunwayBoard.swift Sources/TokenBeApp/Dashboard/OverviewHeadline.swift
// ui-covers: Sources/TokenBeApp/Dashboard/OverviewView.swift Sources/TokenBeApp/Dashboard/ByAppTable.swift
// ui-covers: Sources/TokenBeApp/Dashboard/ByModelTable.swift Sources/TokenBeApp/Dashboard/LedgerList.swift
/// 14 § Stage 8.4 Tests, `AccessibilityUITests` (08 § Accessibility), in fixture mode under a throwaway
/// `TOKENBE_TEST_ROOT`, with an anchored OpenAI account ($42, cents hidden):
/// - VoiceOver reads the card's figure as 08's sentence, `Remaining, approximately 42 dollars, plus or minus 0`, and
///   the band dot by its word;
/// - at the `xxLarge` text size (`TOKENBE_TEST_TEXT_SIZE`, never the owner's system setting) the card's figure is
///   taller than at the default size, and the popover keeps its 360 pt width;
/// - the account page's numbers strip and the Overview's runway board read their figures in words with their
///   titles; the board's row takes keyboard focus, and Esc leaves it.
/// Reduce Motion (`TOKENBE_TEST_REDUCE_MOTION`) is on for the second launch; what it changes (a pulse for a spin) is
/// not exposed to accessibility, so 8.4.sh checks the code.
final class AccessibilityUITests: XCTestCase {
  private var root: URL!
  /// Built at run time so no key-shaped literal is committed (Q-028).
  private let fakeKey = "sk-" + "admin-" + String(repeating: "Ax8", count: 14)
  private let sentence = "Remaining, approximately 42 dollars, plus or minus 0"

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
  func testSpokenFiguresTextSizeAndKeyboard() throws {
    let first = launch(onboardingDone: false)
    try onboard(first)
    let pinned = control(first, "popover.card.openai.pinned")
    XCTAssertTrue(openPopover(first, until: pinned), "the popover shows the card")
    XCTAssertTrue(waitFor { self.text(pinned) == self.sentence }, "08's sentence, got `\(text(pinned))`")
    XCTAssertTrue(control(first, "popover.card.openai.band").label.hasPrefix("Band: "), "the band dot names its band")
    let normalHeight = pinned.frame.height
    first.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quitThroughPopover(first), "the app quits")

    let app = launch(onboardingDone: true, large: true)
    let largePinned = control(app, "popover.card.openai.pinned")
    XCTAssertTrue(openPopover(app, until: largePinned), "the popover shows the card")
    XCTAssertTrue(waitFor { self.text(largePinned) == self.sentence }, "the same words at xxLarge")
    let largeHeight = largePinned.frame.height
    XCTContext.runActivity(named: "pinned height: default \(normalHeight), xxLarge \(largeHeight)") { _ in }
    XCTAssertGreaterThan(largeHeight, normalHeight, "xxLarge text is larger (08: Dynamic Type up to xxLarge)")
    XCTAssertEqual(control(app, "popover.root").frame.width, 360, accuracy: 1, "the popover keeps its width")
    try audit(app, "popover at xxLarge")

    largePinned.click()
    let remaining = control(app, "dashboard.account.numbers.remaining")
    XCTAssertTrue(remaining.waitForExistence(timeout: 10), "the card opens the account page")
    XCTAssertEqual(text(remaining), sentence, "the numbers strip reads the same sentence")

    app.activate()
    let overview = control(app, "dashboard.sidebar.overview")
    XCTAssertTrue(overview.waitForExistence(timeout: 5))
    overview.click()
    let row = control(app, "dashboard.runwayBoard.openai")
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the Overview shows the runway board")
    let boardRemaining = control(app, "dashboard.runwayBoard.openai.remaining")
    XCTAssertEqual(text(boardRemaining), sentence, "the board's cell reads the figure with its column title")
    try audit(app, "Dashboard")
    try checkKeyboardFocus(app, row: row)
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "the app quits")
  }

  /// The board's row takes focus on a click on its first cell; Esc gives it up (`TableKeyboard`). Keys are typed
  /// only after the Dashboard is frontmost, so none can land in another app.
  @MainActor
  private func checkKeyboardFocus(_ app: XCUIApplication, row: XCUIElement) throws {
    let name = row.descendants(matching: .any).matching(NSPredicate(format: "value == 'OpenAI' OR label == 'OpenAI'"))
      .firstMatch
    let target = name.exists ? name : row
    target.click()
    XCTAssertTrue(waitFor(timeout: 5) { self.focused(app) }, "a click gives the board's row keyboard focus")
    XCTAssertEqual(app.state, .runningForeground, "the Dashboard is frontmost before any key")
    app.typeKey(.downArrow, modifierFlags: [])
    XCTAssertTrue(focused(app), "↓ on the only row keeps the focus in the table")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitFor(timeout: 5) { !self.focused(app) }, "Esc leaves the table")
  }

  /// XCTest's accessibility audit, the scriptable part of the Accessibility Inspector pass (Q-054). It fails on every
  /// issue except those that belong to system chrome: an unlabelled container (no identifier) that
  /// `NavigationSplitView` draws as a `Group`, or the `MenuBarExtra` panel, an untitled `Dialog`; contrast on the sidebar's rows and the window title, and a contrast that "nearly
  /// passed" (secondary text in the system style). Each tolerated issue is logged.
  @MainActor
  private func audit(_ app: XCUIApplication, _ place: String) throws {
    var failed: [String] = []
    try app.performAccessibilityAudit { issue in
      let element = issue.element
      let identifier = element?.identifier ?? ""
      let container = [.group, .dialog].contains(element?.elementType) && identifier.isEmpty
      // The popover header's `Refreshed …` is Paper's secondary caption on the header material; its colour is
      // 11.3's call against Paper (PM-8.4-2), so it is tolerated by name.
      let chrome = identifier.hasPrefix("dashboard.sidebar.") || identifier.isEmpty
        || identifier == "popover.header.freshness"
      let tolerated = (issue.auditType == .sufficientElementDescription && container)
        || (issue.auditType == .contrast && (chrome || issue.compactDescription.contains("nearly")))
      let line = "\(issue.compactDescription) | \(identifier) \(element?.label ?? "")"
      XCTContext.runActivity(named: "audit \(place): \(tolerated ? "tolerated" : "FAILED") \(line)") { _ in }
      if !tolerated { failed.append(line) }
      return true
    }
    XCTAssertEqual(failed, [], "accessibility audit, \(place)")
  }

  /// Whether an element of the runway board has keyboard focus.
  private func focused(_ app: XCUIApplication) -> Bool {
    let board = control(app, "dashboard.runwayBoard")
    return board.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).count > 0
  }

  private func launch(onboardingDone: Bool, large: Bool = false) -> XCUIApplication {
    let app = makeApp(root: root, onboardingDone: onboardingDone, fixtures: true,
                      fixtureCases: "openai/usage_completions=empty")
    app.launchArguments += ["-tb.ui.hideCents", "<true/>", "-tb.popover.pinnedMetric", "remaining"]
    if large {
      app.launchEnvironment["TOKENBE_TEST_TEXT_SIZE"] = "xxLarge"
      app.launchEnvironment["TOKENBE_TEST_REDUCE_MOTION"] = "1"
    }
    app.launch()
    return app
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
    amount.typeText("42")
    control(app, "onboarding.setAnchor").click()
    XCTAssertTrue(control(app, "onboarding.anchorSaved").waitForExistence(timeout: 5), "the anchor is saved")
    control(app, "onboarding.done").click()
    XCTAssertTrue(control(app, "onboarding.root").waitForNonExistence(timeout: 5), "Done closes onboarding")
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
