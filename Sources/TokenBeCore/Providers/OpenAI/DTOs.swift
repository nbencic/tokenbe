import Foundation
import Synchronization

// OpenAI response bodies (02 § openai). Field names come only from 02 (R2); every one is still `[expected]` until
// 3.6 records fixtures. Decoding is lenient: a key 02 does not list is collected, not fatal. A missing required
// field fails as `PollError.decode(field:path:)`.

/// `GET /v1/organization/projects` (probe step 1): `data[]` with `id` and `name`.
struct OpenAIProjectList: Decodable, Equatable {
  var data: [OpenAIProject]

  enum CodingKeys: String, CodingKey, CaseIterable { case data }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    data = try container.decode([OpenAIProject].self, forKey: .data)
  }
}

struct OpenAIProject: Decodable, Equatable {
  var id: String
  var name: String?

  enum CodingKeys: String, CodingKey, CaseIterable { case id, name }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name)
  }
}

/// `GET /v1/organization/projects/{project_id}/api_keys` (probe step 2): `data[]` of `OpenAIAPIKey`.
struct OpenAIAPIKeyList: Decodable, Equatable {
  var data: [OpenAIAPIKey]

  enum CodingKeys: String, CodingKey, CaseIterable { case data }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    data = try container.decode([OpenAIAPIKey].self, forKey: .data)
  }
}

/// `id`, `name`, `redacted_value`, `created_at`, `last_used_at` (02).
struct OpenAIAPIKey: Decodable, Equatable {
  var id: String
  var name: String?
  var redactedValue: String?
  var createdAt: Int64?
  var lastUsedAt: Int64?

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id, name
    case redactedValue = "redacted_value"
    case createdAt = "created_at"
    case lastUsedAt = "last_used_at"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    redactedValue = try container.decodeIfPresent(String.self, forKey: .redactedValue)
    createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
    lastUsedAt = try container.decodeIfPresent(Int64.self, forKey: .lastUsedAt)
  }
}

/// The page shape of 02 § Usage, also used by the Costs endpoint (Q-029):
/// `{ "object":"page", "data":[ { "object":"bucket", "start_time", "end_time", "results":[…] } ], "has_more",
/// "next_page" }`.
struct OpenAIPage<Result: Decodable & Equatable>: Decodable, Equatable {
  var data: [OpenAIBucket<Result>]
  var hasMore: Bool
  var nextPage: String?

  enum CodingKeys: String, CodingKey, CaseIterable {
    case object, data
    case hasMore = "has_more"
    case nextPage = "next_page"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    data = try container.decode([OpenAIBucket<Result>].self, forKey: .data)
    hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    nextPage = try container.decodeIfPresent(String.self, forKey: .nextPage)
  }

  /// The next page's cursor, only while `has_more` is true and `next_page` is a non-empty string.
  var cursor: String? {
    guard hasMore, let nextPage, !nextPage.isEmpty else { return nil }
    return nextPage
  }
}

struct OpenAIBucket<Result: Decodable & Equatable>: Decodable, Equatable {
  var startTime: Int64
  var endTime: Int64
  var results: [Result]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case object
    case startTime = "start_time"
    case endTime = "end_time"
    case results
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    startTime = try container.decode(Int64.self, forKey: .startTime)
    endTime = try container.decode(Int64.self, forKey: .endTime)
    results = try container.decode([Result].self, forKey: .results)
  }
}

/// One result of 02 § Usage. Its unknown keys are logged as `normalize.unknown_keys` (05), not `poll.unknown_keys`.
struct OpenAIUsageResult: Decodable, Equatable {
  /// INCLUDES cached tokens (02).
  var inputTokens: Int64
  var inputCachedTokens: Int64
  /// May be absent → 0 (02).
  var inputCacheWriteTokens: Int64?
  var outputTokens: Int64
  var inputAudioTokens: Int64?
  var outputAudioTokens: Int64?
  var numModelRequests: Int64?
  var projectID: String?
  var userID: String?
  var apiKeyID: String?
  var model: String?
  var batch: Bool?
  var serviceTier: String?

  enum CodingKeys: String, CodingKey, CaseIterable {
    case inputTokens = "input_tokens"
    case inputCachedTokens = "input_cached_tokens"
    case inputCacheWriteTokens = "input_cache_write_tokens"
    case outputTokens = "output_tokens"
    case inputAudioTokens = "input_audio_tokens"
    case outputAudioTokens = "output_audio_tokens"
    case numModelRequests = "num_model_requests"
    case projectID = "project_id"
    case userID = "user_id"
    case apiKeyID = "api_key_id"
    case model, batch
    case serviceTier = "service_tier"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self, usage: true)
    inputTokens = try container.decode(Int64.self, forKey: .inputTokens)
    inputCachedTokens = try container.decode(Int64.self, forKey: .inputCachedTokens)
    inputCacheWriteTokens = try container.decodeIfPresent(Int64.self, forKey: .inputCacheWriteTokens)
    outputTokens = try container.decode(Int64.self, forKey: .outputTokens)
    inputAudioTokens = try container.decodeIfPresent(Int64.self, forKey: .inputAudioTokens)
    outputAudioTokens = try container.decodeIfPresent(Int64.self, forKey: .outputAudioTokens)
    numModelRequests = try container.decodeIfPresent(Int64.self, forKey: .numModelRequests)
    projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
    userID = try container.decodeIfPresent(String.self, forKey: .userID)
    apiKeyID = try container.decodeIfPresent(String.self, forKey: .apiKeyID)
    model = try container.decodeIfPresent(String.self, forKey: .model)
    batch = try container.decodeIfPresent(Bool.self, forKey: .batch)
    serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
  }
}

