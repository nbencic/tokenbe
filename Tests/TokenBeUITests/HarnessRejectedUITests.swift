import AppKit
import XCTest

// ui-covers: Sources/TokenBeApp/SettingsUI/HarnessReportsSection.swift Sources/TokenBeApp/SettingsUI/SourcesTab.swift
// ui-covers: Sources/TokenBeApp/Resources/reporters/ Sources/TokenBeCore/Ingest/
/// 14 § Stage 7.2 Tests, `HarnessRejectedUITests`, under a throwaway `TOKENBE_TEST_ROOT` with no account: a bad file
/// goes to `rejected/` and Settings → Sources → Harness reports counts it (06 DoD: "UI shows count"). The section shows
/// the folder, `Watching · N files · …`, today's counters, the line stored for a provider not added (O-12), turns
/// the watch off (`Off`) and on again, and `Copy reporter snippet` → Python puts the bundled reporter on the
/// pasteboard. Every toggle it changes it changes back (PM-4.2-5); the test leaves General selected.
final class HarnessRejectedUITests: XCTestCase {
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

  private var ingest: URL { root.appendingPathComponent("Application Support/TokenBe/ingest", isDirectory: true) }
  static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/harness")

  @MainActor
  func testRejectedFileAndSourcesGroup() throws {
    let app = makeApp(root: root)
    app.launch()
    XCTAssertTrue(waitFor { FileManager.default.fileExists(atPath: self.ingest.path) }, "startup step 5 made ingest/")
    for name in ["bad_json.jsonl", "unknown_provider.jsonl"] {
      try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name),
                                       to: ingest.appendingPathComponent(name))
    }
    XCTAssertTrue(waitFor {
      FileManager.default.fileExists(atPath: self.ingest.appendingPathComponent("rejected/bad_json.jsonl").path)
    }, "the bad file lands in rejected/")

    let settings = control(app, "popover.footer.settings")
    XCTAssertTrue(openPopover(app, until: settings), "the popover opens")
    settings.click()
    try selectTab(app, "Sources")
    let counters = control(app, "settings.sources.harness.counters")
    XCTAssertTrue(counters.waitForExistence(timeout: 10), "the Harness reports group exists")
    XCTAssertTrue(waitFor { self.text(counters) == "Today: 1 ok · 0 duplicate · 2 rejected" },
                  "the rejected file and the unknown provider's line are counted: \(text(counters))")
    XCTAssertTrue(text(control(app, "settings.sources.harness.folder")).hasSuffix("Application Support/TokenBe/ingest"))
    let status = control(app, "settings.sources.harness.status")
    // `unknown_provider.jsonl` may already have moved to ingested/ (move-when-done is on): 0 or 1 file.
    XCTAssertNotNil(text(status).range(of: #"^Watching · [01] files? · last line "#, options: .regularExpression),
                    "status: \(text(status))")
    XCTAssertEqual(text(control(app, "settings.sources.harness.withoutAccount")),
                   "1 line for providers you haven\u{2019}t added")

    let watch = control(app, "settings.sources.harness.watch")
    watch.click()
    XCTAssertTrue(waitFor { self.text(status) == "Off" }, "the watch stops: \(text(status))")
    watch.click()
    XCTAssertTrue(waitFor { self.text(status).hasPrefix("Watching") }, "and starts again: \(text(status))")

    NSPasteboard.general.clearContents()
    control(app, "settings.sources.harness.copySnippet").click()
    app.menuItems["Python"].click()
    XCTAssertTrue(waitFor { NSPasteboard.general.string(forType: .string)?.contains("def report(") == true },
                  "the Python reporter is on the pasteboard")
    try selectTab(app, "General")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(quitThroughPopover(app), "the app quits")
  }

  @MainActor
  private func selectTab(_ app: XCUIApplication, _ name: String) throws {
    let tab = app.toolbars.buttons[name].exists ? app.toolbars.buttons[name] : app.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name) exists")
    tab.click()
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
