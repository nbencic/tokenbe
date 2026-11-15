import Foundation

/// 05 § Runway (14 § Stage 5.3 step 1): `remaining ÷ burn`, in seconds (a ratio, not money).
public enum Runway {
  public struct Paces: Sendable, Equatable {
    public var sevenDay: TimeInterval?
    public var today: TimeInterval?
    /// The smaller of the two that exist; nil when neither does.
    public var minimum: TimeInterval? { [sevenDay, today].compactMap { $0 }.min() }

    public init(sevenDay: TimeInterval?, today: TimeInterval?) {
      self.sevenDay = sevenDay
      self.today = today
    }
  }

  /// `runway_7d = remaining / burn_7d` (nil if either is nil or burn is 0); `runway_today = remaining / burn_today`.
  /// A remaining at or below zero is no runway left (0 s).
  public static func paces(remaining: Int64?, burn7d: Int64?, burnToday: Int64?) -> Paces {
    Paces(sevenDay: seconds(remaining, burn7d), today: seconds(remaining, burnToday))
  }

  static func seconds(_ remaining: Int64?, _ burn: Int64?) -> TimeInterval? {
    guard let remaining, let burn, burn > 0 else { return nil }
    guard remaining > 0 else { return 0 }
    return TimeInterval(remaining) / TimeInterval(burn) * 86_400
  }
}
