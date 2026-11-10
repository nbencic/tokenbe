import Foundation

/// What a provider's API can tell TokenBe for one account (02 § Capability matrix), found by the probe and stored
/// as `account.capabilities` JSON (03). The JSON keys are pinned by `CodingKeys`, so a Swift rename never breaks
/// stored rows; `usageLag` is stored as whole seconds (Q-028).
public struct Capabilities: Sendable, Equatable, Codable {
  public var usage: Bool
  public var cost: Bool
  public var balance: Bool
  /// Usage (or spend) broken out per provider key (06 § Attribution: provider rows are truth when true).
  public var perKeyUsage: Bool
  /// Provider keys can be listed with their names.
  public var keyNames: Bool
  public var balanceModeDefault: BalanceMode
  /// How long the provider takes to finish counting a bucket (02 `usageLag`).
  public var usageLag: Duration
  public var currencyHint: Currency

  public init(usage: Bool, cost: Bool, balance: Bool, perKeyUsage: Bool, keyNames: Bool,
              balanceModeDefault: BalanceMode, usageLag: Duration, currencyHint: Currency) {
    self.usage = usage
    self.cost = cost
    self.balance = balance
    self.perKeyUsage = perKeyUsage
    self.keyNames = keyNames
    self.balanceModeDefault = balanceModeDefault
    self.usageLag = usageLag
    self.currencyHint = currencyHint
  }

  enum CodingKeys: String, CodingKey {
    case usage, cost, balance
    case perKeyUsage = "per_key_usage"
    case keyNames = "key_names"
    case balanceModeDefault = "balance_mode_default"
    case usageLagSeconds = "usage_lag_s"
    case currencyHint = "currency_hint"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    usage = try container.decode(Bool.self, forKey: .usage)
    cost = try container.decode(Bool.self, forKey: .cost)
    balance = try container.decode(Bool.self, forKey: .balance)
    perKeyUsage = try container.decode(Bool.self, forKey: .perKeyUsage)
    keyNames = try container.decode(Bool.self, forKey: .keyNames)
    balanceModeDefault = try container.decode(BalanceMode.self, forKey: .balanceModeDefault)
    usageLag = .seconds(try container.decode(Int64.self, forKey: .usageLagSeconds))
    currencyHint = try container.decode(Currency.self, forKey: .currencyHint)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(usage, forKey: .usage)
    try container.encode(cost, forKey: .cost)
    try container.encode(balance, forKey: .balance)
    try container.encode(perKeyUsage, forKey: .perKeyUsage)
    try container.encode(keyNames, forKey: .keyNames)
    try container.encode(balanceModeDefault, forKey: .balanceModeDefault)
    try container.encode(usageLag.components.seconds, forKey: .usageLagSeconds)
    try container.encode(currencyHint, forKey: .currencyHint)
  }

  /// The JSON stored in `account.capabilities`: sorted keys, so equal values store equal text.
  public func json() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(bytes: try encoder.encode(self), encoding: .utf8) ?? "{}"
  }

  public static func decode(json: String) throws -> Capabilities {
    try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
  }
}
