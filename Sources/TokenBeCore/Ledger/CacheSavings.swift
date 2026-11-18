import Foundation

/// Why an account's cache savings are not computed (05 § Cache savings; the tile shows `—` with this reason).
public enum CacheSavingsGap: String, Error, Sendable, Equatable, CaseIterable {
  /// OpenAI's aggregate usage API under-reports cached tokens (02 quirk, D-openai-cache-savings-off).
  case openAIAggregate = "openai_aggregate"
  /// The provider reports no cache token classes (OpenRouter's harness lines carry a cost, not cache counts).
  case noCacheCounts = "no_cache_counts"
  /// Computed from harness reports (DeepSeek, xAI), and the range has none for the account.
  case noHarnessReports = "no_harness_reports"
  /// Computed from the provider's usage (Anthropic), and the range has none for the account.
  case noUsage = "no_usage"
}

/// One account's cache savings over the Dashboard range: net cents saved, or why they are not computed.
public enum CacheSavingsFigure: Sendable, Equatable {
  /// Net of write premiums; negative when cache writes cost more than cache reads saved. Always dollars: the price
  /// book is in USD (05 § Cost formula), whatever the account's currency (Q-052).
  case saved(cents: Int64)
  case notComputed(CacheSavingsGap)

  public var cents: Int64? {
    if case .saved(let cents) = self { return cents }
    return nil
  }
}

/// 05 § Cache savings (14 § Stage 8.2):
/// ```
/// saved = Σ cacheRead × (in − cache_read_rate) − Σ cacheWrite5m × (cache_write_5m_rate − in)
///       − Σ cacheWrite1h × (cache_write_1h_rate − in)
/// ```
/// i.e. what the cached tokens would have cost as plain input, minus what they cost, with `CostEstimator`'s rates
/// and fallbacks, in `Int128` picodollars rounded once. Anthropic counts its provider buckets and their retention
/// roll-ups (`rollup`, 9.1; PM-8.2-4); DeepSeek and xAI their harness buckets (per-response cache fields), which keep
/// `harness` when rolled up (Q-055); OpenAI and OpenRouter are not computed. Unpriced models are left out.
public enum CacheSavings {
  /// The usage sources the provider's savings are computed from, or why there are none.
  static func sources(_ provider: ProviderID) -> Result<Set<String>, CacheSavingsGap> {
    switch provider {
    case .anthropic: .success(["provider", "rollup"])
    case .deepseek, .xai: .success(["harness"])
    case .openai: .failure(.openAIAggregate)
    case .openrouter: .failure(.noCacheCounts)
    }
  }

  public static func figure(_ account: AccountSummary, days: [String], inputs: SummaryInputs,
                            pricer: Pricer) -> CacheSavingsFigure {
    let sources: Set<String>
    switch Self.sources(account.provider) {
    case .success(let value): sources = value
    case .failure(let gap): return .notComputed(gap)
    }
    let wanted = Set(days)
    let rows = inputs.modelUsageDays.filter {
      $0.accountId == account.id && sources.contains($0.source) && wanted.contains($0.day)
    }
    guard !rows.isEmpty else { return .notComputed(sources == ["harness"] ? .noHarnessReports : .noUsage) }
    var total: Int128 = 0
    for row in rows {
      guard let entry = pricer.lookup(provider: account.provider, model: row.model)?.entry else { continue }
      total = CostEstimator.sum(total, saved(row.classes, entry: entry) ?? 0)
    }
    return .saved(cents: CostEstimator.roundHalfUp(total))
  }

  /// The cached tokens' cost as plain input minus their cost, in picodollars × 20; nil when unpriced.
  static func saved(_ classes: TokenClasses, entry: PriceEntry) -> Int128? {
    var ignored: [String] = []
    var uncached = classes
    uncached.inputUncached = classes.inputUncached + classes.cacheRead + classes.cacheWrite5m + classes.cacheWrite1h
    uncached.cacheRead = 0
    uncached.cacheWrite5m = 0
    uncached.cacheWrite1h = 0
    guard let plain = CostEstimator.total(uncached, entry: entry, fallbacks: &ignored),
          let actual = CostEstimator.total(classes, entry: entry, fallbacks: &ignored) else { return nil }
    return CostEstimator.sum(plain, -actual)
  }

  /// The tile's headline (08: `Saved $12 via cache (net of writes)`): Σ the accounts' computed savings, in dollars;
  /// nil when no account's savings are computed.
  public static func total(_ accounts: [AccountSummary]) -> Int64? {
    let computed = accounts.compactMap { $0.cacheSavings?.cents }
    return computed.isEmpty ? nil : computed.reduce(0, +)
  }
}
