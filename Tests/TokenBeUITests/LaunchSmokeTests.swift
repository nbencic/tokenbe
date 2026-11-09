import XCTest

/// 11 `LaunchSmokeTests`: the app launches and its menu-bar item exists.
final class LaunchSmokeTests: XCTestCase {
  @MainActor
  func testLaunchShowsStatusItem() throws {
    let app = XCUIApplication()
    // Debug builds keep logs, sentinel and settings under this root (Q-014); terminate() is a hard kill.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tokenbe-uitests-\(UUID().uuidString)")
    app.launchEnvironment["TOKENBE_TEST_ROOT"] = root.path
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.state == .runningBackground)
    let item = app.statusItems.firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 10), "menu-bar status item exists")
    app.terminate()
    let logs = root.appendingPathComponent("Logs/TokenBe")
    let files = try FileManager.default.contentsOfDirectory(atPath: logs.path)
    XCTAssertFalse(files.isEmpty, "the app logged under the test root, not the real ~/Library/Logs/TokenBe")
  }
}
