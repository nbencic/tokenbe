import CoreGraphics
import Foundation
import Testing
@testable import TokenBeCore

/// Stage 1.2: the range setting, the saved Dashboard frame and the 500 ms save debounce (14 § 1.2, 09).
@Suite struct DashboardRangeTests {
  @Test("raw values are 09's allowed values; anything else reads as the 7 d default")
  func rawValues() {
    #expect(DashboardRange.allCases.map(\.rawValue) == ["today", "7d", "30d", "90d"])
    #expect(DashboardRange(setting: "30d") == .thirtyDays)
    #expect(DashboardRange(setting: "") == .sevenDays)
    #expect(DashboardRange(setting: "365d") == .sevenDays)
    let spec = SettingsKey.uiDashboardRange.spec
    #expect(spec.defaultValue == .string(DashboardRange.default.rawValue))
    if case .oneOf(let allowed) = spec.rule {
      #expect(allowed == DashboardRange.allCases.map(\.rawValue), "09's allowed values match the enum")
    } else {
      Issue.record("tb.ui.dashboardRange should be a oneOf setting")
    }
  }
}

@Suite struct WindowFrameTests {
  static let screen = CGRect(x: 0, y: 0, width: 1470, height: 919)
  static let minimum = CGSize(width: 920, height: 600)

  @Test("encode writes NSStringFromRect's format with integral points; decode reads it back")
  func roundTrip() {
    let rect = CGRect(x: 100, y: 80.4, width: 1000.6, height: 700)
    let text = WindowFrame.encode(rect)
    #expect(text == "{{100, 80}, {1001, 701}}")
    #expect(WindowFrame.decode(text) == CGRect(x: 100, y: 80, width: 1001, height: 701))
    #expect(WindowFrame.decode("{{-1440, 25.5}, {920, 600}}") == CGRect(x: -1440, y: 25.5, width: 920, height: 600))
  }

  @Test("decode rejects empty, malformed, non-finite and empty-size text")
  func rejects() {
    for text in ["", "garbage", "{{1, 2}, {3}}", "{1, 2, 3, 4}", "{{1, 2}, {0, 600}}", "{{1, 2}, {-5, 600}}",
                 "{{nan, 2}, {920, 600}}", "{{1, 2}, {inf, 600}}", "{{1, 2}, {920, 600}} extra 5"] {
      #expect(WindowFrame.decode(text) == nil, "\(text)")
    }
  }

  @Test("restore: saved frame on screen, grown to the minimum; nil when nothing is saved or it is off-screen")
  func restorable() {
    let screens = [Self.screen]
    #expect(WindowFrame.restorable(saved: "{{100, 100}, {1000, 700}}", screens: screens, minimum: Self.minimum)
      == CGRect(x: 100, y: 100, width: 1000, height: 700))
    #expect(WindowFrame.restorable(saved: "{{100, 100}, {500, 300}}", screens: screens, minimum: Self.minimum)
      == CGRect(x: 100, y: 100, width: 920, height: 600))
    #expect(WindowFrame.restorable(saved: "", screens: screens, minimum: Self.minimum) == nil)
    #expect(WindowFrame.restorable(saved: "{{-3000, 100}, {1000, 700}}", screens: screens, minimum: Self.minimum) == nil,
            "on a display that is no longer connected")
    #expect(WindowFrame.restorable(saved: "{{1450, 100}, {1000, 700}}", screens: screens, minimum: Self.minimum) == nil,
            "only 20 pt visible")
    let second = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    #expect(WindowFrame.restorable(saved: "{{-1500, 100}, {1000, 700}}", screens: [Self.screen, second],
                                   minimum: Self.minimum) != nil)
    #expect(WindowFrame.restorable(saved: "{{100, 100}, {1000, 700}}", screens: [], minimum: Self.minimum) == nil)
  }
}

@MainActor @Suite struct DebouncerTests {
  final class Counter {
    var values: [Int] = []
  }

  @Test("only the last submission runs, once, after the delay")
  func lastWins() async {
    let clock = TestClock()
    let debouncer = Debouncer(delay: .milliseconds(500), clock: clock)
    let counter = Counter()
    debouncer.submit { counter.values.append(1) }
    await clock.waitForSleepers(1)
    clock.advance(by: .milliseconds(300))
    debouncer.submit { counter.values.append(2) }
    // The first sleeper (deadline 500 ms) is gone; only the second, submitted at 300 ms, sleeps until 800 ms.
    await clock.waitUntil("only the second sleeper") { $0.deadlines == [.milliseconds(800)] }
    clock.advance(by: .milliseconds(300))
    await settle()
    #expect(counter.values.isEmpty, "600 ms after the first, 300 ms after the second: nothing yet")
    clock.advance(by: .milliseconds(200))
    await settle()
    #expect(counter.values == [2])
    clock.advance(by: .seconds(5))
    await settle()
    #expect(counter.values == [2])
  }

  @Test("cancel drops the pending action")
  func cancel() async {
    let clock = TestClock()
    let debouncer = Debouncer(delay: .milliseconds(500), clock: clock)
    let counter = Counter()
    debouncer.submit { counter.values.append(1) }
    await clock.waitForSleepers(1)
    debouncer.cancel()
    clock.advance(by: .seconds(1))
    await settle()
    #expect(counter.values.isEmpty)
  }

  private func settle() async {
    for _ in 0..<200 { await Task.yield() }
  }
}

@Suite struct SettingsSuiteResetTests {
  // The positive path (the UI-test suite is cleared) is proven by `DashboardShellUITests`, which resets and then
  // sees the 7 d default although the previous run left 30 d. Unit tests never write that suite: verify reads it
  // after the UI tests, and the registration domain is shared by every suite in the test process.
  @Test("only the UI-test suite can be reset; the owner's real suite and any other name are refused")
  func refusesOtherSuites() {
    #expect(SettingsSuite.uiTestsName == "dev.bathyon.tokenbe.uitests")
    #expect(!SettingsSuite.resetUITests(named: SettingsSuite.name))
    #expect(!SettingsSuite.resetUITests(named: "dev.bathyon.tokenbe.other"))
    #expect(!SettingsSuite.resetUITests(named: ""))
  }
}
