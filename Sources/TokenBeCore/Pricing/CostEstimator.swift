import Foundation

/// 05 § Cost formula, per bucket, in integer cents rounded half-up once at the end (14 § Stage 5.2 step 1):
/// ```
/// cost = inputUncached × in
///      + cacheWrite5m × (cache_creation_input_token_cost ?? in × 1.25)
///      + cacheWrite1h × (cache_creation_input_token_cost_above_1hr ?? cache_creation_input_token_cost ?? in × 2.0)
///      + cacheRead × (cache_read_input_token_cost ?? in × 0.1)
///      + output × out
///      + reasoning × out
/// ```
/// Rates are picodollars per token (Q-038); 1 cent is 10^10 picodollars. Every term is summed over the common
/// denominator 20 (1.25 = 25/20, 2.0 = 40/20, 0.1 = 2/20) in `Int128`, so no fallback multiplier truncates before the
/// single rounding (Q-040). The `_above_200k_tokens` variants are not applied (05, O-7). Priority and batch tiers
/// use the standard rate (05).
public enum CostEstimator {
  /// What pricing one bucket found.
  public struct Estimate: Sendable, Equatable {
    /// Nil when the model is unpriced (05 § Price lookup step 6, V5).
    public var cents: Int64?
    /// The feed fields that were missing for a class with tokens, so their 05 fallback multiplier was used.
    public var fallbackFields: [String]
    /// The bucket's tier is `priority` or `batch` and was priced at the standard rate (05 § Service tier).
    public var tierPricedAsStandard: Bool

    public init(cents: Int64?, fallbackFields: [String] = [], tierPricedAsStandard: Bool = false) {
      self.cents = cents
      self.fallbackFields = fallbackFields
      self.tierPricedAsStandard = tierPricedAsStandard
    }

    public var isUnpriced: Bool { cents == nil }
  }

  /// 05: tiers that have their own price but are priced as standard in V1.
  public static let nonStandardTiers: Set<String> = ["priority", "batch"]

  /// Picodollars per cent, times the common denominator.
  static let divisor: Int128 = 10_000_000_000 * 20

  /// The bucket's cost under `entry`; nil `entry` (or one V5 rejects) is unpriced.
  public static func estimate(_ classes: TokenClasses, entry: PriceEntry?, serviceTier: String = "") -> Estimate {
    guard let entry, entry.isPriced, let input = entry.input, let output = entry.output else {
      return Estimate(cents: nil)
    }
    var fallbacks: [String] = []
    /// Tokens × rate × 20; a missing rate uses `input × numerator / 20` and is recorded when the class has tokens.
    func term(_ tokens: Int64, _ rate: PriceEntry.Rate?, fallbackNumerator: Int128, field: String) -> Int128 {
      if let rate { return product(tokens, rate, 20) }
      if tokens != 0 { fallbacks.append(field) }
      return product(tokens, input, fallbackNumerator)
    }
    let write1h = entry.cacheWrite1h ?? entry.cacheWrite
    let total = [
      product(classes.inputUncached, input, 20),
      term(classes.cacheWrite5m, entry.cacheWrite, fallbackNumerator: 25, field: PriceEntry.Key.cacheWrite),
      term(classes.cacheWrite1h, write1h, fallbackNumerator: 40, field: PriceEntry.Key.cacheWrite1h),
      term(classes.cacheRead, entry.cacheRead, fallbackNumerator: 2, field: PriceEntry.Key.cacheRead),
      product(classes.output, output, 20),
      product(classes.reasoning, output, 20)
    ].reduce(Int128(0), sum)
    return Estimate(cents: roundHalfUp(total), fallbackFields: fallbacks,
                    tierPricedAsStandard: nonStandardTiers.contains(serviceTier))
  }

  /// The bucket row with `est_cost_cents` and `unpriced` set (03: NULL and 1 when unpriced).
  public static func priced(_ row: UsageBucketRecord, entry: PriceEntry?) -> (UsageBucketRecord, Estimate) {
    let estimate = estimate(row.classes, entry: entry, serviceTier: row.serviceTier)
    var copy = row
    copy.estCostCents = estimate.cents
    copy.unpriced = estimate.isUnpriced
    return (copy, estimate)
  }

  /// tokens × rate × numerator, saturating: a garbled rate or count can never trap (R5: degrade, never crash).
  static func product(_ tokens: Int64, _ rate: Int64, _ numerator: Int128) -> Int128 {
    let (first, overflow1) = Int128(tokens).multipliedReportingOverflow(by: Int128(rate))
    let (value, overflow2) = first.multipliedReportingOverflow(by: numerator)
    guard !overflow1, !overflow2 else { return (tokens < 0) != (rate < 0) ? .min : .max }
    return value
  }

  /// A saturating sum.
  static func sum(_ lhs: Int128, _ rhs: Int128) -> Int128 {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    guard overflow else { return value }
    return rhs > 0 ? .max : .min
  }

  /// Half-up for a non-negative total; token counts are never negative (05 floors them at 0). Clamped to `Int64`.
  static func roundHalfUp(_ total: Int128) -> Int64 {
    let magnitude = total == .min ? Int128.max : abs(total)
    let rounded = magnitude / divisor + (magnitude % divisor >= divisor / 2 ? 1 : 0)
    let value = total >= 0 ? rounded : -rounded
    return Int64(clamping: value)
  }
}
