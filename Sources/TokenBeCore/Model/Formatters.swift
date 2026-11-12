import Foundation

/// Every number, amount, runway and time the UI shows (08 § Formatting rules, 05 § Runway formatting).
/// Pure functions: locale, clock and calendar are parameters, so output never depends on the machine
/// (tests pin `en_US_POSIX` and `de_DE`). Only separators come from the locale; the text is English (O-9).
/// Money and tokens use integer arithmetic only (12 § R7).
public enum Formatters {
  public static let approx = "\u{2248}"  // ≈
  public static let plusMinus = "\u{00B1}"  // ±
  public static let dot = "\u{00B7}"  // ·

  // MARK: - Money

  /// `$42` (cents hidden, rounded half up) or `$42.17`; `CN¥` for CNY; negative amounts as `-$5`.
  public static func money(_ amount: Money, hideCents: Bool, locale: Locale) -> String {
    let sign = amount.cents < 0 ? "-" : ""
    return sign + amount.currency.symbol + magnitude(absolute(amount.cents), hideCents: hideCents, locale: locale)
  }

  /// Remaining balance: negative values are clamped to zero (08; the band is forced `critical` elsewhere).
  public static func remaining(_ amount: Money, hideCents: Bool, locale: Locale) -> String {
    money(Money(cents: max(0, amount.cents), currency: amount.currency), hideCents: hideCents, locale: locale)
  }

  /// An estimate with its band: `≈ $42 ± 3` (08); the band has no currency symbol.
  public static func estimate(_ amount: Money, bandCents: Int64, hideCents: Bool, locale: Locale) -> String {
    "\(approx) \(remaining(amount, hideCents: hideCents, locale: locale)) \(plusMinus) "
      + magnitude(absolute(bandCents), hideCents: hideCents, locale: locale)
  }

  /// Non-negative cents without a symbol: whole units (half up) or units plus two decimals, grouped per locale.
  static func magnitude(_ cents: Int64, hideCents: Bool, locale: Locale) -> String {
    if hideCents { return grouped(roundedQuotient(cents, 100), locale: locale) }
    let fraction = cents % 100
    return grouped(cents / 100, locale: locale) + decimalSeparator(locale) + (fraction < 10 ? "0" : "") + String(fraction)
  }

  // MARK: - Runway

