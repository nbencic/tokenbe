import Foundation

// Novita response bodies (02 § novita). Field names come only from 02 (R2) until H6 records them. Decoding is lenient
// like DeepSeek's: a key 02 does not list is collected, not fatal; a missing or malformed required field fails as
// `PollError.decode(field:path:)`.

/// `GET /openapi/v1/billing/balance/detail` → `{ "availableBalance": "1000000", "cashBalance": "800000",
/// "creditLimit": "200000", "pendingCharges": "0", "outstandingInvoices": "0" }`: strings in 1/10000 USD
/// (`"10000"` = $1.00), parsed strictly and rounded to cents once (05 § Currency).
struct NovitaBalance: Decodable, Equatable {
  var availableCents: Int64
  var cashCents: Int64

  enum CodingKeys: String, CodingKey, CaseIterable {
    case availableBalance, cashBalance, creditLimit, pendingCharges, outstandingInvoices
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    availableCents = try Self.cents(container, .availableBalance)
    cashCents = try Self.cents(container, .cashBalance)
  }

  /// `"1234567"` (1/10000 USD) → 12_346 cents: ÷ 100, half away from zero (05).
  static func cents(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Int64 {
    let text = try container.decode(String.self, forKey: key)
    guard let units = MinorUnits.decimal(text) else {
      throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "not a decimal amount")
    }
    return MinorUnits.cents(units / 10_000)
  }
}