/// One result of 02 § Cost: `object`, `amount { value, currency }`, `line_item`, `project_id`, `api_key_id`,
/// `api_source`. `value` decodes as `Decimal` from the JSON text, never through `Double` (R7).
struct OpenAICostResult: Decodable, Equatable {
  var amount: OpenAICostAmount
  var lineItem: String?
  var projectID: String?
  var apiKeyID: String?
  var apiSource: String?

  enum CodingKeys: String, CodingKey, CaseIterable {
    case object, amount
    case lineItem = "line_item"
    case projectID = "project_id"
    case apiKeyID = "api_key_id"
    case apiSource = "api_source"
  }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    amount = try container.decode(OpenAICostAmount.self, forKey: .amount)
    lineItem = try container.decodeIfPresent(String.self, forKey: .lineItem)
    projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
    apiKeyID = try container.decodeIfPresent(String.self, forKey: .apiKeyID)
    apiSource = try container.decodeIfPresent(String.self, forKey: .apiSource)
  }
}

struct OpenAICostAmount: Decodable, Equatable {
  var value: Decimal
  var currency: String

  enum CodingKeys: String, CodingKey, CaseIterable { case value, currency }

  init(from decoder: any Decoder) throws {
    let container = try LenientDecoding.container(decoder, CodingKeys.self)
    value = try container.decode(Decimal.self, forKey: .value)
    currency = try container.decode(String.self, forKey: .currency)
  }
}

// MARK: - Lenient decoding

/// What one decode found besides the DTO: keys 02 does not list, as paths like `data[].results[].new_field`.
struct DecodedBody<Value> {
  var value: Value
  /// Outside usage results → `poll.unknown_keys`.
  var unknownKeys: [String]
  /// Inside usage results → `normalize.unknown_keys` (05).
  var unknownUsageKeys: [String]
}

enum LenientDecoding {
  /// Collects unknown keys during one decode. Decoding is synchronous; the lock only satisfies `Sendable`.
  final class Collector: Sendable {
    private let found = Mutex<(general: Set<String>, usage: Set<String>)>(([], []))

    func note(_ paths: [String], usage: Bool) {
      found.withLock { current in
        if usage { current.usage.formUnion(paths) } else { current.general.formUnion(paths) }
      }
    }

    var general: [String] { found.withLock { $0.general.sorted() } }
    var usage: [String] { found.withLock { $0.usage.sorted() } }
  }

  struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
      self.stringValue = String(intValue)
      self.intValue = intValue
    }
  }

  static let collectorKey = CodingUserInfoKey(rawValue: "dev.bathyon.tokenbe.unknownKeys")

  /// The keyed container for `Keys`, after noting every key of the object that `Keys` does not list.
  static func container<Keys: CodingKey & CaseIterable>(
    _ decoder: any Decoder, _ keys: Keys.Type, usage: Bool = false
  ) throws -> KeyedDecodingContainer<Keys> {
    if let collectorKey, let collector = decoder.userInfo[collectorKey] as? Collector {
      let known = Set(Keys.allCases.map(\.stringValue))
      let all = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
      let prefix = path(decoder.codingPath)
      let unknown = all.filter { !known.contains($0) }.map { prefix.isEmpty ? $0 : "\(prefix).\($0)" }
      if !unknown.isEmpty { collector.note(unknown, usage: usage) }
    }
    return try decoder.container(keyedBy: Keys.self)
  }

  /// `data[].results[]`: array indices collapse to `[]`, so one unknown key is reported once per page.
  static func path(_ codingPath: [any CodingKey]) -> String {
    var text = ""
    for key in codingPath {
      if key.intValue != nil {
        text += "[]"
      } else {
        text += text.isEmpty ? key.stringValue : ".\(key.stringValue)"
      }
    }
    return text
  }

  /// Decodes `data` as `T`. A required field that is missing or of the wrong type fails as
  /// `.decode(field:path:)` with `path` prefixed by `endpoint` (`usage_completions: data[].results[]`).
  static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String)
    throws(PollError) -> DecodedBody<T> {
    let collector = Collector()
    let decoder = JSONDecoder()
    if let collectorKey { decoder.userInfo[collectorKey] = collector }
    do {
      let value = try decoder.decode(T.self, from: data)
      return DecodedBody(value: value, unknownKeys: collector.general, unknownUsageKeys: collector.usage)
    } catch let error as DecodingError {
      throw decodeError(error, endpoint: endpoint)
    } catch {
      throw .decode(field: "body", path: "\(endpoint): \(error)")
    }
  }

  static func decodeError(_ error: DecodingError, endpoint: String) -> PollError {
    switch error {
    case .keyNotFound(let key, let context):
      return .decode(field: key.stringValue, path: located(endpoint, context.codingPath))
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      return .decode(field: context.codingPath.last?.stringValue ?? "body",
                     path: located(endpoint, Array(context.codingPath.dropLast())))
    case .dataCorrupted(let context):
      return .decode(field: context.codingPath.last?.stringValue ?? "body",
                     path: located(endpoint, Array(context.codingPath.dropLast())))
    @unknown default:
      return .decode(field: "body", path: endpoint)
    }
  }

  private static func located(_ endpoint: String, _ codingPath: [any CodingKey]) -> String {
    let inner = path(codingPath)
    return inner.isEmpty ? endpoint : "\(endpoint): \(inner)"
  }
}