  /// 05: `< 1 h`, `N h` below 48 h, `~N d` below 60 d, `> 60 d`. Values are floored. Nil stays nil.
  /// A typed amount (`200`, `200.5`, `1,234.56` in `locale`) → cents, rounded half up; nil when it is not a
  /// non-negative number. Parsing lives here because `Decimal` is allowed only in `Formatters` (R7).
  public static func cents(fromInput text: String, locale: Locale) -> Int64? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.generatesDecimalNumbers = true
    guard let number = formatter.number(from: trimmed) as? NSDecimalNumber else { return nil }
    var scaled = number.decimalValue * 100
    guard scaled >= 0 else { return nil }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).int64Value
  }

  public static func runway(_ seconds: TimeInterval?) -> String? {
    guard let seconds, seconds.isFinite else { return nil }
    let hours = seconds / 3600
    if hours < 1 { return "< 1 h" }
    if hours < 48 { return "\(Int(hours)) h" }
    let days = hours / 24
    if days < 60 { return "~\(Int(days)) d" }
    return "> 60 d"
  }

  /// The popover's two paces (05): `~12 d · ~9 d today` when both exist, else the one that exists.
  public static func runwayPair(sevenDay: TimeInterval?, today: TimeInterval?) -> String? {
    switch (runway(sevenDay), runway(today)) {
    case let (week?, day?): "\(week) \(dot) \(day) today"
    case let (week?, nil): week
    case let (nil, day?): "\(day) today"
    case (nil, nil): nil
    }
  }

  // MARK: - Tokens

  /// `842`, `212k`, `1.53M`: three significant digits, rounded half up, decimal separator per locale.
  public static func tokens(_ count: Int64, locale: Locale) -> String {
    if count < 0 { return "-" + tokens(count == .min ? .max : -count, locale: locale) }
    if count < 1000 { return String(count) }
    let suffixes = ["k", "M", "B", "T"]
    var unit: Int64 = 1
    for (index, suffix) in suffixes.enumerated() {
      unit *= 1000
      let last = index == suffixes.count - 1
      var decimals = count >= 100 * unit ? 0 : (count >= 10 * unit ? 1 : 2)
      while true {
        let scale: Int64 = decimals == 2 ? 100 : (decimals == 1 ? 10 : 1)
        let (scaled, overflow) = count.multipliedReportingOverflow(by: scale)
        guard !overflow else {
          decimals = 0
          continue
        }
        let rounded = roundedQuotient(scaled, unit)
        if rounded < 1000 || (decimals == 0 && last) {
          let whole = rounded / scale
          guard decimals > 0 else { return String(whole) + suffix }
          let fraction = String(rounded % scale)
          let padded = String(repeating: "0", count: decimals - fraction.count) + fraction
          return String(whole) + decimalSeparator(locale) + padded + suffix
        }
        if decimals == 0 { break }
        decimals -= 1
      }
    }
    return String(count)
  }

  // MARK: - Time

  /// `just now` (< 60 s), `N min ago`, `N h ago` (< 24 h), `yesterday`, then the date (`Nov 9`); `never` for nil.
  /// Stale freshness reads `stale · 3 h ago` (08); the caller colours it `HealthLow`.
  public static func freshness(_ date: Date?, now: Date, calendar: Calendar, stale: Bool = false) -> String {
    guard let date else { return "never" }
    let text: String
    let elapsed = now.timeIntervalSince(date)
    if elapsed < 60 {
      text = "just now"
    } else if elapsed < 3600 {
      text = "\(Int(elapsed / 60)) min ago"
    } else if elapsed < 86_400 {
      text = "\(Int(elapsed / 3600)) h ago"
    } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(date, inSameDayAs: yesterday) {
      text = "yesterday"
    } else {
      text = self.date(date, calendar: calendar)
    }
    return stale ? "stale \(dot) \(text)" : text
  }

  /// `HH:mm`, 24-hour, in the calendar's time zone: `Paused · resumes 14:30` (08).
  public static func clockTime(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let hour = parts.hour ?? 0
    let minute = parts.minute ?? 0
    return (hour < 10 ? "0" : "") + "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
  }

  /// Time until a job's next run, for the Sources strip's `next 3 min` (08 `HP-0`): whole minutes rounded up
  /// (`3 min`, `1 h 5 min`), seconds under a minute (`42 s`), `now` once due (Q-036).
  public static func untilNextRun(_ due: Date, now: Date) -> String {
    let remaining = due.timeIntervalSince(now)
    guard remaining >= 1 else { return "now" }
    guard remaining >= 60 else { return "\(Int(remaining)) s" }
    return interval(seconds: Int((remaining / 60).rounded(.up)) * 60)
  }

  /// A polling period: `30 s`, `5 min`, `1 h`, `1 h 30 min` (Sources tab, Q-034).
  public static func interval(seconds: Int) -> String {
    guard seconds >= 60 else { return "\(seconds) s" }
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let rest = seconds % 60
    var parts: [String] = []
    if hours > 0 { parts.append("\(hours) h") }
    if minutes > 0 { parts.append("\(minutes) min") }
    if rest > 0 { parts.append("\(rest) s") }
    return parts.joined(separator: " ")
  }

  private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  /// `MMM d` in the calendar's time zone (08), English month names (O-9).
  public static func date(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.month, .day], from: date)
    let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
    return "\(month) \(parts.day ?? 1)"
  }

  // MARK: - Integer helpers

  /// `value / divisor` rounded half up, for non-negative values, without overflow.
  static func roundedQuotient(_ value: Int64, _ divisor: Int64) -> Int64 {
    let quotient = value / divisor
    return value % divisor >= divisor - divisor / 2 ? quotient + 1 : quotient
  }

  /// `abs` that cannot trap: `Int64.min` maps to `Int64.max`.
  static func absolute(_ value: Int64) -> Int64 { value == .min ? .max : abs(value) }

  // MARK: - Separators

  static func decimalSeparator(_ locale: Locale) -> String { locale.decimalSeparator ?? "." }

  /// Groups thousands with the locale's separator (none if the locale has none).
  static func grouped(_ value: Int64, locale: Locale) -> String {
    let digits = Array(String(value))
    let separator = locale.groupingSeparator ?? ""
    guard digits.count > 3, !separator.isEmpty else { return String(digits) }
    var out = ""
    for (index, digit) in digits.enumerated() {
      if index > 0, (digits.count - index) % 3 == 0 { out += separator }
      out.append(digit)
    }
    return out
  }
}
