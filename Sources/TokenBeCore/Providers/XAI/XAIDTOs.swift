import Foundation

// xAI response bodies (02 § xai). `GET /v1/api-key` returns key metadata; secondary sources report the balance
// fields `remaining_balance`, `spent_balance` and `total_granted` (USD), all `[expected]` until a recording confirms
// them (H3, D-xai-balance). Decoding is lenient: key metadata 02 does not list is collected as unknown keys.

/// `GET /v1/api-key`. Only `remaining_balance` is read: a JSON number of US dollars (02). Absent or null → nil.
/// Present with another type fails as `PollError.decode(field: "remaining_balance", …)`; the probe reads that as
/// "no usable balance" (D-xai-balance), a poll as schema drift.
struct XAIAPIKey: Decodable, Equatable {
  var remainingBalance: Decimal?

  enum CodingKeys: String, CodingKey, CaseIterable {
    case remainingBalance = "remaining_balance"
    case spentBalance = "spent_balance"
    case totalGranted = "total_granted"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    remainingBalance = try container.decodeIfPresent(Decimal.self, forKey: .remainingBalance)
  }
}
