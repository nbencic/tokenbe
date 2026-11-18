import Foundation

/// 05 § Normalizers, the per-response (harness) rows: a provider's `usage` object, as a harness line carries it
/// verbatim (06), into `TokenClasses`. One line is one request (`requests = 1`).
///
/// | Provider | inputUncached | cacheWrite5m | cacheWrite1h | cacheRead | output | reasoning |
/// |---|---|---|---|---|---|---|
/// | openai (chat.completions) | `prompt_tokens − prompt_tokens_details.cached_tokens` | 0 | 0 | `prompt_tokens_details.cached_tokens ?? 0` | `completion_tokens − completion_tokens_details.reasoning_tokens` | `completion_tokens_details.reasoning_tokens ?? 0` |
/// | openai (responses API) | `input_tokens − input_tokens_details.cached_tokens` | 0 | 0 | `input_tokens_details.cached_tokens ?? 0` | `output_tokens − output_tokens_details.reasoning_tokens` | `output_tokens_details.reasoning_tokens ?? 0` |
/// | anthropic | `input_tokens` | `cache_creation.ephemeral_5m_input_tokens ?? cache_creation_input_tokens ?? 0` | `cache_creation.ephemeral_1h_input_tokens ?? 0` | `cache_read_input_tokens ?? 0` | `output_tokens` | 0 |
/// | deepseek | `prompt_cache_miss_tokens ?? (prompt_tokens − prompt_cache_hit_tokens)` | 0 | 0 | `prompt_cache_hit_tokens ?? 0` | `completion_tokens − (completion_tokens_details.reasoning_tokens ?? 0)` | `completion_tokens_details.reasoning_tokens ?? 0` |
/// | xai | `prompt_tokens − (prompt_tokens_details.cached_tokens ?? 0)` | 0 | 0 | `prompt_tokens_details.cached_tokens ?? 0` | `completion_tokens − (completion_tokens_details.reasoning_tokens ?? 0)` | `completion_tokens_details.reasoning_tokens ?? 0` |
///
/// OpenAI's two shapes are told apart by `prompt_tokens` (chat) or `input_tokens` (responses). 05 has no
/// per-response OpenRouter row; OpenRouter returns OpenAI's chat shape, so it uses that row (Q-049). A missing
/// required key (`prompt_tokens` / `input_tokens`) fails normalization; an absent optional key is 0. A difference
/// below zero is clamped to 0 and reported (`normalize.negative`).
public enum HarnessNormalizer {
  public struct Output: Sendable, Equatable {
    /// Nil when a required key is missing.
    public var classes: TokenClasses?
    public var missingKey: String?
    /// Top-level usage keys this row does not read (`normalize.unknown_keys`).
    public var unknownKeys: [String]
    /// Fields whose difference was negative and clamped to 0 (`normalize.negative`).
    public var negative: [String]
  }

  public static func normalize(_ provider: ProviderID, usage: [String: Any]) -> Output {
    var reader = Reader(usage: usage)
    let classes: TokenClasses?
    let required: String
    let known: Set<String>
    switch provider {
    case .openai, .openrouter, .moonshot:
      if usage["input_tokens"] != nil && usage["prompt_tokens"] == nil {
        required = "input_tokens"
        known = ["input_tokens", "output_tokens", "total_tokens", "input_tokens_details", "output_tokens_details"]
        classes = reader.openAI(input: "input_tokens", output: "output_tokens", inputDetails: "input_tokens_details",
                                outputDetails: "output_tokens_details")
      } else {
        required = "prompt_tokens"
        known = ["prompt_tokens", "completion_tokens", "total_tokens", "prompt_tokens_details",
                 "completion_tokens_details", "cost", "is_byok", "cost_details"]
        classes = reader.openAI(input: "prompt_tokens", output: "completion_tokens",
                                inputDetails: "prompt_tokens_details", outputDetails: "completion_tokens_details")
      }
    case .anthropic:
      required = "input_tokens"
      known = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
               "cache_creation", "service_tier", "server_tool_use"]
      classes = reader.anthropic()
    case .deepseek:
      required = "prompt_tokens"
      known = ["prompt_tokens", "completion_tokens", "total_tokens", "prompt_cache_hit_tokens",
               "prompt_cache_miss_tokens", "prompt_tokens_details", "completion_tokens_details"]
      classes = reader.deepSeek()
    case .xai:
      required = "prompt_tokens"
      known = ["prompt_tokens", "completion_tokens", "total_tokens", "prompt_tokens_details",
               "completion_tokens_details", "num_sources_used"]
      classes = reader.xAI()
    }
    return Output(classes: classes, missingKey: classes == nil ? required : nil,
                  unknownKeys: usage.keys.filter { !known.contains($0) }.sorted(), negative: reader.negative)
  }

  /// Reads integer fields from the usage object; JSON booleans are not numbers.
  struct Reader {
    let usage: [String: Any]
    var negative: [String] = []

    func int(_ key: String, in object: [String: Any]? = nil) -> Int64? {
      guard let number = (object ?? usage)[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
        return nil
      }
      return number.int64Value
    }

    func object(_ key: String) -> [String: Any]? { usage[key] as? [String: Any] }

    mutating func difference(_ lhs: Int64, _ rhs: Int64, field: String) -> Int64 {
      let value = lhs - rhs
      if value < 0 { negative.append(field) }
      return max(0, value)
    }

    mutating func openAI(input: String, output: String, inputDetails: String, outputDetails: String) -> TokenClasses? {
      guard let prompt = int(input) else { return nil }
      let cached = int("cached_tokens", in: object(inputDetails)) ?? 0
      let reasoning = int("reasoning_tokens", in: object(outputDetails)) ?? 0
      return TokenClasses(inputUncached: difference(prompt, cached, field: "input_uncached"), cacheRead: cached,
                          output: difference(int(output) ?? 0, reasoning, field: "output"), reasoning: reasoning,
                          requests: 1)
    }

    func anthropic() -> TokenClasses? {
      guard let input = int("input_tokens") else { return nil }
      let creation = object("cache_creation")
      return TokenClasses(
        inputUncached: input,
        cacheWrite5m: int("ephemeral_5m_input_tokens", in: creation) ?? int("cache_creation_input_tokens") ?? 0,
        cacheWrite1h: int("ephemeral_1h_input_tokens", in: creation) ?? 0,
        cacheRead: int("cache_read_input_tokens") ?? 0, output: int("output_tokens") ?? 0, requests: 1
      )
    }

    mutating func deepSeek() -> TokenClasses? {
      guard let prompt = int("prompt_tokens") else { return nil }
      let hit = int("prompt_cache_hit_tokens") ?? 0
      let uncached = int("prompt_cache_miss_tokens") ?? difference(prompt, hit, field: "input_uncached")
      let reasoning = int("reasoning_tokens", in: object("completion_tokens_details")) ?? 0
      return TokenClasses(inputUncached: uncached, cacheRead: hit,
                          output: difference(int("completion_tokens") ?? 0, reasoning, field: "output"),
                          reasoning: reasoning, requests: 1)
    }

    mutating func xAI() -> TokenClasses? {
      guard let prompt = int("prompt_tokens") else { return nil }
      let cached = int("cached_tokens", in: object("prompt_tokens_details")) ?? 0
      let reasoning = int("reasoning_tokens", in: object("completion_tokens_details")) ?? 0
      return TokenClasses(inputUncached: difference(prompt, cached, field: "input_uncached"), cacheRead: cached,
                          output: difference(int("completion_tokens") ?? 0, reasoning, field: "output"),
                          reasoning: reasoning, requests: 1)
    }
  }
}
