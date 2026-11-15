import Foundation

/// 05 § Burn, in cents per day over UTC days (14 § Stage 5.3 step 1).
public enum Burn {
  /// `burn_7d` gate: at least 2 of the last 7 closed days have data.
  public static let minimumClosedDays = 2
  /// `burn_today` gates: 2 h into the UTC day and at least $1 estimated today.
  public static let minimumSecondsToday: Int64 = 7200
  public static let minimumCentsToday: Int64 = 100

  /// The 7 closed UTC days before today, oldest first.
  public static func closedDays(now: Date) -> [String] {
    (1...7).reversed().map { DailyOnce.utcDay(now.addingTimeInterval(TimeInterval(-86_400 * $0))) }
  }

  /// `burn_7d = Σ spend over the last 7 closed UTC days ÷ 7`, rounded half-up; nil when fewer than 2 of those days
  /// have data (05). The per-day spend is `Spend.daily` (truth, else estimate).
  public static func sevenDay(daily: [String: SpendFigure], now: Date) -> Int64? {
    let figures = closedDays(now: now).compactMap { daily[$0] }
    guard figures.count >= minimumClosedDays else { return nil }
    return divideHalfUp(figures.reduce(0) { $0 + $1.cents }, by: 7)
  }

  /// `burn_today = spend_est(today) × 86400 / seconds_since_utc_midnight`, rounded half-up, only from 2 h into the
  /// UTC day and with at least 100 cents estimated today; nil otherwise (05).
  public static func today(daily: [String: SpendFigure], now: Date) -> Int64? {
    let seconds = secondsSinceUTCMidnight(now)
    guard seconds >= minimumSecondsToday, let spend = daily[DailyOnce.utcDay(now)]?.cents,
          spend >= minimumCentsToday else { return nil }
    return divideHalfUp(spend * 86_400, by: seconds)
  }

  static func secondsSinceUTCMidnight(_ now: Date) -> Int64 {
    let seconds = Int64(now.timeIntervalSince1970.rounded(.down))
    return ((seconds % 86_400) + 86_400) % 86_400
  }

  /// Half-up integer division for a non-negative numerator and a positive divisor; negatives round half away from 0.
  static func divideHalfUp(_ value: Int64, by divisor: Int64) -> Int64 {
    let (quotient, remainder) = value.quotientAndRemainder(dividingBy: divisor)
    if remainder * 2 >= divisor { return quotient + 1 }
    if remainder * 2 <= -divisor { return quotient - 1 }
    return quotient
  }
}
