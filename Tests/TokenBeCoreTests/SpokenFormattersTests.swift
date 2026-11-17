import Foundation
import Testing
@testable import TokenBeCore

/// 08 § Accessibility: what VoiceOver reads for each number, pinned to `en_US_POSIX` and `de_DE` like
/// `FormattersTests`. The view's label (`Remaining`) and this value are read joined by a comma.
@Suite struct SpokenFormattersTests {
  static let posix = Locale(identifier: "en_US_POSIX")
  static let german = Locale(identifier: "de_DE")

  @Test("08's sentence: `Remaining, approximately 42 dollars, plus or minus 3`")
  func estimateSentence() {
    let value = Spoken.estimate(Money(cents: 4_200), bandCents: 300, hideCents: true, locale: Self.posix)
    #expect(value == "approximately 42 dollars, plus or minus 3")
    #expect("Remaining, " + value == "Remaining, approximately 42 dollars, plus or minus 3")
    #expect(Spoken.estimate(Money(cents: 4_217), bandCents: 312, hideCents: false, locale: Self.german)
      == "approximately 42,17 dollars, plus or minus 3,12")
    // Clamped to zero like the screen's `≈ $0 ± 3`.
    #expect(Spoken.estimate(Money(cents: -500), bandCents: 300, hideCents: true, locale: Self.posix)
      == "approximately 0 dollars, plus or minus 3")
  }

  @Test("money: the screen's digits, `dollar(s)` or `yuan`, `minus` for a negative amount")
  func money() {
    #expect(Spoken.money(Money(cents: 4_217), hideCents: false, locale: Self.posix) == "42.17 dollars")
    #expect(Spoken.money(Money(cents: 4_250), hideCents: true, locale: Self.posix) == "43 dollars")
    #expect(Spoken.money(Money(cents: 100), hideCents: true, locale: Self.posix) == "1 dollar")
    #expect(Spoken.money(Money(cents: 100), hideCents: false, locale: Self.posix) == "1.00 dollars")
    #expect(Spoken.money(Money(cents: -500), hideCents: true, locale: Self.posix) == "minus 5 dollars")
    #expect(Spoken.money(Money(cents: 123_456_700, currency: .cny), hideCents: true, locale: Self.german)
      == "1.234.567 yuan")
    #expect(Spoken.remaining(Money(cents: -500), hideCents: true, locale: Self.posix) == "0 dollars")
  }

  @Test("spend and unpriced: `approximately` where the screen has `≈`, `none` where it has `—`")
  func spendAndUnpriced() {
    #expect(Spoken.spend(SpendFigure(cents: 4_217, isEstimate: false), currency: .usd, hideCents: false,
                         locale: Self.posix) == "42.17 dollars")
    #expect(Spoken.spend(SpendFigure(cents: 4_217, isEstimate: true), currency: .cny, hideCents: true,
                         locale: Self.posix) == "approximately 42 yuan")
    #expect(Spoken.unpriced(UnpricedFigure(tokens: 5, cents: 310), currency: .usd, hideCents: false,
                            locale: Self.posix) == "approximately 3.10 dollars")
    #expect(Spoken.unpriced(UnpricedFigure(tokens: 5, cents: nil), currency: .usd, hideCents: false,
                            locale: Self.posix) == Spoken.none)
  }

  @Test("runway: 05's steps in words, the same floors as `Formatters.runway`")
  func runway() {
    let hour: TimeInterval = 3_600
    #expect(Spoken.runway(nil) == nil)
    #expect(Spoken.runway(.infinity) == nil)
    #expect(Spoken.runway(0.5 * hour) == "less than 1 hour")
    #expect(Spoken.runway(1.5 * hour) == "1 hour")
    #expect(Spoken.runway(47.9 * hour) == "47 hours")
    #expect(Spoken.runway(48 * hour) == "about 2 days")
    #expect(Spoken.runway(59.9 * 24 * hour) == "about 59 days")
    #expect(Spoken.runway(60 * 24 * hour) == "more than 60 days")
    #expect(Spoken.runwayPair(sevenDay: 12 * 24 * hour, today: 9 * 24 * hour)
      == "about 12 days, about 9 days at today's pace")
    #expect(Spoken.runwayPair(sevenDay: 12 * 24 * hour, today: nil) == "about 12 days")
    #expect(Spoken.runwayPair(sevenDay: nil, today: 5 * hour) == "5 hours at today's pace")
    #expect(Spoken.runwayPair(sevenDay: nil, today: nil) == nil)
  }
}
