import Foundation
import Testing
@testable import TokenBeCore

/// 11 `LineParserTests` (14 § Stage 7.2): every rejection reason of 06's v1 table, the key hint and unknown-field
/// rules, and 05's per-response (harness) normalizer rows.
@Suite struct LineParserTests {
  static var valid: [String: Any] { [
    "v": 1, "ts": "2026-11-09T14:03:21.512Z", "provider": "deepseek", "app": "Weather-Collector",
    "key_hint": "\u{2026}a9f2", "request_id": "c7c3e2a4", "model": "deepseek-chat",
    "usage": ["prompt_tokens": 1532, "completion_tokens": 212, "prompt_cache_hit_tokens": 1200,
              "prompt_cache_miss_tokens": 332], "status": "ok"
  ] }

  static func parse(_ object: [String: Any]) -> Result<HarnessLine, LineRejection> {
    do {
      return LineParser.parse(try JSONSerialization.data(withJSONObject: object))
    } catch {
      Issue.record("unserializable test object: \(error)")
      return .failure(.badJSON)
    }
  }

  static func changing(_ key: String, to value: Any?) -> [String: Any] {
    var object = valid
    object[key] = value
    return object
  }

  @Test("06's example line: fields, lowercased app, the key hint's last 4, 05's DeepSeek row")
  func validLine() throws {
    let line = try Self.parse(Self.valid).get()
    #expect(line.provider == .deepseek && line.requestID == "c7c3e2a4" && line.model == "deepseek-chat")
    #expect(line.app == "weather-collector" && line.keyHint == "a9f2" && line.succeeded && !line.keyHintTruncated)
    #expect(DBTime.string(line.date) == "2026-11-09T14:03:21.512Z")
    #expect(line.classes == TokenClasses(inputUncached: 332, cacheRead: 1200, output: 212, requests: 1))
    #expect(line.usageJSON.contains("\"prompt_cache_hit_tokens\":1200"))
    #expect(line.classesJSON == "{\"cache_read\":1200,\"cache_write_1h\":0,\"cache_write_5m\":0," +
      "\"input_uncached\":332,\"output\":212,\"reasoning\":0,\"requests\":1}")
    #expect(line.unknownFields.isEmpty && line.costCents == nil)
  }

  /// One rejection case: the field, its new value as JSON text (nil removes the field), the rejection.
  struct Case: Sendable, CustomTestStringConvertible {
    var key: String
    var json: String?
    var rejection: LineRejection
    var testDescription: String { "\(key) = \(json ?? "(absent)")" }

    init(_ key: String, _ json: String?, _ rejection: LineRejection) {
      self.key = key
      self.json = json
      self.rejection = rejection
    }
  }

  @Test("each rejection reason and its 07 event", arguments: [
    Case("v", "2", .badVersion), Case("v", "\"1\"", .badVersion), Case("v", nil, .badVersion),
    Case("v", "true", .badVersion), Case("ts", "\"yesterday\"", .badField("ts")), Case("ts", nil, .badField("ts")),
    Case("provider", "\"gemini\"", .unknownProvider), Case("provider", "\"DeepSeek\"", .unknownProvider),
    Case("provider", "3", .unknownProvider), Case("app", "\"\"", .badApp), Case("app", "\"-leading\"", .badApp),
    Case("app", "\"has space\"", .badApp), Case("app", "\"" + String(repeating: "a", count: 65) + "\"", .badApp),
    Case("app", "7", .badApp), Case("request_id", "\"\"", .badField("request_id")),
    Case("request_id", "\"" + String(repeating: "r", count: 129) + "\"", .badField("request_id")),
    Case("request_id", nil, .badField("request_id")), Case("model", "\"\"", .badField("model")),
    Case("model", nil, .badField("model")), Case("usage", "\"1532\"", .badField("usage")), Case("usage", nil, .badField("usage")),
    Case("status", "\"failed\"", .badField("status")), Case("status", nil, .badField("status")),
    Case("key_hint", "9412", .badField("key_hint"))
  ])
  func rejections(_ item: Case) throws {
    let value = try item.json.map { try JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
    #expect(Self.parse(Self.changing(item.key, to: value)) == .failure(item.rejection))
  }

  @Test("bad JSON, a non-object, an over-long line; the events and which reject a whole file")
  func shapes() {
    #expect(LineParser.parse(Data("{not json".utf8)) == .failure(.badJSON))
    #expect(LineParser.parse(Data("[1,2]".utf8)) == .failure(.badJSON))
    #expect(LineParser.parse(Data(repeating: 0x20, count: LineParser.maxLineBytes + 1)) == .failure(.lineTooLong))
    #expect(LineRejection.badJSON.event == .ingestBadJson && LineRejection.badField("ts").event == .ingestBadJson)
    #expect(LineRejection.badVersion.event == .ingestBadVersion && LineRejection.badApp.event == .ingestBadApp)
    #expect(LineRejection.unknownProvider.event == .ingestUnknownProvider)
    #expect(LineRejection.lineTooLong.event == .ingestLineTooLong)
    #expect(LineRejection.badJSON.rejectsFile && LineRejection.badVersion.rejectsFile)
    #expect(!LineRejection.badApp.rejectsFile && !LineRejection.lineTooLong.rejectsFile)
  }

  @Test("key hint: `…` dropped, more than 12 characters truncated and flagged, only 4 kept")
  func keyHint() throws {
    let long = try Self.parse(Self.changing("key_hint", to: "sk-" + "proj-0123456789abcd")).get()
    #expect(long.keyHint == "abcd" && long.keyHintTruncated)
    let twelve = try Self.parse(Self.changing("key_hint", to: "0123456789ab")).get()
    #expect(twelve.keyHint == "89ab" && !twelve.keyHintTruncated)
    #expect(try Self.parse(Self.changing("key_hint", to: nil)).get().keyHint == nil)
    #expect(try Self.parse(Self.changing("key_hint", to: "")).get().keyHint == nil)
  }

  @Test("unknown top-level fields are listed; cost_cents counts for openrouter only; status error; ts forms")
  func fieldsAndForms() throws {
    var extra = Self.valid
    extra["zeta"] = 1
    extra["alpha"] = "x"
    extra["cost_cents"] = 9
    let line = try Self.parse(extra).get()
    #expect(line.unknownFields == ["alpha", "zeta"] && line.costCents == nil)
    var router = Self.changing("provider", to: "openrouter")
    router["cost_cents"] = 7
    router["usage"] = ["prompt_tokens": 100, "completion_tokens": 50]
    #expect(try Self.parse(router).get().costCents == 7)
    #expect(try Self.parse(Self.changing("status", to: "error")).get().succeeded == false)
    for ts in ["2026-11-09T14:03:21Z", "2026-11-09T16:03:21+02:00", "2026-11-09T14:03:21.5Z"] {
      let parsed = try Self.parse(Self.changing("ts", to: ts)).get()
      #expect(Int(parsed.date.timeIntervalSince1970) == 1_794_233_001, "\(ts)")
    }
    #expect(LineParser.isAppTag("a.b_c-9") && !LineParser.isAppTag("A"))
  }

  // MARK: - 05 per-response normalizers

  static func normalize(_ provider: ProviderID, _ usage: [String: Any]) -> HarnessNormalizer.Output {
    HarnessNormalizer.normalize(provider, usage: usage)
  }

  @Test("openai chat.completions and responses API rows")
  func openAI() {
    let chat = Self.normalize(.openai, ["prompt_tokens": 1000, "completion_tokens": 300,
                                        "prompt_tokens_details": ["cached_tokens": 400],
                                        "completion_tokens_details": ["reasoning_tokens": 120], "total_tokens": 1300])
    #expect(chat.classes == TokenClasses(inputUncached: 600, cacheRead: 400, output: 180, reasoning: 120, requests: 1))
    #expect(chat.unknownKeys.isEmpty && chat.missingKey == nil)
    let responses = Self.normalize(.openai, ["input_tokens": 50, "output_tokens": 20,
                                             "input_tokens_details": ["cached_tokens": 10],
                                             "output_tokens_details": ["reasoning_tokens": 5]])
    #expect(responses.classes == TokenClasses(inputUncached: 40, cacheRead: 10, output: 15, reasoning: 5, requests: 1))
    let router = Self.normalize(.openrouter, ["prompt_tokens": 10, "completion_tokens": 2, "cost": 0.01])
    #expect(router.classes == TokenClasses(inputUncached: 10, output: 2, requests: 1) && router.unknownKeys.isEmpty)
  }

  @Test("anthropic row: both cache_creation forms")
  func anthropic() {
    let split = Self.normalize(.anthropic, ["input_tokens": 10, "output_tokens": 7, "cache_read_input_tokens": 30,
                                            "cache_creation_input_tokens": 99,
                                            "cache_creation": ["ephemeral_5m_input_tokens": 20,
                                                               "ephemeral_1h_input_tokens": 5]])
    #expect(split.classes == TokenClasses(inputUncached: 10, cacheWrite5m: 20, cacheWrite1h: 5, cacheRead: 30,
                                          output: 7, requests: 1))
    let flat = Self.normalize(.anthropic, ["input_tokens": 10, "output_tokens": 7, "cache_creation_input_tokens": 99])
    #expect(flat.classes == TokenClasses(inputUncached: 10, cacheWrite5m: 99, output: 7, requests: 1))
  }

  @Test("deepseek and xai rows; a missing miss count falls back to prompt − hit")
  func deepSeekAndXAI() {
    let deepseek = Self.normalize(.deepseek, ["prompt_tokens": 1000, "completion_tokens": 100,
                                              "prompt_cache_hit_tokens": 700,
                                              "completion_tokens_details": ["reasoning_tokens": 40]])
    #expect(deepseek.classes == TokenClasses(inputUncached: 300, cacheRead: 700, output: 60, reasoning: 40, requests: 1))
    let xai = Self.normalize(.xai, ["prompt_tokens": 800, "completion_tokens": 100,
                                    "prompt_tokens_details": ["cached_tokens": 300], "num_sources_used": 0])
    #expect(xai.classes == TokenClasses(inputUncached: 500, cacheRead: 300, output: 100, requests: 1))
  }

  @Test("a missing required key fails; negatives clamp to 0 and are reported; unknown keys are listed")
  func failures() {
    for (provider, key) in [(ProviderID.openai, "prompt_tokens"), (.anthropic, "input_tokens"),
                            (.deepseek, "prompt_tokens"), (.xai, "prompt_tokens")] {
      let output = Self.normalize(provider, ["completion_tokens": 3])
      #expect(output.classes == nil && output.missingKey == key, "\(provider)")
    }
    let negative = Self.normalize(.xai, ["prompt_tokens": 10, "completion_tokens": 1, "brand_new": 1,
                                         "prompt_tokens_details": ["cached_tokens": 30],
                                         "completion_tokens_details": ["reasoning_tokens": 5]])
    #expect(negative.classes == TokenClasses(cacheRead: 30, reasoning: 5, requests: 1))
    #expect(negative.negative == ["input_uncached", "output"] && negative.unknownKeys == ["brand_new"])
    #expect(Self.normalize(.deepseek, ["prompt_tokens": true]).classes == nil, "a Boolean is not a count")
  }
}
