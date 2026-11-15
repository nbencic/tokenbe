import Foundation

// DeepSeek response bodies (02 § deepseek). Field names come only from 02 (R2) until a recording confirms them
// (H3). Decoding is lenient like OpenAI's: a key 02 does not list is collected, not fatal; a missing or malformed
// required field fails as `PollError.decode(field:path:)`.

/// `GET /user/balance`: `{ "is_available": bool, "balance_infos": [ … ] }`.
struct DeepSeekBalance: Decodable, Equatable {
  var isAvailable: Bool
  var balanceInfos: [DeepSeekBalanceInfo]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case isAvailable = "is_available"
    case balanceInfos = "balance_infos"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
    balanceInfos = try container.decode([DeepSeekBalanceInfo].self, forKey: .balanceInfos)
    // No entry means no balance to show: a failure, never a successful poll that writes nothing (Q-045).
    guard !balanceInfos.isEmpty else {
      throw DecodingError.dataCorruptedError(forKey: .balanceInfos, in: container,
                                             debugDescription: "balance_infos is empty")
    }
  }
}

/// One currency's balance. Amounts are strings (`"110.00"`, 02), parsed strictly into cents.
struct DeepSeekBalanceInfo: Decodable, Equatable {
  /// `CNY` or `USD` (02), kept as sent: the snapshot column has no CHECK, so a currency 02 does not list is stored,
  /// not fatal (Q-045).
  var currency: String
  var totalCents: Int64
  var grantedCents: Int64?
  var toppedUpCents: Int64?

  enum CodingKeys: String, CodingKey, CaseIterable {
    case currency
    case totalBalance = "total_balance"
    case grantedBalance = "granted_balance"
    case toppedUpBalance = "topped_up_balance"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    currency = try container.decode(String.self, forKey: .currency).uppercased()
    totalCents = try Self.cents(container, .totalBalance, text: container.decode(String.self, forKey: .totalBalance))
    grantedCents = try container.decodeIfPresent(String.self, forKey: .grantedBalance).map {
      try Self.cents(container, .grantedBalance, text: $0)
    }
    toppedUpCents = try container.decodeIfPresent(String.self, forKey: .toppedUpBalance).map {
      try Self.cents(container, .toppedUpBalance, text: $0)
    }
  }

  static func cents(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, text: String) throws -> Int64 {
    guard let amount = MinorUnits.decimal(text) else {
      throw DecodingError.dataCorruptedError(forKey: key, in: container,
                                             debugDescription: "not a decimal amount")
    }
    return MinorUnits.cents(amount)
  }
}
