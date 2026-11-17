import Foundation

/// What VoiceOver reads for a number (08 § Accessibility: `Remaining, approximately 42 dollars, plus or minus 3`).
/// The screen's symbols become words: `≈` → `approximately`, `±` → `plus or minus`, `$` → `dollars`,
/// `CN¥` → `yuan`, `~12 d` → `about 12 days`. The view puts its title (`Remaining`) in the accessibility label
/// and this text in the value, so VoiceOver reads them joined by a comma. Digits and separators are those of
/// `Formatters` (the locale's), so the spoken figure is the figure on screen, and like the screen the band has no
/// unit. Amounts are cents (12 § R7).
public enum Spoken {
  /// `42 dollars`, `42.17 dollars`, `1 dollar`, `minus 5 dollars`; `yuan` for CNY (one word for one or many).
  public static func money(_ amount: Money, hideCents: Bool, locale: Locale) -> String {
    let magnitude = Formatters.magnitude(Formatters.absolute(amount.cents), hideCents: hideCents, locale: locale)
    let sign = amount.cents < 0 ? "minus " : ""
    return sign + magnitude + " " + unit(amount.currency, one: magnitude == "1")
  }

  /// A remaining balance, clamped to zero as on screen (`Formatters.remaining`).
  public static func remaining(_ amount: Money, hideCents: Bool, locale: Locale) -> String {
    money(Money(cents: max(0, amount.cents), currency: amount.currency), hideCents: hideCents, locale: locale)
  }

  /// `approximately 42 dollars, plus or minus 3` (08 § Accessibility).
  public static func estimate(_ amount: Money, bandCents: Int64, hideCents: Bool, locale: Locale) -> String {
    "approximately \(remaining(amount, hideCents: hideCents, locale: locale)), plus or minus "
      + Formatters.magnitude(Formatters.absolute(bandCents), hideCents: hideCents, locale: locale)
  }

  /// `42.17 dollars`, or `approximately 42.17 dollars` when any of it is a usage estimate (Q-040).
  public static func spend(_ figure: SpendFigure, currency: Currency, hideCents: Bool, locale: Locale) -> String {
    let amount = money(Money(cents: figure.cents, currency: currency), hideCents: hideCents, locale: locale)
    return figure.isEstimate ? "approximately \(amount)" : amount
  }

  /// `approximately 3.10 dollars`; `none` where the screen shows `—` (no priced model gave a rate).
  public static func unpriced(_ figure: UnpricedFigure, currency: Currency, hideCents: Bool, locale: Locale) -> String {
    guard let cents = figure.cents else { return none }
    return "approximately " + money(Money(cents: cents, currency: currency), hideCents: hideCents, locale: locale)
  }

  /// 05's runway steps in words: `less than 1 hour`, `1 hour`, `5 hours`, `about 12 days`, `more than 60 days`.
  public static func runway(_ seconds: TimeInterval?) -> String? {
    guard let seconds, seconds.isFinite else { return nil }
    let hours = seconds / 3600
    if hours < 1 { return "less than 1 hour" }
    if hours < 48 { return Int(hours) == 1 ? "1 hour" : "\(Int(hours)) hours" }
    let days = hours / 24
    if days < 60 { return "about \(Int(days)) days" }
    return "more than 60 days"
  }

  /// The two paces (`~12 d · ~9 d today`): `about 12 days, about 9 days at today's pace`.
  public static func runwayPair(sevenDay: TimeInterval?, today: TimeInterval?) -> String? {
    switch (runway(sevenDay), runway(today)) {
    case let (week?, day?): "\(week), \(day) at today's pace"
    case let (week?, nil): week
    case let (nil, day?): "\(day) at today's pace"
    case (nil, nil): nil
    }
  }

  /// What VoiceOver reads for the screen's `—`.
  public static let none = "none"

  private static func unit(_ currency: Currency, one: Bool) -> String {
    switch currency {
    case .usd: one ? "dollar" : "dollars"
    case .cny: "yuan"
    }
  }
}
