import Foundation

/// 05 § Estimate band `M` (cents) for an anchored account (14 § Stage 5.3 step 1):
/// ```
/// drift      = spend_since_anchor × 0.03
/// unreported = burn_7d × usageLag / 86400
/// unpriced   = unpriced_cents(since anchor)
/// age_factor = max(1, 1 + 0.5 × floor((now − anchor.ts) / anchor_age_days))
/// M          = (drift + unreported + unpriced) × age_factor
/// ```
/// Each term rounds up to whole cents, and so does `M` (05: "M rounded UP"), so the band never understates (Q-042).
public enum EstimateBand {
  public struct Inputs: Sendable, Equatable {
    public var spendSinceAnchor: Int64
    public var burn7d: Int64?
    public var usageLagSeconds: Int64
    public var unpricedCents: Int64
    /// Whole seconds since the anchor.
    public var anchorAgeSeconds: Int64
    public var anchorAgeDays: Int

    public init(spendSinceAnchor: Int64, burn7d: Int64?, usageLagSeconds: Int64, unpricedCents: Int64,
                anchorAgeSeconds: Int64, anchorAgeDays: Int) {
      self.spendSinceAnchor = spendSinceAnchor
      self.burn7d = burn7d
      self.usageLagSeconds = usageLagSeconds
      self.unpricedCents = unpricedCents
      self.anchorAgeSeconds = anchorAgeSeconds
      self.anchorAgeDays = anchorAgeDays
    }
  }

  public static func cents(_ inputs: Inputs) -> Int64 {
    let drift = divideUp(max(0, inputs.spendSinceAnchor) * 3, by: 100)
    let unreported = divideUp(max(0, inputs.burn7d ?? 0) * max(0, inputs.usageLagSeconds), by: 86_400)
    let sum = drift + unreported + max(0, inputs.unpricedCents)
    // age_factor in halves: 2 × (1 + 0.5 × steps) = 2 + steps.
    let steps = max(0, inputs.anchorAgeSeconds) / (Int64(max(1, inputs.anchorAgeDays)) * 86_400)
    return divideUp(sum * (2 + steps), by: 2)
  }

  static func divideUp(_ value: Int64, by divisor: Int64) -> Int64 {
    let (quotient, remainder) = value.quotientAndRemainder(dividingBy: divisor)
    return remainder > 0 ? quotient + 1 : quotient
  }
}
