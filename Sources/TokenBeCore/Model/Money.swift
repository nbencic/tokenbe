import Foundation

/// Account currency (03: integer minor units with an explicit currency; D-no-currency-conversion).
public enum Currency: String, CaseIterable, Sendable, Codable {
  case usd = "USD"
  case cny = "CNY"

  /// Display prefix (08 § Formatting rules): `$`, and `CN¥` for every non-USD amount in V1.
  public var symbol: String {
    switch self {
    case .usd: "$"
    case .cny: "CN¥"
    }
  }
}

/// An amount in integer minor units (D-integer-money, 12 § R7). Never `Double`.
public struct Money: Sendable, Equatable, Hashable {
  public var cents: Int64
  public var currency: Currency

  public init(cents: Int64, currency: Currency = .usd) {
    self.cents = cents
    self.currency = currency
  }
}

/// Provider amounts in major units → integer cents (05; R7: `Decimal` for the arithmetic, never `Double`).
public enum MinorUnits {
  /// Major units → cents, rounded half up once.
  public static func cents(_ amount: Decimal) -> Int64 {
    var scaled = amount * 100
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).int64Value
  }

  /// A decimal amount sent as a string (02 § deepseek: `"110.00"`): an optional `-`, digits, and an optional `.`
  /// with digits; nothing else. `Decimal(string:)` alone accepts a numeric prefix (`"12abc"` → 12) and follows
  /// the locale's separator, so the whole string is checked first and parsed in `en_US_POSIX` (Q-045).
  public static func decimal(_ text: String) -> Decimal? {
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let whole = parts.first else { return nil }
    let digits = whole.hasPrefix("-") ? whole.dropFirst() : whole[...]
    guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
    if parts.count == 2 {
      guard !parts[1].isEmpty, parts[1].allSatisfy(\.isASCIIDigit) else { return nil }
    }
    return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
  }
}

extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
}
