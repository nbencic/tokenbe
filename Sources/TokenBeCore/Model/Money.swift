/// Account currency (03: integer minor units with an explicit currency; D-no-currency-conversion).
public enum Currency: String, CaseIterable, Sendable {
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
