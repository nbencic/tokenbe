import Foundation

/// 05 § Price lookup: a deterministic order, the first hit wins.
/// 1. `price_override[model]`
/// 2. feed key `model` exactly
/// 3. feed key `"{litellm_provider_prefix}/{model}"` (only deepseek, xai and openrouter have a prefix)
/// 4. the model with a trailing date suffix (`-YYYYMMDD`, `-YYYY-MM-DD`) stripped, applied to 2 and 3
/// 5. the model with `-latest` appended, applied to 2 and 3
/// 6. unpriced (`nil`)
/// A hit whose input or output rate is missing or ≤ 0 is unpriced (V5): lookup never returns a zero price.
public enum Lookup {
  /// Which step found the entry (logged and tested).
  public enum Step: Int, Sendable, Equatable {
    case override = 1, exact, prefixed, dateStripped, latest
  }

  public struct Hit: Sendable, Equatable {
    public var entry: PriceEntry
    public var step: Step
    /// The override model or feed key that matched.
    public var key: String
  }

  public static func find(provider: ProviderID, model: String, overrides: [String: PriceEntry],
                          feed: [String: PriceEntry]) -> Hit? {
    guard let hit = firstHit(provider: provider, model: model, overrides: overrides, feed: feed),
          hit.entry.isPriced else { return nil }
    return hit
  }

  /// The first matching key, priced or not (V5 is applied by `find`).
  static func firstHit(provider: ProviderID, model: String, overrides: [String: PriceEntry],
                       feed: [String: PriceEntry]) -> Hit? {
    if let entry = overrides[model] { return Hit(entry: entry, step: .override, key: model) }
    let candidates: [(String, Step)] = [(model, .exact)]
      + (stripDate(model).map { [($0, .dateStripped)] } ?? [])
      + [(model + "-latest", .latest)]
    for (name, step) in candidates {
      for key in keys(provider: provider, name: name) {
        if let entry = feed[key] {
          return Hit(entry: entry, step: step == .exact && key != name ? .prefixed : step, key: key)
        }
      }
    }
    return nil
  }

  /// Steps 2 and 3 for one name: the bare key, then the prefixed one.
  static func keys(provider: ProviderID, name: String) -> [String] {
    guard let prefix = prefix(provider) else { return [name] }
    return [name, "\(prefix)/\(name)"]
  }

  /// 05: OpenAI and Anthropic keys are bare.
  public static func prefix(_ provider: ProviderID) -> String? {
    switch provider {
    case .openai, .anthropic: nil
    case .deepseek: "deepseek"
    case .xai: "xai"
    case .openrouter: "openrouter"
    }
  }

  /// `claude-sonnet-4-20250514` → `claude-sonnet-4`; `gpt-4o-2024-08-06` → `gpt-4o`; nil without a date suffix.
  public static func stripDate(_ model: String) -> String? {
    for pattern in [#"-\d{4}-\d{2}-\d{2}$"#, #"-\d{8}$"#] {
      if let range = model.range(of: pattern, options: .regularExpression), range.lowerBound > model.startIndex {
        return String(model[..<range.lowerBound])
      }
    }
    return nil
  }
}
