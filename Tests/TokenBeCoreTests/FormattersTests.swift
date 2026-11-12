import Foundation
import Testing
@testable import TokenBeCore

/// 08 § Formatting rules and 05 runway formatting, pinned to `en_US_POSIX` and `de_DE` (11 FormattersTests).
@Suite struct FormattersTests {
  static let posix = Locale(identifier: "en_US_POSIX")
  static let german = Locale(identifier: "de_DE")
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zagreb") ?? .gmt
    return calendar
  }()

  static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
  }

  @Test("the pinned locales have the separators these tests assume")
  func separators() {
    #expect(Self.posix.decimalSeparator == ".")
    #expect(Self.posix.groupingSeparator == ",")
    #expect(Self.german.decimalSeparator == ",")
    #expect(Self.german.groupingSeparator == ".")
  }

  @Test("money: whole units when cents are hidden (half up), two decimals otherwise, CN¥ prefix")
  func money() {
    struct Case {
      let cents: Int64
      let currency: Currency
      let hide: Bool
      let posix: String
      let german: String
      init(_ cents: Int64, _ currency: Currency, _ hide: Bool, _ posix: String, _ german: String) {
        (self.cents, self.currency, self.hide, self.posix, self.german) = (cents, currency, hide, posix, german)
      }
    }
    let cases: [Case] = [
      Case(4217, .usd, true, "$42", "$42"),
      Case(4217, .usd, false, "$42.17", "$42,17"),
      Case(4250, .usd, true, "$43", "$43"),
      Case(4249, .usd, true, "$42", "$42"),
      Case(4299, .usd, true, "$43", "$43"),
      Case(5, .usd, false, "$0.05", "$0,05"),
      Case(0, .usd, true, "$0", "$0"),
      Case(123_456_789, .usd, false, "$1,234,567.89", "$1.234.567,89"),
      Case(123_456_789, .usd, true, "$1,234,568", "$1.234.568"),
      Case(88_000, .cny, true, "CN¥880", "CN¥880"),
      Case(-500, .usd, true, "-$5", "-$5")
    ]
    for item in cases {
      let amount = Money(cents: item.cents, currency: item.currency)
      #expect(Formatters.money(amount, hideCents: item.hide, locale: Self.posix) == item.posix)
      #expect(Formatters.money(amount, hideCents: item.hide, locale: Self.german) == item.german)
    }
    #expect(Formatters.money(Money(cents: .max), hideCents: true, locale: Self.posix).hasPrefix("$92,233,720,368,547,758"))
  }

  @Test("remaining is clamped to $0; estimates read ≈ $42 ± 3")
  func remainingAndEstimate() {
    #expect(Formatters.remaining(Money(cents: -1234), hideCents: true, locale: Self.posix) == "$0")
    #expect(Formatters.remaining(Money(cents: 4200), hideCents: true, locale: Self.posix) == "$42")
    #expect(Formatters.estimate(Money(cents: 4200), bandCents: 300, hideCents: true, locale: Self.posix) == "\u{2248} $42 \u{00B1} 3")
    #expect(Formatters.estimate(Money(cents: 4217), bandCents: 305, hideCents: false, locale: Self.german) == "\u{2248} $42,17 \u{00B1} 3,05")
    #expect(Formatters.estimate(Money(cents: -1, currency: .cny), bandCents: -150, hideCents: true, locale: Self.posix) == "\u{2248} CN¥0 \u{00B1} 2")
  }

  @Test("runway thresholds of 05, floored")
  func runway() {
    let hour: TimeInterval = 3600
    let day = 24 * hour
    let cases: [(TimeInterval?, String?)] = [
      (nil, nil), (.infinity, nil), (.nan, nil), (0, "< 1 h"), (hour - 1, "< 1 h"), (hour, "1 h"),
      (47.9 * hour, "47 h"), (48 * hour, "~2 d"), (12.9 * day, "~12 d"), (59.99 * day, "~59 d"),
      (60 * day, "> 60 d"), (400 * day, "> 60 d")
    ]
    for (seconds, text) in cases { #expect(Formatters.runway(seconds) == text, "\(String(describing: seconds))") }
  }

  @Test("two paces: both, either, neither (05)")
  func runwayPair() {
    let day: TimeInterval = 86_400
    #expect(Formatters.runwayPair(sevenDay: 12 * day, today: 9 * day) == "~12 d \u{00B7} ~9 d today")
    #expect(Formatters.runwayPair(sevenDay: 12 * day, today: nil) == "~12 d")
    #expect(Formatters.runwayPair(sevenDay: nil, today: 5 * 3600) == "5 h today")
    #expect(Formatters.runwayPair(sevenDay: nil, today: nil) == nil)
  }

  @Test("tokens: three significant digits with k/M/B, no 1000k")
  func tokens() {
    let cases: [(count: Int64, texts: [String])] = [
      (0, ["0", "0"]), (842, ["842", "842"]), (999, ["999", "999"]), (1000, ["1.00k", "1,00k"]), (1234, ["1.23k", "1,23k"]),
      (9994, ["9.99k", "9,99k"]), (9995, ["10.0k", "10,0k"]), (12_345, ["12.3k", "12,3k"]), (99_950, ["100k", "100k"]),
      (212_000, ["212k", "212k"]), (999_499, ["999k", "999k"]), (999_500, ["1.00M", "1,00M"]),
      (1_530_000, ["1.53M", "1,53M"]), (2_000_000_000, ["2.00B", "2,00B"]), (-842, ["-842", "-842"]),
      (-1_530_000, ["-1.53M", "-1,53M"]), (5_000_000_000_000_000, ["5000T", "5000T"])
    ]
    for (count, texts) in cases {
      #expect(Formatters.tokens(count, locale: Self.posix) == texts[0], "\(count)")
      #expect(Formatters.tokens(count, locale: Self.german) == texts[1], "\(count)")
    }
    #expect(Formatters.tokens(.max, locale: Self.posix).hasSuffix("T"))
    #expect(Formatters.tokens(.min, locale: Self.posix).hasPrefix("-"))
  }

  @Test("clock time: HH:mm, 24-hour, zero-padded, in the calendar's zone (08 Paused · resumes 14:30)")
  func clockTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zagreb") ?? .gmt
    let date = Date(timeIntervalSince1970: 1_794_312_000) // 2026-11-10T12:00:00Z = 13:00 in Zagreb
    #expect(Formatters.clockTime(date, calendar: calendar) == "13:00")
    #expect(Formatters.clockTime(date.addingTimeInterval(-12 * 3600 + 5 * 60), calendar: calendar) == "01:05")
    #expect(Formatters.clockTime(date.addingTimeInterval(5400), calendar: calendar) == "14:30")
  }

  @Test("interval: seconds, minutes, hours and mixed")
  func interval() {
    #expect(Formatters.interval(seconds: 30) == "30 s")
    #expect(Formatters.interval(seconds: 60) == "1 min")
    #expect(Formatters.interval(seconds: 300) == "5 min")
    #expect(Formatters.interval(seconds: 3600) == "1 h")
    #expect(Formatters.interval(seconds: 5400) == "1 h 30 min")
    #expect(Formatters.interval(seconds: 86_400) == "24 h")
    #expect(Formatters.interval(seconds: 90) == "1 min 30 s")
  }

  @Test("header freshness: the oldest last success across accounts; never-polled ones left out")
  func refreshedAt() {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    let first = AccountSummary(id: "a", provider: .openai, label: "A", mode: .anchored,
                           freshness: [.usage: new, .keys: old])
    let second = AccountSummary(id: "b", provider: .xai, label: "B", mode: .direct, freshness: [.balance: new])
    let never = AccountSummary(id: "c", provider: .deepseek, label: "C", mode: .direct, freshness: [.balance: nil])
    #expect(AccountSummary.refreshedAt([first, second, never]) == new)
    #expect(AccountSummary.refreshedAt([never]) == nil)
    #expect(AccountSummary.refreshedAt([]) == nil)
  }

  @Test("freshness: just now, minutes, hours, yesterday, date, never, stale")
  func freshness() {
    let now = Self.date(2026, 11, 9, 14, 30)
    let calendar = Self.calendar
    #expect(Formatters.freshness(nil, now: now, calendar: calendar) == "never")
    #expect(Formatters.freshness(now.addingTimeInterval(30), now: now, calendar: calendar) == "just now")
    #expect(Formatters.freshness(now.addingTimeInterval(-59), now: now, calendar: calendar) == "just now")
    #expect(Formatters.freshness(now.addingTimeInterval(-120), now: now, calendar: calendar) == "2 min ago")
    #expect(Formatters.freshness(now.addingTimeInterval(-3599), now: now, calendar: calendar) == "59 min ago")
    #expect(Formatters.freshness(now.addingTimeInterval(-3600), now: now, calendar: calendar) == "1 h ago")
    #expect(Formatters.freshness(now.addingTimeInterval(-86_399), now: now, calendar: calendar) == "23 h ago")
    #expect(Formatters.freshness(Self.date(2026, 11, 8, 9), now: now, calendar: calendar) == "yesterday")
    #expect(Formatters.freshness(Self.date(2026, 11, 2), now: now, calendar: calendar) == "Nov 2")
    #expect(Formatters.freshness(now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar, stale: true) == "stale \u{00B7} 3 h ago")
  }

  @Test("dates: MMM d in the calendar's time zone, English month names")
  func dates() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    let lateEvening = Self.date(2026, 1, 31, 23, 30)  // 22:30 UTC
    #expect(Formatters.date(lateEvening, calendar: Self.calendar) == "Jan 31")
    #expect(Formatters.date(Self.date(2026, 12, 1, 0, 30), calendar: utc) == "Nov 30", "00:30 Zagreb is still Nov 30 in UTC")
    let all = (1...12).map { Formatters.date(Self.date(2026, $0, 9), calendar: Self.calendar) }
    #expect(all == ["Jan 9", "Feb 9", "Mar 9", "Apr 9", "May 9", "Jun 9", "Jul 9", "Aug 9", "Sep 9", "Oct 9", "Nov 9", "Dec 9"])
  }

  @Test("bands order by severity; summary picks the latest success")
  func modelBasics() {
    #expect(Band.allCases.max() == .critical)
    #expect(Band.unknown > .watch && Band.unknown < .low)
    #expect(Band.healthy.word == "healthy")
    #expect(Currency.usd.symbol == "$" && Currency.cny.symbol == "CN¥")
    #expect(BalanceMode.spendOnly.rawValue == "spend_only")
    var summary = AccountSummary(id: "a", provider: .openai, label: "OpenAI", mode: .anchored)
    #expect(summary.lastSuccessAt == nil)
    summary.freshness = [.usage: Self.date(2026, 11, 9, 10), .cost: nil, .keys: Self.date(2026, 11, 9, 11)]
    #expect(summary.lastSuccessAt == Self.date(2026, 11, 9, 11))
    #expect(AppSpend(appName: "harness", cents: 40) == AppSpend(appName: "harness", cents: 40))
    #expect(AutoReload(belowCents: 1000, toCents: 5000).toCents == 5000)
  }
}

/// `ui.popover_open` / `ui.popover_close {dur_ms}` (07), debug level.
@MainActor @Suite struct PopoverTrackerTests {
  @Test("open then close logs both events with a duration; repeats are ignored")
  func session() async throws {
    let sink = CapturingLogSink()
    let pipeline = LogPipeline(sinks: [sink], minimumLevel: .debug, version: "test")
    pipeline.startConsumer()
    let tracker = PopoverTracker(logPipeline: pipeline)
    tracker.closed()
    tracker.opened()
    tracker.opened()
    #expect(tracker.isOpen)
    try await Task.sleep(for: .milliseconds(20))
    tracker.closed()
    tracker.closed()
    #expect(!tracker.isOpen)
    await pipeline.drain()
    let records = await sink.records
    #expect(records.map(\.evt) == [.uiPopoverOpen, .uiPopoverClose])
    #expect(records.allSatisfy { $0.lvl == .debug && $0.cat == .ui })
    if case .int(let millis) = records.last?.ctx["dur_ms"] { #expect(millis >= 20) } else { Issue.record("dur_ms missing") }
    #expect((records.last?.durMs ?? 0) >= 20)
  }
}
