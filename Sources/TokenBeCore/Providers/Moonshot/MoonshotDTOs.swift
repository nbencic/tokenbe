import Foundation

// Moonshot response bodies (02 § moonshot). Field names come only from 02 (R2) until H6 records them. Decoding is
// lenient like DeepSeek's: a key 02 does not list is collected, not fatal; a missing or malformed required field
// fails as `PollError.decode(field:path:)`.

/// `GET /v1/users/me/balance` → `{ "code": 0, "data": { … }, "scode": "0x0", "status": true }`. Amounts are JSON
/// numbers in the region's currency (CNY on `api.moonshot.cn`, USD on `api.moonshot.ai`), read exactly as `Decimal`.
struct MoonshotBalance: Decodable, Equatable {
  var code: Int
  var status: Bool
  var availableCents: Int64
  var voucherCents: Int64
  var cashCents: Int64

  enum CodingKeys: String, CodingKey, CaseIterable {
    case code, data, scode, status
  }

  enum DataKeys: String, CodingKey, CaseIterable {
    case availableBalance = "available_balance"
    case voucherBalance = "voucher_balance"
    case cashBalance = "cash_balance"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    code = try container.decode(Int.self, forKey: .code)
    status = try container.decode(Bool.self, forKey: .status)
    let data = try container.superDecoder(forKey: .data)
    let amounts = try LenientDecoding.container(data, DataKeys.self)
    availableCents = MinorUnits.cents(try amounts.decode(Decimal.self, forKey: .availableBalance))
    voucherCents = MinorUnits.cents(try amounts.decode(Decimal.self, forKey: .voucherBalance))
    cashCents = MinorUnits.cents(try amounts.decode(Decimal.self, forKey: .cashBalance))
  }
}
