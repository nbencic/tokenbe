import Foundation

/// 05 § Normalizers, row "openai usage API":
///
/// | inputUncached | cacheWrite5m | cacheWrite1h | cacheRead | output | reasoning |
/// |---|---|---|---|---|---|
/// | `input_tokens − input_cached_tokens` (floor at 0; if negative log `normalize.negative`) | `input_cache_write_tokens ?? 0` | 0 | `input_cached_tokens` | `output_tokens` | 0 |
///
/// `requests` is `num_model_requests` (0 when absent). Audio token counts are not a 05 class and are not used.
enum OpenAINormalizer {
  static func classes(_ result: OpenAIUsageResult, log: EventLog) -> TokenClasses {
    let uncached = result.inputTokens - result.inputCachedTokens
    if uncached < 0 {
      log.emit(.warn, .normalizeNegative, cat: .normalize, msg: "negative input_uncached clamped to 0", ctx: [
        "provider": .string(ProviderID.openai.rawValue), "field": "input_uncached", "value": .int(Int(uncached))
      ])
    }
    return TokenClasses(
      inputUncached: max(0, uncached),
      cacheWrite5m: result.inputCacheWriteTokens ?? 0,
      cacheWrite1h: 0,
      cacheRead: result.inputCachedTokens,
      output: result.outputTokens,
      reasoning: 0,
      requests: result.numModelRequests ?? 0
    )
  }
}
